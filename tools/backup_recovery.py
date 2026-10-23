#!/usr/bin/env python3
"""Recover a WagLock tar.age export with the independent age CLI; no phone or Keychain.

Passphrases are entered into age's terminal prompt, never command arguments.
A new private output directory is published only after every required domain verifies.
"""
import argparse
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

from age_bootstrap import AgeSetupError, age_executable
from backup_layout import LayoutError, readable_layout

MAX_METADATA = 64 * 1024 * 1024
DEFAULT_MAX_BYTES = 1024 ** 4
DEFAULT_MAX_ENTRIES = 200000


class InvalidBackup(ValueError):
    pass


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidBackup("Duplicate metadata key")
        result[key] = value
    return result


def document(data):
    if len(data) > MAX_METADATA:
        raise InvalidBackup("Metadata exceeds recovery limit")
    try:
        return json.loads(data, object_pairs_hook=unique_object, parse_constant=lambda _: (_ for _ in ()).throw(InvalidBackup("Non-finite number")))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise InvalidBackup("Malformed metadata") from error


def identifier(value):
    if not isinstance(value, str) or len(value) != 36:
        raise InvalidBackup("Invalid record identifier")
    try:
        if str(uuid.UUID(value)).upper() != value:
            raise InvalidBackup("Noncanonical record identifier")
    except ValueError as error:
        raise InvalidBackup("Invalid record identifier") from error
    return value


def safe_path(value):
    if value in ("metadata.json", "manifest.json"):
        return value
    if not isinstance(value, str):
        raise InvalidBackup("Invalid archive path")
    parts = value.split("/")
    if len(parts) != 2 or parts[0] not in ("media", "thumbnails", "protected"):
        raise InvalidBackup("Unexpected archive path")
    name = parts[1]
    if parts[0] == "protected":
        if not name.endswith(".tar.age"):
            raise InvalidBackup("Invalid protected archive")
        name = name[:-8]
    identifier(name)
    return value


def publish(stage, destination):
    """Atomic no-replacement publication; fail closed if unavailable."""
    if os.name == "nt":
        os.rename(stage, destination)  # Windows rename rejects an existing destination.
        return
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        rename = libc.renamex_np
        rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        args = (os.fsencode(stage), os.fsencode(destination), 4)  # RENAME_EXCL
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        rename = libc.renameat2
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        args = (-100, os.fsencode(stage), -100, os.fsencode(destination), 1)  # RENAME_NOREPLACE
    else:
        raise InvalidBackup("Exclusive publication unavailable on this platform")
    rename.restype = ctypes.c_int
    if rename(*args) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(destination))


def exact(stream, count):
    data = stream.read(count)
    if len(data) != count:
        raise InvalidBackup("Truncated archive")
    return data


def octal(field):
    text = field.rstrip(b"\0 ")
    if not text or re.fullmatch(b"[0-7]+", text) is None:
        raise InvalidBackup("Invalid tar number")
    return int(text, 8)


def padding(stream, size):
    data = exact(stream, (-size) % 512)
    if any(data):
        raise InvalidBackup("Nonzero tar padding")


def pax_size(data):
    if len(data) > 4096 or not re.fullmatch(b"[0-9]{1,4} size=[0-9]{1,20}\n", data):
        raise InvalidBackup("Unsupported extended tar header")
    length, text = data.split(b" ", 1)
    if int(length) != len(data):
        raise InvalidBackup("Invalid extended tar record length")
    return int(text[5:-1])


