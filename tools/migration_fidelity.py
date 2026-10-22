#!/usr/bin/env python3
"""Local, read-only byte/name/path comparison for disposable export experiments."""
import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import zlib


IGNORED = {".DS_Store", "Thumbs.db"}


def inventory(directory):
    root = Path(directory).resolve(strict=True)
    if not root.is_dir():
        raise ValueError("The input must be a directory")
    files = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("Symlinks are not supported in fidelity inventories")
        if not path.is_file() or path.name in IGNORED:
            continue
        before = path.stat()
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError("An input changed during hashing; repeat the inventory")
        files.append({"path": path.relative_to(root).as_posix(), "size": after.st_size,
                      "sha256": digest.hexdigest()})
    return {"version": 1, "files": files, "ignored_names": sorted(IGNORED)}


def compare(expected, actual):
    """Match contents as a multiset, preserving duplicate multiplicity across renames."""
    for manifest in (expected, actual):
        if manifest.get("version") != 1 or not isinstance(manifest.get("files"), list):
            raise ValueError("Unsupported inventory format")
        paths = [row["path"] for row in manifest["files"]]
        if len(paths) != len(set(paths)):
            raise ValueError("An inventory contains duplicate paths")
    remaining = defaultdict(list)
    for row in actual["files"]:
        remaining[(row["size"], row["sha256"])].append(row)
    pending = list(expected["files"])
    matches = []
    # Prefer exact paths, then names, then renamed bytes. This avoids consuming
    # an exact duplicate's match for an unrelated renamed duplicate first.
    for mode in ("path", "name", "bytes"):
        unmatched = []
        for source in pending:
            candidates = remaining[(source["size"], source["sha256"])]
            eligible = [row for row in candidates if mode == "bytes"
                        or (row["path"] == source["path"] if mode == "path"
                            else Path(row["path"]).name == Path(source["path"]).name)]
            if not eligible:
                unmatched.append(source)
                continue
            found = eligible[0]
            candidates.remove(found)
            matches.append({"source": source["path"], "exported": found["path"],
                            "name_preserved": Path(source["path"]).name == Path(found["path"]).name,
                            "album_path_preserved": source["path"] == found["path"]})
        pending = unmatched
    by_path = {row["path"]: row for row in actual["files"]}
    changed = [row["path"] for row in pending if row["path"] in by_path
               and (row["size"], row["sha256"]) != (by_path[row["path"]]["size"], by_path[row["path"]]["sha256"])]
    return {"version": 1, "expected_count": len(expected["files"]),
            "exported_count": len(actual["files"]), "byte_identical_count": len(matches),
            "all_expected_bytes_present": not pending, "matches": matches,
            "missing_originals": pending, "changed_at_same_path": changed,
            "extra_exports": [row for rows in remaining.values() for row in rows],
            "metadata_note": "Equal hashes establish embedded-byte preservation. EXIF, video playback, capture dates and Live Photo pairing are not separately decoded or validated."}


def write_report(report, destination, input_root=None):
    destination = Path(destination).resolve()
    if input_root is not None:
        try:
            destination.relative_to(Path(input_root).resolve())
        except ValueError:
            pass
        else:
            raise ValueError("Write reports outside the input tree")
    # Reports contain plaintext names/hashes. Keep local and private by default.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=destination.parent,
                                         delete=False) as stream:
            temporary = stream.name
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        # Publish a complete report without ever overwriting an existing file.
        os.link(temporary, destination)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def png(width, height):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    scanlines = b"".join(b"\0" + bytes([35, 120, 210] if y < height // 2 else [240, 180, 30]) * width
                         for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"tEXt", b"Comment\0Vaultito generated non-private export fixture")
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def fixtures(destination):
    root = Path(destination)
    root.mkdir(parents=True, exist_ok=False)
    landscape = png(320, 180)
    samples = {"Album A/shared.png": landscape, "Album B/shared.png": png(180, 320),
               "Album A/Nested/café.png": png(240, 240), "Album B/duplicate.png": landscape}
    for name, data in samples.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return inventory(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("fixtures", "scan"):
        sub = commands.add_parser(name)
        sub.add_argument("directory")
        sub.add_argument("report")
    sub = commands.add_parser("compare")
    sub.add_argument("baseline")
    sub.add_argument("exported_directory")
    sub.add_argument("report")
    args = parser.parse_args()
    try:
        if args.command == "compare":
            baseline = json.loads(Path(args.baseline).read_text(encoding="utf-8"))
            report = compare(baseline, inventory(args.exported_directory))
            input_root = args.exported_directory
        else:
            report = fixtures(args.directory) if args.command == "fixtures" else inventory(args.directory)
            input_root = args.directory
        write_report(report, args.report, input_root)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f"Fidelity check failed: {error}\n")
    print("Wrote local report to " + args.report)


if __name__ == "__main__":
    main()
