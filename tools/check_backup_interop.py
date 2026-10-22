#!/usr/bin/env python3
"""Check the public synthetic iOS backup with the unmodified age CLI on POSIX.

All passphrases here are PUBLIC fixture data, never user credentials. No real vault
or phone is accessed. The CLI receives them via an isolated terminal, not argv/env.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import sys
import tempfile
import termios
import time

FIXTURE = Path(__file__).parent / "fixtures" / "age-backup"


def terminal(command, password_for, timeout=120):
    master, slave = pty.openpty()
    def setup():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, preexec_fn=setup)
    os.close(slave)
    deadline, pending, transcript = time.monotonic() + timeout, b"", b""
    domain = "root"
    try:
        while process.poll() is None:
            if time.monotonic() > deadline:
                process.kill()
                raise RuntimeError("Public fixture recovery timed out")
            if select.select([master], [], [], 0.1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                pending += data
                transcript += data
                domains = re.findall(rb"Opening protected album backup ([0-9A-F-]{36})", pending)
                if domains:
                    domain = domains[-1].decode("ascii")
                if b"Enter passphrase:" in pending:
                    os.write(master, (password_for(domain) + "\n").encode("utf-8"))
                    pending = b""
        return process.wait(timeout=10), transcript
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)


def check(age):
    expected = json.loads((FIXTURE / "expected.public.json").read_text())
    if expected.get("fixtureOnly") is not True:
        raise RuntimeError("Only the checked-in public fixture is supported")
    source = FIXTURE / "public-fixture.tar.age"
    provenance = json.loads((FIXTURE / "provenance.json").read_text())
    if hashlib.sha256(source.read_bytes()).hexdigest() != provenance["sha256"]:
        raise RuntimeError("Public fixture hash changed")
    def credential(domain):
        return expected["rootPassword"] if domain == "root" else expected["childPasswords"][domain]
    with tempfile.TemporaryDirectory(prefix="waglock-public-age-check-") as temporary:
        output = Path(temporary) / "recovered"
        code, transcript = terminal([sys.executable, str(Path(__file__).with_name("backup_recovery.py")),
            str(source), str(output), "--age", age], credential)
        if code != 0:
            raise RuntimeError("Public fixture recovery failed: " + transcript.decode(errors="replace"))
        actual = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in output.rglob("media/*") if p.is_file()}
        if actual != expected["expectedPayloadHashes"]:
            raise RuntimeError("Recovered payload hashes differ")
        metadata = [json.loads(p.read_text()) for p in output.rglob("metadata.json")]
        if ([n["content"] for m in metadata for n in m["notes"]] != expected["expectedNotes"]
            or [d["content"] for m in metadata for d in m["drafts"]] != expected["expectedDrafts"]
            or sorted(a["name"] for m in metadata for a in m["albums"]) != sorted(expected["expectedAlbums"])
            or [n["tags"] for m in metadata for n in m["notes"]] != [["cafe\u0301"]]):
            raise RuntimeError("Recovered metadata differs")
        rejected = 0
        for path in output.rglob("metadata.json"):
            info = json.loads(path.read_text())
            for child in info["children"]:
                archive = path.parent / "protected" / (child + ".tar.age")
                code, transcript = terminal([age, "--decrypt", str(archive)], lambda _: credential(info["domain"]))
                if code == 0 or b"incorrect passphrase" not in transcript:
                    raise RuntimeError("Parent credential was not rejected by official age")
                rejected += 1
        if rejected != 2:
            raise RuntimeError("Expected both nested password boundaries")
        # Mutate ciphertext and remove a whole final payload chunk. Official age must
        # reject both; the helper must also leave no published recovery directory.
        rejected_mutations = 0
        data = source.read_bytes()
        for name, changed in (("tamper", data[:-1] + bytes([data[-1] ^ 1])), ("truncated", data[:-65552])):
            damaged = Path(temporary) / (name + ".age")
            damaged.write_bytes(changed)
            destination = Path(temporary) / name
            code, _ = terminal([sys.executable, str(Path(__file__).with_name("backup_recovery.py")),
                str(damaged), str(destination), "--age", age], credential)
            if code == 0 or destination.exists() or destination.with_name(destination.name + ".partial").exists():
                raise RuntimeError("Damaged fixture was published or not cleaned up")
            rejected_mutations += 1
        return {"fixtureOnly": True, "officialAgeCLI": subprocess.check_output([age, "--version"], text=True).strip(),
            "independentColdRecovery": True, "payloadCount": len(actual), "payloadHashesMatch": True,
            "metadataNotesDraftsUnicodeMatch": True, "parentOnlyCredentialsRejected": rejected,
            "tamperAndTruncationRejected": rejected_mutations, "phoneKeychainRequired": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--age", default="age", help="Path to unmodified official age executable")
    args = parser.parse_args()
    print(json.dumps(check(args.age), indent=2))
