import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from verify_portable_export import InvalidExport, MANIFEST, Reader, parse_manifest, relative_path


class MemoryReader(Reader):
    def __init__(self, payloads, manifest=None, directories=()):
        self.payloads = payloads
        self.directories = set(directories)
        self.manifest = manifest or {
            "schema": "waglock-portable-export-experiment-1", "fixtureOnly": True,
            "files": [{"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()} for path, data in payloads.items()],
            "directories": list(directories), "nestedVaults": [],
        }
        self.manifest_reads = 0

    def read(self, path, method="GET"):
        if path == MANIFEST:
            self.manifest_reads += 1
            return json.dumps(self.manifest).encode()
        return self.payloads[path]

    def inventory(self):
        return set(self.payloads) | {MANIFEST}, self.directories


class RecoveryTests(unittest.TestCase):
    def test_traversal_absolute_control_and_windows_paths_rejected(self):
        for path in ["../file", "/root", "a//b", "a/./b", "a/../b", "a\\b", "C:drive", "nul\0", "a\n", "x/" * 20 + "leaf"]:
            with self.subTest(path=repr(path)), self.assertRaises(InvalidExport):
                relative_path(path)
        self.assertEqual(relative_path("Photos/家族–café.txt"), "Photos/家族–café.txt")

    def test_duplicate_json_keys_and_duplicate_paths_rejected(self):
        with self.assertRaises(InvalidExport):
            parse_manifest(b'{"schema":"a","schema":"b"}')
        reader = MemoryReader({"file": b"x"})
        reader.manifest["files"].append(dict(reader.manifest["files"][0]))
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))

    def test_bad_lengths_hashes_nested_roots_and_resource_limits_rejected(self):
        for field, value in [("bytes", -1), ("bytes", True), ("bytes", 5 * 1024 * 1024), ("sha256", "bad")]:
            reader = MemoryReader({"file": b"x"})
            reader.manifest["files"][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(InvalidExport):
                parse_manifest(reader.read(MANIFEST))
        reader = MemoryReader({"file": b"x"})
        reader.manifest["nestedVaults"] = ["missing"]
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))

    def test_unicode_binary_and_empty_files_verified_before_publication(self):
        with tempfile.TemporaryDirectory() as root:
            reader = MemoryReader({"Photos/家族–café.bin": bytes(range(256)), "empty": b""}, directories=["Photos"])
            destination = Path(root) / "recovered"
            result = reader.recover(destination)
            self.assertEqual(result["files"], 2)
            self.assertEqual((destination / "Photos/家族–café.bin").read_bytes(), bytes(range(256)))
            self.assertEqual((destination / "empty").read_bytes(), b"")
            self.assertFalse(destination.with_name("recovered.partial").exists())

    def test_wrong_hash_or_truncation_cleans_its_partial_output_only(self):
        for replacement in [b"wrong", b"orig"]:
            with tempfile.TemporaryDirectory() as root:
                reader = MemoryReader({"first": b"keep", "second": b"original"})
                reader.payloads["second"] = replacement
                sentinel = Path(root) / "unrelated"
                sentinel.write_bytes(b"keep")
                destination = Path(root) / "recovered"
                with self.assertRaises(InvalidExport):
                    reader.recover(destination)
                self.assertFalse(destination.exists())
                self.assertFalse(destination.with_name("recovered.partial").exists())
                self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_missing_or_extra_inventory_fails_closed(self):
        for actual in [{"file", "extra", MANIFEST}, {MANIFEST}]:
            reader = MemoryReader({"file": b"data"})
            reader.inventory = lambda: (actual, set())
            with tempfile.TemporaryDirectory() as root, self.assertRaises(InvalidExport):
                reader.recover(Path(root) / "recovered")

    def test_existing_destination_and_unowned_partial_are_preserved(self):
        for leaf in ["recovered", "recovered.partial"]:
            with tempfile.TemporaryDirectory() as root:
                occupied = Path(root) / leaf
                occupied.mkdir()
                sentinel = occupied / "keep"
                sentinel.write_bytes(b"keep")
                with self.assertRaises((InvalidExport, FileExistsError)):
                    MemoryReader({"file": b"data"}).recover(Path(root) / "recovered")
                self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_dangling_destination_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as root:
            destination = Path(root) / "recovered"
            destination.symlink_to(Path(root) / "absent")
            with self.assertRaises(InvalidExport):
                MemoryReader({"file": b"data"}).recover(destination)
            self.assertTrue(destination.is_symlink())
            self.assertFalse((Path(root) / "absent").exists())

    def test_mid_read_failure_removes_only_owned_staging(self):
        with tempfile.TemporaryDirectory() as root:
            reader = MemoryReader({"first": b"ok", "second": b"data"})
            read = reader.read
            def interrupted(path, method="GET"):
                if path == "second":
                    raise OSError("injected read failure")
                return read(path, method)
            reader.read = interrupted
            destination = Path(root) / "recovered"
            with self.assertRaises(OSError):
                reader.recover(destination)
            self.assertFalse(destination.exists())
            self.assertFalse(destination.with_name("recovered.partial").exists())

    def test_manifest_change_before_publication_rejects_recovery(self):
        with tempfile.TemporaryDirectory() as root:
            reader = MemoryReader({"file": b"data"})
            read = reader.read
            def changed(path, method="GET"):
                if path == MANIFEST and reader.manifest_reads:
                    reader.manifest["files"][0]["bytes"] = 0
                return read(path, method)
            reader.read = changed
            destination = Path(root) / "recovered"
            with self.assertRaises(InvalidExport):
                reader.recover(destination)
            self.assertFalse(destination.exists())
            self.assertFalse(destination.with_name("recovered.partial").exists())

    def test_non_loopback_and_redirecting_reader_rejected(self):
        for url in ["https://example.com/vault", "http://192.168.1.2/vault", "http://localhost/vault?secret=x"]:
            with self.assertRaises(InvalidExport):
                Reader(url)


if __name__ == "__main__":
    unittest.main()