def unpack_verified(archive, stage, *, expected_domain="root", expected_parent=None,
                    max_bytes=DEFAULT_MAX_BYTES, max_entries=DEFAULT_MAX_ENTRIES):
    actual = {}
    total = 0
    manifest = metadata = None
    extended = None
    with Path(archive).open("rb") as stream:
        while True:
            header = exact(stream, 512)
            if header == bytes(512):
                if extended is not None or exact(stream, 512) != bytes(512) or stream.read(1):
                    raise InvalidBackup("Invalid archive ending")
                break
            if manifest is not None:
                raise InvalidBackup("Manifest must be the last archive entry")
            checksum = octal(header[148:156])
            if sum(header[:148]) + 8 * 32 + sum(header[156:]) != checksum:
                raise InvalidBackup("Tar checksum mismatch")
            if header[257:263] != b"ustar\0" or header[263:265] != b"00" or any(header[345:500]):
                raise InvalidBackup("Unsupported tar layout")
            raw_name = header[:100]
            before, separator, after = raw_name.partition(b"\0")
            if not separator or any(after):
                raise InvalidBackup("Invalid archive name padding")
            try:
                name = before.decode("ascii")
            except UnicodeError as error:
                raise InvalidBackup("Unexpected archive name encoding") from error
            size = octal(header[124:136])
            kind = header[156:157]
            if kind == b"x":
                if extended is not None or name != "PaxHeaders/size" or size > 4096:
                    raise InvalidBackup("Unsupported extended tar header")
                extended = pax_size(exact(stream, size)); padding(stream, size)
                continue
            if kind != b"0" or any(header[157:257]):
                raise InvalidBackup("Links and special archive entries are forbidden")
            if extended is not None:
                if size != 0 or extended <= 0o77777777777:
                    raise InvalidBackup("Inconsistent extended file size")
                size, extended = extended, None
            safe_path(name)
            if name in actual or (not actual and name != "metadata.json"):
                raise InvalidBackup("Duplicate or out-of-order archive entry")
            if len(actual) >= max_entries or total + size > max_bytes:
                raise InvalidBackup("Recovery resource limit exceeded")
            if name in ("metadata.json", "manifest.json") and size > MAX_METADATA:
                raise InvalidBackup("Metadata exceeds recovery limit")
            if size > shutil.disk_usage(stage).free:
                raise InvalidBackup("Insufficient recovery disk space")
            path = stage / name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            digest = hashlib.sha256()
            with path.open("xb") as output:
                os.chmod(path, 0o600)
                remaining = size
                while remaining:
                    chunk = exact(stream, min(65536, remaining))
                    output.write(chunk); digest.update(chunk); remaining -= len(chunk)
            padding(stream, size)
            total += size
            if name == "manifest.json":
                manifest = document(path.read_bytes())
            else:
                actual[name] = {"bytes": size, "sha256": digest.hexdigest()}
                if name == "metadata.json":
                    metadata = document(path.read_bytes())
    if not isinstance(manifest, dict) or set(manifest) != {"schema", "files", "nested"} or manifest["schema"] != "waglock-backup-manifest-1":
        raise InvalidBackup("Missing or unsupported completeness manifest")
    entries, nested = manifest["files"], manifest["nested"]
    if not isinstance(entries, list) or not isinstance(nested, list) or len(entries) > max_entries or len(nested) > max_entries:
        raise InvalidBackup("Malformed completeness inventory")
    expected = {}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "bytes", "sha256"}:
            raise InvalidBackup("Malformed completeness entry")
        name = safe_path(entry["path"])
        if name == "manifest.json" or name in expected or type(entry["bytes"]) is not int or entry["bytes"] < 0 or not isinstance(entry["sha256"], str) or not re.fullmatch("[0-9a-f]{64}", entry["sha256"]):
            raise InvalidBackup("Malformed completeness entry")
        expected[name] = {"bytes": entry["bytes"], "sha256": entry["sha256"]}
    if actual != expected:
        raise InvalidBackup("Missing, extra or modified content")
    if any(not isinstance(path, str) or not path.startswith("protected/") for path in nested) or len(set(nested)) != len(nested) or set(nested) != {path for path in actual if path.startswith("protected/")}:
        raise InvalidBackup("Incomplete protected-album inventory")
    validate_metadata(metadata, actual, nested, expected_domain, expected_parent)
    return {"domain": expected_domain, "files": len(actual), "bytes": total, "nested": nested}


def text(value):
    if not isinstance(value, str):
        return False
    try:
        value.encode("utf-8")
        return True
    except UnicodeError:
        return False


def number(value, optional=False, positive=False):
    if value is None:
        return optional
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value) and (not positive or value >= 0)
    except OverflowError:
        return False


