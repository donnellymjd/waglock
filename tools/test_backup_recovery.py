import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from backup_recovery import InvalidBackup, recover, unpack_verified

ASSET = "12345678-1234-4321-ABCD-123456789ABC"
ALBUM = "23456789-2345-4321-ABCD-123456789ABC"
NOTE = "34567890-3456-4321-ABCD-123456789ABC"


def metadata(domain="root", parent=None):
    return {"schema": "waglock-backup-metadata-1", "domain": domain, "parent": parent,
        "assets": [], "albums": [], "notes": [], "drafts": [], "children": [],
        "notIncluded": ["deviceSettings", "FaceIDRegistrations", "nativeKeychainCredentials"], "trash": "notImplemented"}


def archive(meta=None, files=None, edit_manifest=None, extra_entries=()):
    meta = meta if meta is not None else metadata()
    payloads = {"metadata.json": json.dumps(meta, ensure_ascii=True).encode(), **(files or {})}
    manifest = {"schema": "waglock-backup-manifest-1", "files": [
        {"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()} for path, data in payloads.items()],
        "nested": [p for p in payloads if p.startswith("protected/")]}
    if edit_manifest:
        edit_manifest(manifest)
    pairs = list(payloads.items()) + list(extra_entries) + [("manifest.json", json.dumps(manifest).encode())]
    out = io.BytesIO()
    for path, data in pairs:
        info = tarfile.TarInfo(path); info.mode = 0o600; info.size = len(data)
        out.write(info.tobuf(format=tarfile.USTAR_FORMAT)); out.write(data); out.write(bytes((-len(data)) % 512))
    out.write(bytes(1024))
    return out.getvalue()


def asset_record():
    return {"id": ASSET, "albumID": None, "name": "家族 cafe\u0301", "fileExtension": ".bin",
        "storedType": "document", "effectiveType": "document", "declaredBytes": 256,
        "createdAt": 42, "modifiedAt": 43, "width": None, "height": None, "duration": None,
        "payload": "media/" + ASSET, "thumbnail": "thumbnails/" + ASSET}


class BackupRecoveryTests(unittest.TestCase):
    def unpack(self, data, **kwargs):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "input.tar"; source.write_bytes(data)
            stage = Path(root) / "stage"; stage.mkdir()
            result = unpack_verified(source, stage, **kwargs)
            return result, {p.relative_to(stage).as_posix(): p.read_bytes() for p in stage.rglob("*") if p.is_file()}

    def test_binary_unicode_notes_drafts_thumbnails_and_inventory_preserved(self):
        meta = metadata(); meta["assets"] = [asset_record()]
        meta["notes"] = [{"id": NOTE, "title": "café", "content": "# Public 家族", "createdAt": 42, "modifiedAt": 43, "isFavorite": True, "tags": ["cafe\u0301"]}]
        meta["drafts"] = [{"origin": "keychain", "title": "saved", "content": "draft", "updatedAt": 44}]
        result, files = self.unpack(archive(meta, {"media/" + ASSET: bytes(range(256)), "thumbnails/" + ASSET: b"thumbnail"}))
        self.assertEqual(result["files"], 3)
        self.assertEqual(files["media/" + ASSET], bytes(range(256)))
        self.assertEqual(json.loads(files["metadata.json"])["assets"][0]["name"].encode(), meta["assets"][0]["name"].encode())

    def test_modified_missing_or_extra_payload_fails_completeness(self):
        meta = metadata(); meta["assets"] = [asset_record()]
        files = {"media/" + ASSET: bytes(range(256)), "thumbnails/" + ASSET: b"thumbnail"}
        for mutate in [lambda m: m["files"].pop(), lambda m: m["files"][1].update(sha256="0" * 64), lambda m: m["files"][1].update(bytes=1)]:
            with self.subTest(mutate=mutate), self.assertRaises(InvalidBackup):
                self.unpack(archive(meta, files, edit_manifest=mutate))
        with self.assertRaises(InvalidBackup):
            self.unpack(archive(metadata(), {"media/" + ASSET: b"unreferenced"}))

    def test_traversal_links_duplicate_names_and_header_damage_rejected(self):
        for path in ["../escape", "/absolute", "media/../escape", "media/not-a-uuid"]:
            with self.subTest(path=path), self.assertRaises(InvalidBackup):
                self.unpack(archive(extra_entries=[(path, b"data")]))
        with self.assertRaises(InvalidBackup):
            self.unpack(archive(extra_entries=[("metadata.json", b"duplicate")]))
        linked = bytearray(archive()); linked[156] = ord("2")
        linked[148:156] = b"        "
        checksum = sum(linked[:512]); linked[148:156] = f"{checksum:06o}\0 ".encode()
        with self.assertRaises(InvalidBackup):
            self.unpack(bytes(linked))
        damaged = bytearray(archive()); damaged[5] ^= 1
        with self.assertRaises(InvalidBackup):
            self.unpack(bytes(damaged))

    def test_truncation_extra_bytes_missing_manifest_and_resource_limits_rejected(self):
        data = archive()
        for candidate in [data[:-1], data[:-1024], data + b"extra", data[:512] + bytes(1024)]:
            with self.subTest(length=len(candidate)), self.assertRaises(InvalidBackup):
                self.unpack(candidate)
        with self.assertRaises(InvalidBackup):
            self.unpack(data, max_bytes=1)
        with self.assertRaises(InvalidBackup):
            self.unpack(data, max_entries=1)

    def test_malformed_schema_coverage_dates_or_unicode_rejected(self):
        for key, value in [("schema", "future"), ("trash", "silently-omitted"), ("notIncluded", []), ("children", [ALBUM])]:
            meta = metadata(); meta[key] = value
            with self.subTest(key=key), self.assertRaises(InvalidBackup):
                self.unpack(archive(meta))
        for bad in [float("nan"), float("inf"), True, "yesterday"]:
            meta = metadata(); record = asset_record(); record["createdAt"] = bad; meta["assets"] = [record]
            with self.subTest(bad=bad), self.assertRaises(InvalidBackup):
                self.unpack(archive(meta, {"media/" + ASSET: b"data", "thumbnails/" + ASSET: b"thumb"}))
        meta = metadata(); record = asset_record(); record["name"] = "bad\ud800"; meta["assets"] = [record]
        with self.assertRaises(InvalidBackup):
            self.unpack(archive(meta, {"media/" + ASSET: b"x", "thumbnails/" + ASSET: b"y"}))

    def test_album_cycles_and_protected_metadata_in_wrong_domain_rejected(self):
        for policy, parent in [("password", None), ("inherited", ALBUM), ("inherited", NOTE)]:
            meta = metadata(); meta["albums"] = [{"id": ALBUM, "parentID": parent, "name": "Album", "protection": policy, "createdAt": 42}]
            with self.subTest(policy=policy, parent=parent), self.assertRaises(InvalidBackup):
                self.unpack(archive(meta))

    @staticmethod
    def fake_age(command):
        source = Path(command[-1]); output = Path(command[command.index("--output") + 1])
        if source.read_bytes() == b"bad child":
            return subprocess.CompletedProcess(command, 1)
        output.write_bytes(source.read_bytes())
        return subprocess.CompletedProcess(command, 0)

    def test_recursive_recovery_verifies_children_before_publication(self):
        child = metadata(ALBUM, "root"); child["albums"] = [{"id": ALBUM, "parentID": None, "name": "Protected", "protection": "password", "createdAt": 42}]
        root = metadata(); root["children"] = [ALBUM]
        for child_data, succeeds in [(archive(child), True), (b"bad child", False)]:
            with self.subTest(succeeds=succeeds), tempfile.TemporaryDirectory() as folder:
                source = Path(folder) / "backup.age"; source.write_bytes(archive(root, {"protected/" + ALBUM + ".tar.age": child_data}))
                original = source.read_bytes(); destination = Path(folder) / "recovered"
                with patch("backup_recovery.subprocess.run", side_effect=self.fake_age):
                    if succeeds:
                        result = recover(source, destination, "fixture-age")
                        self.assertTrue(result["allProtectedDomainsRecovered"])
                        self.assertEqual(len(result["domains"]), 2)
                    else:
                        with self.assertRaises(InvalidBackup):
                            recover(source, destination, "fixture-age")
                        self.assertFalse(destination.exists())
                self.assertFalse(destination.with_name("recovered.partial").exists())
                self.assertEqual(source.read_bytes(), original)

    def test_existing_output_unowned_partial_and_late_destination_are_preserved(self):
        for kind in ["destination", "partial", "late"]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as folder:
                source = Path(folder) / "source.age"; source.write_bytes(archive())
                destination = Path(folder) / "recovered"
                occupied = destination.with_name("recovered.partial") if kind == "partial" else destination
                if kind != "late": occupied.mkdir()
                def run(command):
                    result = self.fake_age(command)
                    if kind == "late": occupied.mkdir()
                    return result
                with patch("backup_recovery.subprocess.run", side_effect=run), self.assertRaises((InvalidBackup, OSError)):
                    recover(source, destination, "fixture-age")
                self.assertTrue(occupied.is_dir())
                self.assertEqual(list(occupied.iterdir()), [])

    def test_decrypt_disk_and_ciphertext_budgets_checked_before_age(self):
        for low_disk in (False, True):
            with self.subTest(low_disk=low_disk), tempfile.TemporaryDirectory() as folder:
                source = Path(folder) / "source.age"
                source.write_bytes(b"x" * 30000)
                destination = Path(folder) / "recovered"
                usage = type("Usage", (), {"free": 0 if low_disk else 10 ** 9})()
                with patch("backup_recovery.subprocess.run") as decrypt, patch("backup_recovery.shutil.disk_usage", return_value=usage):
                    with self.assertRaises(InvalidBackup):
                        recover(source, destination, "fixture-age", max_bytes=100000 if low_disk else 1, max_entries=1)
                    decrypt.assert_not_called()
                self.assertFalse(destination.exists())
                self.assertFalse(destination.with_name("recovered.partial").exists())
                self.assertEqual(source.stat().st_size, 30000)

    def test_outer_only_explicitly_retains_unopened_child_ciphertext(self):
        meta = metadata(); meta["children"] = [ALBUM]
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source.age"; source.write_bytes(archive(meta, {"protected/" + ALBUM + ".tar.age": b"unopened ciphertext"}))
            destination = Path(folder) / "recovered"
            with patch("backup_recovery.subprocess.run", side_effect=self.fake_age):
                result = recover(source, destination, "fixture-age", outer_only=True)
            self.assertFalse(result["allProtectedDomainsRecovered"])
            self.assertEqual((destination / "root/protected" / (ALBUM + ".tar.age")).read_bytes(), b"unopened ciphertext")


if __name__ == "__main__":
    unittest.main()
