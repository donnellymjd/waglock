import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from verify_portable_export import InvalidExport, MANIFEST, MAX_ENTRIES, MAX_FILE, Reader, parse_manifest, relative_path


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


class HostileRecoveryTests(unittest.TestCase):
    def test_destination_created_during_recovery_is_never_replaced(self):
        for kind in ["empty-directory", "file", "symlink"]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as root:
                destination = Path(root) / "recovered"
                reader = MemoryReader({"file": b"fixture"})
                read = reader.read
                before = []
                def competing_destination(path, method="GET"):
                    if path == MANIFEST and reader.manifest_reads:
                        if kind == "empty-directory":
                            destination.mkdir()
                        elif kind == "file":
                            destination.write_bytes(b"unrelated")
                        else:
                            destination.symlink_to(Path(root) / "absent")
                        before.append(destination.lstat().st_ino)
                    return read(path, method)
                reader.read = competing_destination
                with self.assertRaises(OSError):
                    reader.recover(destination)
                self.assertEqual(destination.lstat().st_ino, before[0])
                self.assertFalse(destination.with_name("recovered.partial").exists())
                if kind == "empty-directory":
                    self.assertEqual(list(destination.iterdir()), [])
                elif kind == "file":
                    self.assertEqual(destination.read_bytes(), b"unrelated")
                else:
                    self.assertTrue(destination.is_symlink())
                    self.assertFalse((Path(root) / "absent").exists())

    def test_inventory_changed_after_payload_read_prevents_publication(self):
        for changed in [({MANIFEST}, set()), ({"file", "extra", MANIFEST}, set()),
                        ({"file", MANIFEST}, {"new-directory"})]:
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as root:
                reader = MemoryReader({"file": b"data"})
                calls = []
                def inventory():
                    calls.append(True)
                    return ({"file", MANIFEST}, set()) if len(calls) == 1 else changed
                reader.inventory = inventory
                destination = Path(root) / "recovered"
                with self.assertRaises(InvalidExport):
                    reader.recover(destination)
                self.assertFalse(destination.exists())
                self.assertFalse(destination.with_name("recovered.partial").exists())

    def test_case_and_unicode_aliases_rejected_without_renaming_user_data(self):
        for paths in [["Photo", "photo"], ["café", "cafe\u0301"], ["WAGLOCK-MANIFEST.JSON"]]:
            reader = MemoryReader({path: b"data" for path in paths})
            with self.subTest(paths=paths), self.assertRaises(InvalidExport):
                parse_manifest(reader.read(MANIFEST))
        reader = MemoryReader({"Photos/a": b"data"}, directories=["photos"])
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))

    def test_missing_parents_file_as_parent_and_reserved_manifest_directory_rejected(self):
        cases = [MemoryReader({"a/b": b"x"}), MemoryReader({"a": b"x", "a/b": b"y"}),
                 MemoryReader({}, directories=["a/b"]), MemoryReader({}, directories=[MANIFEST])]
        for reader in cases:
            with self.subTest(manifest=reader.manifest), self.assertRaises(InvalidExport):
                parse_manifest(reader.read(MANIFEST))

    def test_unknown_schema_fields_and_entry_fields_rejected(self):
        reader = MemoryReader({"a": b"x"})
        reader.manifest["futurePolicy"] = "ignored"
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))
        del reader.manifest["futurePolicy"]
        reader.manifest["files"][0]["symlink"] = "outside"
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))

    def test_inventory_budget_includes_manifest_and_rejects_excess_totals(self):
        reader = MemoryReader({str(i): b"" for i in range(MAX_ENTRIES - 1)})
        self.assertEqual(len(parse_manifest(reader.read(MANIFEST))[0]), MAX_ENTRIES - 1)
        reader.manifest["files"].append({"path": "one-too-many", "bytes": 0, "sha256": hashlib.sha256(b"").hexdigest()})
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))
        reader = MemoryReader({str(i): b"" for i in range(9)})
        for entry in reader.manifest["files"]:
            entry["bytes"] = MAX_FILE
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))
        reader.manifest["files"] = []
        reader.manifest["nestedVaults"] = ["root"] * (MAX_ENTRIES + 1)
        with self.assertRaises(InvalidExport):
            parse_manifest(reader.read(MANIFEST))

    def test_bad_json_encoding_deep_json_and_surrogate_paths_fail_closed(self):
        for data in [b"\xff", b"not json", b"[" * 1500 + b"]" * 1500]:
            with self.subTest(data=data[:20]), self.assertRaises(InvalidExport):
                parse_manifest(data)
        with self.assertRaises(InvalidExport):
            relative_path("bad\ud800")