def validate_metadata(meta, actual, nested, domain, parent):
    keys = {"schema", "domain", "parent", "assets", "albums", "notes", "drafts", "children", "notIncluded", "trash"}
    if not isinstance(meta, dict) or set(meta) != keys or meta["schema"] != "waglock-backup-metadata-1" or meta["domain"] != domain or meta["parent"] != parent:
        raise InvalidBackup("Wrong or unsupported domain metadata")
    if meta["trash"] != "notImplemented" or meta["notIncluded"] != ["deviceSettings", "FaceIDRegistrations", "nativeKeychainCredentials"]:
        raise InvalidBackup("Unsupported backup coverage")
    for key in ["assets", "albums", "notes", "drafts", "children"]:
        if not isinstance(meta[key], list):
            raise InvalidBackup("Invalid record inventory")
    for child in meta["children"]:
        identifier(child)
    if len(set(meta["children"])) != len(meta["children"]) or {"protected/" + child + ".tar.age" for child in meta["children"]} != set(nested):
        raise InvalidBackup("Protected-album references do not match")
    album_ids = set()
    for album in meta["albums"]:
        if not isinstance(album, dict) or set(album) != {"id", "parentID", "name", "protection", "createdAt"} or album["protection"] not in ["inherited", "password", "passwordAndFaceID", "faceIDOnly"] or not text(album["name"]) or not number(album["createdAt"]):
            raise InvalidBackup("Malformed album metadata")
        value = identifier(album["id"])
        if value in album_ids:
            raise InvalidBackup("Duplicate album identifier")
        album_ids.add(value)
        if album["parentID"] is not None:
            identifier(album["parentID"])
    own = {album["id"]: album for album in meta["albums"]}
    if domain == "root":
        if any(album["protection"] != "inherited" for album in own.values()):
            raise InvalidBackup("Protected album metadata exposed in the root domain")
    elif domain not in own or own[domain]["protection"] == "inherited" or any(album["protection"] != "inherited" for key, album in own.items() if key != domain):
        raise InvalidBackup("Invalid protected domain root")
    for album in own.values():
        visited = set()
        current = album["id"]
        while current is not None:
            if current in visited:
                raise InvalidBackup("Cyclic album hierarchy")
            visited.add(current)
            if current not in own:
                if domain == "root":
                    raise InvalidBackup("Missing album parent")
                break
            current = own[current]["parentID"]
    if domain != "root" and (meta["notes"] or meta["drafts"]):
        raise InvalidBackup("Unexpected note domain")
    expected_paths = {"metadata.json"} | set(nested)
    asset_ids = set()
    fields = {"id", "albumID", "name", "fileExtension", "storedType", "effectiveType", "declaredBytes", "createdAt", "modifiedAt", "width", "height", "duration", "payload", "thumbnail"}
    for asset in meta["assets"]:
        if not isinstance(asset, dict) or set(asset) != fields:
            raise InvalidBackup("Malformed asset metadata")
        value = identifier(asset["id"])
        if asset["albumID"] is not None:
            identifier(asset["albumID"])
        if value in asset_ids or (asset["albumID"] is not None and asset["albumID"] not in album_ids) or (domain != "root" and asset["albumID"] is None):
            raise InvalidBackup("Duplicate or unbound asset")
        asset_ids.add(value)
        if asset["payload"] != "media/" + value or asset["thumbnail"] not in (None, "thumbnails/" + value):
            raise InvalidBackup("Invalid asset payload reference")
        if any(not text(asset[key]) for key in ["name", "fileExtension"]) or asset["storedType"] not in ["photo", "video", "audio", "document"] or asset["effectiveType"] not in ["photo", "video", "audio", "document"] or type(asset["declaredBytes"]) is not int or asset["declaredBytes"] < 0:
            raise InvalidBackup("Unsupported asset metadata")
        if not number(asset["createdAt"]) or not number(asset["modifiedAt"], optional=True) or not number(asset["duration"], optional=True, positive=True) or any(value is not None and (type(value) is not int or value <= 0) for value in [asset["width"], asset["height"]]):
            raise InvalidBackup("Invalid asset dates or dimensions")
        expected_paths.add(asset["payload"])
        if asset["thumbnail"] is not None:
            expected_paths.add(asset["thumbnail"])
    if expected_paths != set(actual):
        raise InvalidBackup("Unreferenced or missing payload")
    note_ids = set()
    for note in meta["notes"]:
        if not isinstance(note, dict) or set(note) != {"id", "title", "content", "createdAt", "modifiedAt", "isFavorite", "tags"} or any(not text(note[k]) for k in ["title", "content"]) or type(note["isFavorite"]) is not bool or not isinstance(note["tags"], list) or any(not text(tag) for tag in note["tags"]):
            raise InvalidBackup("Malformed note metadata")
        if not number(note["createdAt"]) or not number(note["modifiedAt"]):
            raise InvalidBackup("Invalid note dates")
        value = identifier(note["id"])
        if value in note_ids:
            raise InvalidBackup("Duplicate note identifier")
        note_ids.add(value)
    origins = set()
    for draft in meta["drafts"]:
        if not isinstance(draft, dict) or set(draft) != {"origin", "title", "content", "updatedAt"} or draft["origin"] not in ["keychain", "legacyPreferences", "encryptedVault"] or draft["origin"] in origins or any(not text(draft[k]) for k in ["title", "content"]):
            raise InvalidBackup("Malformed saved draft")
        if not number(draft["updatedAt"]):
            raise InvalidBackup("Invalid draft date")
        origins.add(draft["origin"])


