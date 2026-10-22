#!/usr/bin/env python3
"""Disposable experiment only. Official CLI recovery + complete-manifest verification.

No iOS containers, Keychain, FUSE installation or production libraries are used.
Passwords are the public fixture strings, never taken from real users.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

MANIFEST = "waglock-manifest.json"
MAX_FILE = 4 * 1024 * 1024
MAX_TOTAL = 32 * 1024 * 1024
MAX_ENTRIES = 1000
OUTER_PASSWORD = "WagLock outer disposable fixture"
INNER_PASSWORD = "WagLock inner disposable fixture"


class InvalidExport(ValueError):
    pass


def relative_path(value):
    if not isinstance(value, str) or not value or len(value.encode()) > 4096:
        raise InvalidExport("Invalid relative path")
    parts = value.split("/")
    if len(parts) > 16 or any(not p or p in (".", "..") or "\\" in p or ":" in p
                              or any(ord(c) < 32 or ord(c) == 127 for c in p) for p in parts):
        raise InvalidExport("Unsafe relative path")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidExport("Duplicate JSON key")
        result[key] = value
    return result


def parse_manifest(data):
    if len(data) > MAX_FILE:
        raise InvalidExport("Manifest too large")
    value = json.loads(data, object_pairs_hook=unique_object)
    if not isinstance(value, dict) or value.get("schema") != "waglock-portable-export-experiment-1" or value.get("fixtureOnly") is not True:
        raise InvalidExport("Unsupported experimental manifest")
    files, directories, nested = value.get("files"), value.get("directories"), value.get("nestedVaults")
    if not isinstance(files, list) or not isinstance(directories, list) or not isinstance(nested, list) or len(files) + len(directories) > MAX_ENTRIES:
        raise InvalidExport("Invalid manifest inventory")
    expected = {}
    total = 0
    for item in files:
        if not isinstance(item, dict):
            raise InvalidExport("Invalid file entry")
        path = relative_path(item.get("path"))
        size, digest = item.get("bytes"), item.get("sha256")
        if path == MANIFEST or path in expected or type(size) is not int or not 0 <= size <= MAX_FILE or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise InvalidExport("Invalid file entry")
        expected[path] = (size, digest)
        total += size
    dirs = [relative_path(p) for p in directories]
    if total > MAX_TOTAL or len(set(dirs)) != len(dirs) or set(dirs) & set(expected):
        raise InvalidExport("Invalid directory inventory")
    for path in nested:
        if relative_path(path) not in dirs:
            raise InvalidExport("Nested vault not in directory inventory")
    if len(set(nested)) != len(nested):
        raise InvalidExport("Duplicate nested vault")
    return expected, set(dirs), nested


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise InvalidExport("Unexpected HTTP redirect")


class Reader:
    def __init__(self, base):
        parsed = urllib.parse.urlsplit(base)
        if parsed.scheme != "http" or parsed.hostname not in ("localhost", "127.0.0.1", "::1") or parsed.query or parsed.fragment:
            raise InvalidExport("Reader must use the CLI's loopback URL")
        self.base = base.rstrip("/") + "/"
        self.root = urllib.parse.unquote(urllib.parse.urlsplit(self.base).path)
        self.http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def read(self, path, method="GET"):
        url = self.base + urllib.parse.quote(relative_path(path), safe="/") if path else self.base
        request = urllib.request.Request(url, method=method, headers={"Depth": "1"} if method == "PROPFIND" else {})
        with self.http.open(request, timeout=10) as response:
            data = response.read(MAX_FILE + 1)
        if len(data) > MAX_FILE:
            raise InvalidExport("Response exceeds fixture bound")
        return data

    def inventory(self):
        files, dirs, todo = set(), set(), [""]
        while todo:
            current = todo.pop()
            root = ET.fromstring(self.read(current, "PROPFIND"))
            for entry in root.findall("{DAV:}response"):
                href = entry.findtext("{DAV:}href")
                if not href:
                    raise InvalidExport("Missing WebDAV path")
                href = urllib.parse.urlsplit(href).path
                decoded = urllib.parse.unquote(href)
                if not decoded.startswith(self.root):
                    raise InvalidExport("WebDAV path outside vault")
                path = decoded[len(self.root):].rstrip("/")
                if not path or path == current.rstrip("/"):
                    continue
                path = relative_path(path)
                parent = str(PurePosixPath(path).parent)
                if ("" if parent == "." else parent) != current.rstrip("/"):
                    raise InvalidExport("WebDAV response escaped requested directory")
                collection = entry.find(".//{DAV:}resourcetype/{DAV:}collection") is not None
                if collection:
                    if path not in dirs:
                        dirs.add(path)
                        todo.append(path)
                else:
                    files.add(path)
                if len(files) + len(dirs) > MAX_ENTRIES:
                    raise InvalidExport("Inventory exceeds fixture bound")
        return files, dirs

    def recover(self, destination):
        expected, directories, nested = parse_manifest(self.read(MANIFEST))
        actual_files, actual_dirs = self.inventory()
        if actual_files != set(expected) | {MANIFEST} or actual_dirs != directories:
            raise InvalidExport("Incomplete or unexpected inventory")
        destination = Path(destination)
        if destination.exists() or destination.is_symlink():
            raise InvalidExport("Destination already exists")
        stage = destination.with_name(destination.name + ".partial")
        stage.mkdir(mode=0o700)
        try:
            for path in sorted(directories, key=lambda p: (p.count("/"), p)):
                (stage / path).mkdir(mode=0o700)
            for path, (size, digest) in expected.items():
                data = self.read(path)
                if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
                    raise InvalidExport("File length or hash mismatch")
                with (stage / path).open("xb") as stream:
                    os.chmod(stage / path, 0o600)
                    stream.write(data)
            # Source is read-only to this client; recheck the authenticated manifest before publication.
            if parse_manifest(self.read(MANIFEST)) != (expected, directories, nested):
                raise InvalidExport("Manifest changed during recovery")
            stage.rename(destination)
        except BaseException:
            shutil.rmtree(stage)
            raise
        return {"files": len(expected), "directories": len(directories), "nestedVaults": nested}


@contextlib.contextmanager
def unlock(cli, vault, password, log_path):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with Path(log_path).open("x") as log:
        process = subprocess.Popen([str(cli), "unlock", "--password:stdin",
            "--mounter=org.cryptomator.frontend.webdav.mount.FallbackMounter",
            "--loopbackHostName=localhost", f"--loopbackPort={port}", str(vault)],
            stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True)
        try:
            process.stdin.write(password + "\n")
            process.stdin.close()
            deadline = time.monotonic() + 15
            while True:
                output = Path(log_path).read_text()
                urls = re.findall(rf"http://localhost:{port}/[a-zA-Z0-9-]+", output)
                if urls and "Unlocked and mounted vault successfully" in output:
                    break
                if process.poll() is not None:
                    raise InvalidExport("CLI rejected fixture credentials or vault")
                if time.monotonic() >= deadline:
                    raise InvalidExport("CLI startup timed out")
                time.sleep(0.05)
            yield Reader(urls[-1])
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def experiment(cli, fixture, output):
    info = json.loads((fixture / "experiment.json").read_text(), object_pairs_hook=unique_object)
    if info.get("fixtureOnly") is not True or info.get("outerPassword") != OUTER_PASSWORD or info.get("innerPassword") != INNER_PASSWORD:
        raise InvalidExport("Only public generated experiment fixtures are supported")
    if output.exists() or output.is_symlink():
        raise InvalidExport("Output must be a new directory")
    output.mkdir(mode=0o700)
    report = {"fixtureOnly": True, "cliVersion": subprocess.check_output([str(cli), "--version"], text=True).strip(), "wholeVaultAppExportShipped": False}
    vault = fixture / "candidate-vault"
    with unlock(cli, vault, OUTER_PASSWORD, output / "outer.log") as reader:
        report["outerRecovery"] = reader.recover(output / "recovered")
    inner = output / "recovered/Protected"
    try:
        with unlock(cli, inner, OUTER_PASSWORD, output / "wrong-inner.log"):
            raise AssertionError("Outer password unlocked inner vault")
    except InvalidExport as error:
        if str(error) != "CLI rejected fixture credentials or vault":
            raise
        report["outerPasswordCannotUnlockInner"] = True
    with unlock(cli, inner, INNER_PASSWORD, output / "inner.log") as reader:
        report["innerRecovery"] = reader.recover(output / "inner-recovered")
    outer_bytes = (output / "recovered/Trips/2026/sample.bin").read_bytes()
    inner_bytes = (output / "inner-recovered/Photos/secret.bin").read_bytes()
    if hashlib.sha256(outer_bytes).hexdigest() != info["expectedOuterSHA256"] or hashlib.sha256(inner_bytes).hexdigest() != info["expectedInnerSHA256"]:
        raise InvalidExport("Cross-implementation fixture mismatch")
    report["independentCLIContentHashesMatch"] = True
    for name in ["truncated", "tampered", "missing-manifest"]:
        damaged = output / name
        shutil.copytree(vault, damaged)
        target = damaged / relative_path(info["manifestCiphertext"] if name == "missing-manifest" else info["truncationTarget"])
        if name == "missing-manifest":
            target.unlink()
        else:
            data = bytearray(target.read_bytes())
            if name == "truncated":
                del data[-(37 + 12 + 16):]  # Valid final-chunk removal, accepted by native format reader.
            else:
                data[-1] ^= 1
            target.write_bytes(data)
        recovered = output / (name + "-recovered")
        try:
            with unlock(cli, damaged, OUTER_PASSWORD, output / (name + ".log")) as reader:
                if name == "truncated":
                    prefix = reader.read("Trips/2026/sample.bin")
                    if len(prefix) != 65536:
                        raise InvalidExport("Unexpected native truncation behavior")
                    report["nativeReaderAcceptsTruncatedPrefix"] = True
                reader.recover(recovered)
            raise AssertionError("Damaged export accepted")
        except (InvalidExport, urllib.error.HTTPError):
            if recovered.exists() or recovered.with_name(recovered.name + ".partial").exists():
                raise AssertionError("Rejected recovery published partial data")
            report[name + "RejectedByVerifiedRecovery"] = True
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", required=True, type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(experiment(args.cli.resolve(strict=True), args.fixture.resolve(strict=True), args.output.absolute()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
