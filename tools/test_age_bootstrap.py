import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import age_bootstrap as bootstrap
import backup_recovery


class AgeBootstrapTests(unittest.TestCase):
    def release(self, *, kind=tarfile.REGTYPE, duplicate=False):
        result = io.BytesIO()
        with tarfile.open(fileobj=result, mode="w:gz") as archive:
            item = tarfile.TarInfo("age/age"); item.type = kind
            if kind == tarfile.REGTYPE:
                item.size = 6
                archive.addfile(item, io.BytesIO(b"binary"))
                if duplicate:
                    archive.addfile(item, io.BytesIO(b"binary"))
            else:
                item.linkname = "/outside"
                archive.addfile(item)
        return result.getvalue()

    def test_installed_and_explicit_executables_do_not_download(self):
        for requested in (None, "/chosen/age"):
            with self.subTest(requested=requested), patch.object(bootstrap.shutil, "which", return_value="/chosen/age"), patch.object(bootstrap, "download") as download:
                with bootstrap.age_executable(requested) as binary:
                    self.assertEqual(binary, "/chosen/age")
                download.assert_not_called()
        with patch.object(bootstrap.shutil, "which", return_value=None), patch.object(bootstrap, "download") as download:
            with self.assertRaises(bootstrap.AgeSetupError), bootstrap.age_executable("/missing/age"):
                pass
            download.assert_not_called()

    def test_platform_selection_and_unsupported_platform(self):
        for system, architecture, suffix in (("Darwin", "arm64", "darwin-arm64.tar.gz"), ("Darwin", "x86_64", "darwin-amd64.tar.gz"), ("Linux", "aarch64", "linux-arm64.tar.gz"), ("Windows", "AMD64", "windows-amd64.zip")):
            with patch.object(bootstrap.platform, "system", return_value=system), patch.object(bootstrap.platform, "machine", return_value=architecture):
                name, digest = bootstrap.artifact_name()
                self.assertTrue(name.endswith(suffix)); self.assertEqual(len(digest), 64)
        with patch.object(bootstrap.platform, "system", return_value="unknown"), self.assertRaises(bootstrap.AgeSetupError):
            bootstrap.artifact_name()

    def test_automatic_setup_and_verified_cache_reuse_without_network(self):
        data = self.release(); digest = hashlib.sha256(data).hexdigest()
        def download(url, target, expected):
            self.assertTrue(url.startswith(bootstrap.RELEASE)); self.assertEqual(expected, digest)
            target.write_bytes(data)
        result = subprocess.CompletedProcess([], 0, stdout="v1.3.2\n")
        with tempfile.TemporaryDirectory() as root, patch.object(bootstrap.shutil, "which", return_value=None), patch.object(bootstrap, "artifact_name", return_value=("fixture.tar.gz", digest)), patch.object(bootstrap.subprocess, "run", return_value=result):
            for cached in (False, True):
                with self.subTest(cached=cached), patch.object(bootstrap, "download", side_effect=download) as fetch:
                    with bootstrap.age_executable(cache=root, allow_install=not cached) as binary:
                        path = Path(binary)
                        self.assertEqual(path.read_bytes(), b"binary")
                        if os.name != "nt": self.assertEqual(path.stat().st_mode & 0o777, 0o700)
                    self.assertFalse(path.exists())
                    self.assertEqual(fetch.call_count, 0 if cached else 1)
                self.assertEqual(sorted(p.name for p in Path(root).iterdir()), ["fixture.tar.gz"])

    def test_corrupt_cache_does_not_execute_in_no_install_mode(self):
        with tempfile.TemporaryDirectory() as root, patch.object(bootstrap.shutil, "which", return_value=None), patch.object(bootstrap, "artifact_name", return_value=("fixture.tar.gz", "0" * 64)), patch.object(bootstrap.subprocess, "run") as execute, patch.object(bootstrap, "download") as fetch:
            (Path(root) / "fixture.tar.gz").write_bytes(b"corrupt")
            with self.assertRaises(bootstrap.AgeSetupError), bootstrap.age_executable(cache=root, allow_install=False):
                pass
            execute.assert_not_called(); fetch.assert_not_called()
            self.assertEqual((Path(root) / "fixture.tar.gz").read_bytes(), b"corrupt")

    def test_download_checksum_size_and_https_guards(self):
        class Response(io.BytesIO):
            def geturl(self): return "https://release-assets.githubusercontent.com/official"
        for bad_hash, max_size, insecure in ((True, 100, False), (False, 2, False), (False, 100, True)):
            with self.subTest(bad_hash=bad_hash, max_size=max_size, insecure=insecure), tempfile.TemporaryDirectory() as root:
                response = Response(b"payload")
                if insecure: response.geturl = lambda: "http://example.invalid"
                digest = "0" * 64 if bad_hash else hashlib.sha256(b"payload").hexdigest()
                with patch.object(bootstrap.urllib.request, "urlopen", return_value=response), patch.object(bootstrap, "MAX_DOWNLOAD", max_size), self.assertRaises(bootstrap.AgeSetupError):
                    bootstrap.download(bootstrap.RELEASE + "fixture", Path(root) / "download", digest)

    def test_archive_rejects_links_duplicates_and_oversized_executables(self):
        for data, limit in ((self.release(kind=tarfile.SYMTYPE), 100), (self.release(kind=tarfile.LNKTYPE), 100), (self.release(duplicate=True), 100), (self.release(), 2)):
            with self.subTest(limit=limit), tempfile.TemporaryDirectory() as root:
                archive = Path(root) / "fixture.tar.gz"; archive.write_bytes(data)
                output = Path(root) / "age"
                with patch.object(bootstrap, "MAX_EXECUTABLE", limit), self.assertRaises(bootstrap.AgeSetupError):
                    bootstrap.unpack_executable(archive, output)
                self.assertFalse(output.exists())

    def test_windows_archive_copies_only_exact_binary(self):
        with tempfile.TemporaryDirectory() as root:
            archive = Path(root) / "fixture.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("../../outside", b"ignored")
                output.writestr("age/age.exe", b"windows fixture")
            binary = Path(root) / "age.exe"
            bootstrap.unpack_executable(archive, binary)
            self.assertEqual(binary.read_bytes(), b"windows fixture")
            self.assertEqual(sorted(p.name for p in Path(root).iterdir()), ["age.exe", "fixture.zip"])

    def test_unexpected_version_cannot_start_recovery_and_temp_files_are_cleaned(self):
        data = self.release(); digest = hashlib.sha256(data).hexdigest()
        with tempfile.TemporaryDirectory() as root, patch.object(bootstrap.shutil, "which", return_value=None), patch.object(bootstrap, "artifact_name", return_value=("fixture.tar.gz", digest)), patch.object(bootstrap.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="unexpected")):
            (Path(root) / "fixture.tar.gz").write_bytes(data)
            with self.assertRaises(bootstrap.AgeSetupError), bootstrap.age_executable(cache=root):
                self.fail("An unverified version was returned")
            self.assertEqual(sorted(p.name for p in Path(root).iterdir()), ["fixture.tar.gz"])

    def test_failed_download_preserves_cache_and_never_executes(self):
        with tempfile.TemporaryDirectory() as root, patch.object(bootstrap.shutil, "which", return_value=None), patch.object(bootstrap, "artifact_name", return_value=("fixture.tar.gz", "0" * 64)), patch.object(bootstrap.subprocess, "run") as execute:
            archive = Path(root) / "fixture.tar.gz"; archive.write_bytes(b"old corrupted cache")
            def broken(url, target, expected):
                target.write_bytes(b"partial")
                raise bootstrap.urllib.error.URLError("disconnected")
            with patch.object(bootstrap, "download", side_effect=broken), self.assertRaises(bootstrap.AgeSetupError), bootstrap.age_executable(cache=root):
                pass
            execute.assert_not_called()
            self.assertEqual(archive.read_bytes(), b"old corrupted cache")
            self.assertEqual(list(Path(root).iterdir()), [archive])

    def test_replaced_cache_is_reverified_before_execution(self):
        data = self.release(); digest = hashlib.sha256(data).hexdigest()
        with tempfile.TemporaryDirectory() as root, patch.object(bootstrap.shutil, "which", return_value=None), patch.object(bootstrap, "artifact_name", return_value=("fixture.tar.gz", digest)), patch.object(bootstrap.subprocess, "run") as execute:
            archive = Path(root) / "fixture.tar.gz"; archive.write_bytes(data)
            def changed(source, destination): destination.write_bytes(b"changed during copy")
            with patch.object(bootstrap.shutil, "copyfile", side_effect=changed), self.assertRaises(bootstrap.AgeSetupError), bootstrap.age_executable(cache=root):
                pass
            execute.assert_not_called()
            self.assertEqual(archive.read_bytes(), data)
            self.assertEqual(list(Path(root).iterdir()), [archive])

    def test_invalid_inputs_are_rejected_before_automatic_setup(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source.age"
            destination = Path(root) / "recovered"
            for source_exists, destination_exists in ((False, False), (True, True)):
                with self.subTest(source_exists=source_exists), patch.object(backup_recovery, "age_executable") as setup:
                    if source_exists: source.write_bytes(b"fixture")
                    if destination_exists: destination.mkdir()
                    with patch("sys.argv", ["backup_recovery.py", str(source), str(destination)]), self.assertRaises(SystemExit):
                        backup_recovery.main()
                    setup.assert_not_called()


if __name__ == "__main__":
    unittest.main()