def recover(encrypted, destination, age, *, identity=None, outer_only=False, max_bytes=DEFAULT_MAX_BYTES, max_entries=DEFAULT_MAX_ENTRIES, raw_layout=False):
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise InvalidBackup("Choose a new recovery directory")
    stage = destination.with_name(destination.name + ".partial")
    stage.mkdir(mode=0o700)
    reports = []
    verified_domains = []
    remaining = {"bytes": max_bytes, "entries": max_entries, "metadata": MAX_METADATA}
    album_graph, assets, domain_parents = {}, set(), {}
    try:
        def domain(source, target, label, parent, depth):
            if depth > 64:
                raise InvalidBackup("Protected-album nesting exceeds recovery limit")
            # age does not decompress: decrypted tar cannot exceed ciphertext size.
            # Bound the decrypt-to-disk step itself, before the tar parser can enforce
            # payload/entry limits. Account conservatively for USTAR/PAX/age framing.
            ciphertext_bytes = source.stat().st_size
            tar_budget = remaining["bytes"] + remaining["entries"] * 2048 + 2048
            ciphertext_budget = tar_budget + tar_budget // 4096 + 16384
            if ciphertext_bytes > ciphertext_budget:
                raise InvalidBackup("Encrypted archive exceeds recovery resource budget")
            if ciphertext_bytes > shutil.disk_usage(stage).free:
                raise InvalidBackup("Insufficient space for temporary decryption")
            candidate = stage / (".decrypt-" + uuid.uuid4().hex + ".tar")
            command = [str(age), "--decrypt", "--output", str(candidate)]
            if depth == 0 and identity is not None:
                command += ["--identity", str(identity)]
            command += [str(source)]
            # age owns interactive passphrase entry; no secret goes through argv/environment.
            if depth == 0:
                if identity is None:
                    print("Opening the outer backup. At the age prompt, enter the password chosen when this backup was exported.", file=sys.stderr)
                else:
                    print("Opening the outer backup with your supplied private identity.", file=sys.stderr)
            if subprocess.run(command).returncode != 0:
                if depth > 0:
                    message = "Unable to decrypt protected album " + label + ". It needs its own album/export password; the outer backup password cannot replace it."
                elif identity is not None:
                    message = "Unable to decrypt the outer backup with this private identity. Check that the identity matches the recipient used for this backup."
                else:
                    message = "Unable to decrypt the outer backup with the entered export password. Check that this is the intended backup file. If the correct backup password still fails, keep this file and report the failure; do not send the password."
                raise InvalidBackup(message + " The age error above may also indicate damaged encrypted content.")
            target.mkdir(mode=0o700)
            result = unpack_verified(candidate, target, expected_domain=label, expected_parent=parent, max_bytes=remaining["bytes"], max_entries=remaining["entries"])
            candidate.unlink()
            meta_path = target / "metadata.json"
            remaining["metadata"] -= meta_path.stat().st_size
            if remaining["metadata"] < 0:
                raise InvalidBackup("Aggregate metadata exceeds recovery limit")
            meta = document(meta_path.read_bytes())
            verified_domains.append((target, meta))
            domain_parents[label] = meta["parent"]
            for album in meta["albums"]:
                if album["id"] in album_graph:
                    raise InvalidBackup("Album identifier reused across domains")
                album_graph[album["id"]] = (album["parentID"], album["protection"], label)
            for asset in meta["assets"]:
                if asset["id"] in assets:
                    raise InvalidBackup("Asset identifier reused across domains")
                assets.add(asset["id"])
            remaining["bytes"] -= result["bytes"]
            remaining["entries"] -= result["files"] + 1
            reports.append(result)
            if not outer_only:
                for nested in result["nested"]:
                    child = nested.split("/")[1][:-8]
                    print("Opening protected album backup " + child, file=sys.stderr)
                    domain(target / nested, target / ("recovered-" + child), child, label, depth + 1)
        domain(Path(encrypted).absolute(), stage / "root", "root", None, 0)
        if not outer_only:
            def owning_domain(album_id):
                seen, nearest = set(), None
                while album_id is not None:
                    if album_id in seen or album_id not in album_graph:
                        raise InvalidBackup("Missing or cyclic cross-domain parent")
                    seen.add(album_id)
                    parent_id, policy, _ = album_graph[album_id]
                    if policy != "inherited" and nearest is None:
                        nearest = album_id
                    album_id = parent_id
                return nearest or "root"
            for album_id, (parent_id, policy, owner) in album_graph.items():
                if owning_domain(album_id) != owner:
                    raise InvalidBackup("Album assigned to the wrong password domain")
                if policy != "inherited" and domain_parents[owner] != owning_domain(parent_id):
                    raise InvalidBackup("Protected domain parent mismatch")
        files = [] if raw_layout else readable_layout(stage, verified_domains, publish)
        report = {"schema": "waglock-recovery-report-2", "allProtectedDomainsRecovered": not outer_only,
            "domains": reports, "layout": "raw" if raw_layout else "readable", "files": files}
        (stage / "recovery-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        publish(stage, destination)
        return report
    except BaseException:
        shutil.rmtree(stage)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Mac example (repository in ~/repos/WagLock; backup on Desktop):
  python3 "$HOME/repos/WagLock/tools/backup_recovery.py" \\
    "$HOME/Desktop/WagLock-Backup.tar.age" \\
    "$HOME/Downloads/WagLock-Recovered"

The destination must be a new folder: do not create it first.
age downloads automatically if missing. Enter your backup password at the
prompt; typed passwords are hidden. Protected albums need their own passwords.
Recovered files appear under Library with names/extensions and album folders.
Recovery-key exports also need: --identity /path/to/private-identity.txt
""")
    parser.add_argument("encrypted", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--age", help="Use this age executable instead of automatic discovery/setup")
    parser.add_argument("--no-install-age", action="store_true", help="Do not download age; use an installed or verified cached copy")
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--raw-layout", action="store_true", help="Keep internal UUID filenames instead of creating a readable Library")
    parser.add_argument("--json", action="store_true", help="Print the full machine-readable recovery report")
    parser.add_argument("--outer-only", action="store_true", help="Explicitly retain child ciphertext without decrypting it")
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    parser.add_argument("--max-entries", type=int, default=DEFAULT_MAX_ENTRIES)
    args = parser.parse_args()
    if args.max_bytes <= 0 or args.max_entries <= 0:
        parser.error("Recovery limits must be positive")
    try:
        if not args.encrypted.is_file():
            raise InvalidBackup("Backup file not found. Check the encrypted file path.")
        destination = args.destination.absolute()
        if destination.exists() or destination.is_symlink() or destination.with_name(destination.name + ".partial").exists() or destination.with_name(destination.name + ".partial").is_symlink():
            raise InvalidBackup("Choose a new recovery directory; the destination or its .partial staging folder already exists.")
        with age_executable(args.age, allow_install=not args.no_install_age) as age:
            report = recover(args.encrypted, destination, age, identity=args.identity,
                outer_only=args.outer_only, max_bytes=args.max_bytes, max_entries=args.max_entries, raw_layout=args.raw_layout)
    except (InvalidBackup, AgeSetupError, LayoutError, OSError) as error:
        print("Recovery stopped without publishing a destination: " + str(error), file=sys.stderr)
        raise SystemExit(1)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("Recovery complete." if report["allProtectedDomainsRecovered"] else "Outer backup recovered. Protected child archives remain encrypted.")
        print("Open your files here:\n  " + str(destination / ("root" if args.raw_layout else "Library")))
        print("Verification details:\n  " + str(destination / "recovery-report.json"))


if __name__ == "__main__":
    main()