class WebDAVInventoryTests(unittest.TestCase):
    @staticmethod
    def response(entries):
        root = ET.Element("{DAV:}multistatus")
        for href, collection, status in entries:
            response = ET.SubElement(root, "{DAV:}response")
            ET.SubElement(response, "{DAV:}href").text = href
            propstat = ET.SubElement(response, "{DAV:}propstat")
            ET.SubElement(propstat, "{DAV:}status").text = status
            prop = ET.SubElement(propstat, "{DAV:}prop")
            resource = ET.SubElement(prop, "{DAV:}resourcetype")
            if collection:
                ET.SubElement(resource, "{DAV:}collection")
        return ET.tostring(root)

    def reader(self, bodies):
        reader = Reader("http://localhost:49183/vault/")
        reader.read = lambda path, method="GET": bodies[path]
        return reader

    def test_valid_unicode_percent_names_and_recursive_collections(self):
        reader = self.reader({
            "": self.response([("/vault/", True, "HTTP/1.1 200 OK"),
                                ("/vault/Photos/", True, "HTTP/1.1 200 OK"),
                                ("/vault/100%25.txt", False, "HTTP/1.1 200 OK")]),
            "Photos": self.response([("/vault/Photos/", True, "HTTP/1.1 200 OK"),
                                      ("/vault/Photos/caf%C3%A9.jpg", False, "HTTP/1.1 200 OK")])})
        self.assertEqual(reader.inventory(), ({"100%.txt", "Photos/café.jpg"}, {"Photos"}))

    def test_foreign_escaped_ambiguous_or_duplicate_paths_rejected(self):
        for href in ["http://evil.invalid/vault/a", "/other/a", "/vault/../outside",
                     "/vault/a/b", "/vault/a%2fb", "/vault/a%5cb", "/vault/%FF",
                     "/vault/%ZZ", "/vault/a?x=1", "/vault/a#fragment", "relative"]:
            with self.subTest(href=href), self.assertRaises(InvalidExport):
                self.reader({"": self.response([(href, False, "HTTP/1.1 200 OK")])}).inventory()
        duplicate = [("/vault/a", False, "HTTP/1.1 200 OK")] * 2
        with self.assertRaises(InvalidExport):
            self.reader({"": self.response(duplicate)}).inventory()

    def test_failed_or_ambiguous_property_status_is_not_a_file(self):
        for status in ["HTTP/1.1 404 Not Found", "HTTP/1.1 403 Forbidden", "", "200"]:
            with self.subTest(status=status), self.assertRaises(InvalidExport):
                self.reader({"": self.response([("/vault/a", False, status)])}).inventory()
        tree = ET.fromstring(self.response([("/vault/a", False, "HTTP/1.1 200 OK")]))
        response = tree.find("{DAV:}response")
        response.append(ET.fromstring(ET.tostring(response.find("{DAV:}propstat"))))
        with self.assertRaises(InvalidExport):
            self.reader({"": ET.tostring(tree)}).inventory()

    def test_cli_file_properties_without_resource_type_require_bounded_length(self):
        tree = ET.fromstring(self.response([("/vault/a", False, "HTTP/1.1 200 OK")]))
        prop = tree.find(".//{DAV:}prop")
        prop.remove(prop.find("{DAV:}resourcetype"))
        length = ET.SubElement(prop, "{DAV:}getcontentlength")
        length.text = "7"
        self.assertEqual(self.reader({"": ET.tostring(tree)}).inventory(), ({"a"}, set()))
        for value in [None, "-1", "invalid", "999999999999999", "4194305"]:
            length.text = value
            with self.subTest(value=value), self.assertRaises(InvalidExport):
                self.reader({"": ET.tostring(tree)}).inventory()

    def test_wrong_root_malformed_xml_and_dtd_rejected(self):
        for body in [b"<bad/>", b"<", b'<!DOCTYPE x [<!ENTITY e "x">]><x>&e;</x>',
                     b"<\x00x/>"]:
            with self.subTest(body=body), self.assertRaises(InvalidExport):
                self.reader({"": body}).inventory()

    def test_credentials_in_reader_url_rejected(self):
        for base in ["http://user@localhost:49183/vault", "http://user:secret@localhost/vault"]:
            with self.assertRaises(InvalidExport):
                Reader(base)


if __name__ == "__main__":
    unittest.main()
