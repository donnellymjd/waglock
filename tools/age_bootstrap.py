"""Find age or use a checksum-pinned official release in a private user cache.

Only public executable downloads leave this process. No backup, password or
identity is sent to the download service. No package manager or shell is run.
"""
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile

VERSION = "1.3.2"
RELEASE = "https://github.com/FiloSottile/age/releases/download/v" + VERSION + "/"
# Official GitHub release asset SHA-256 digests, retrieved 2026-10-22.
# Keep pinned: do not silently trust a checksum downloaded beside an executable.
DIGESTS = {
    "darwin-amd64.tar.gz": "1d1e4bc66e1427edad7739ae7616157de0e79db8b6d2a1497d7d9925fb06a539",
    "darwin-arm64.tar.gz": "e2020b073c44f692685a24d6abc378817eb81ffaaf49fd0531ef8565f767f2f5",
    "linux-amd64.tar.gz": "cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10",
    "linux-arm64.tar.gz": "6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4",
    "windows-amd64.zip": "f48d8f8f9ebe903ab5027ed067652f2cc1db94bc206976430133b905dcd8e8c7",
    "windows-arm64.zip": "fae351336c8d5f30f93cc3ccdec16d1ed7851d68cdd6656d41955cc31a447c9d",
}
MAX_DOWNLOAD = 32 * 1024 * 1024
MAX_EXECUTABLE = 64 * 1024 * 1024
INSTALL_HELP = "Install age from https://github.com/FiloSottile/age#installation, or pass --age /path/to/age."


class AgeSetupError(ValueError):
    pass


def artifact_name():
    system = platform.system().lower()
    machine = platform.machine().lower()
    architecture = {"x86_64": "amd64", "amd64": "amd64", "arm64": "arm64", "aarch64": "arm64"}.get(machine)
    suffix = ".zip" if system == "windows" else ".tar.gz"
    key = system + "-" + str(architecture) + suffix
    if key not in DIGESTS:
        raise AgeSetupError("Automatic age setup is unavailable for this computer. " + INSTALL_HELP)
    return "age-v" + VERSION + "-" + key, DIGESTS[key]


def cache_root():
    if sys.platform == "darwin":
        parent = Path.home() / "Library" / "Caches"
    elif os.name == "nt":
        parent = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    else:
        parent = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return parent / "WagLock" / "age" / VERSION


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            chunk = source.read(65536)
            if not chunk:
                return digest.hexdigest()
            digest.update(chunk)


def download(url, target, expected):
    digest, total = hashlib.sha256(), 0
    request = urllib.request.Request(url, headers={"User-Agent": "WagLock-Recovery/1"})
    with urllib.request.urlopen(request, timeout=30) as response, target.open("xb") as output:
        if not response.geturl().startswith("https://"):
            raise AgeSetupError("age download did not use HTTPS.")
        while True:
            chunk = response.read(65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_DOWNLOAD:
                raise AgeSetupError("age download exceeds the allowed size.")
            output.write(chunk)
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise AgeSetupError("age download checksum did not match the pinned official release. Nothing was executed.")


def unpack_executable(archive, executable):
    name = "age/age.exe" if archive.name.endswith(".zip") else "age/age"
    # Never extract paths from an archive. Copy only the exact expected regular
    # binary to a file we own; links/duplicate entries/oversized output are refused.
    if archive.name.endswith(".zip"):
        container = zipfile.ZipFile(archive)
        matches = [item for item in container.infolist() if item.filename == name]
        if len(matches) != 1 or matches[0].is_dir() or stat.S_ISLNK(matches[0].external_attr >> 16):
            container.close()
            raise AgeSetupError("Official age archive has an unexpected executable entry.")
        size = matches[0].file_size
        source = lambda: container.open(matches[0])
    else:
        container = tarfile.open(archive, "r:gz")
        matches = [item for item in container.getmembers() if item.name == name]
        if len(matches) != 1 or not matches[0].isfile():
            container.close()
            raise AgeSetupError("Official age archive has an unexpected executable entry.")
        size = matches[0].size
        source = lambda: container.extractfile(matches[0])
    try:
        if not 0 < size <= MAX_EXECUTABLE:
            raise AgeSetupError("Official age executable has an unexpected size.")
        with source() as incoming, executable.open("xb") as output:
            total = 0
            while True:
                chunk = incoming.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > size:
                    raise AgeSetupError("Official age executable exceeds its declared size.")
                output.write(chunk)
        if total != size:
            raise AgeSetupError("Official age executable is incomplete.")
        executable.chmod(0o700)
    finally:
        container.close()


@contextmanager
def age_executable(requested=None, *, allow_install=True, cache=None):
    """Explicit --age never falls back. A verified cached release also works offline."""
    explicit = requested is not None
    installed = shutil.which(str(requested) if explicit else "age")
    if installed:
        yield str(Path(installed).absolute())
        return
    if explicit:
        raise AgeSetupError("Cannot run the age executable supplied with --age. " + INSTALL_HELP)
    name, expected = artifact_name()
    root = Path(cache) if cache is not None else cache_root()
    archive = root / name
    try:
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        valid = archive.is_file() and not archive.is_symlink() and archive.stat().st_size <= MAX_DOWNLOAD and digest_file(archive) == expected
        if not valid and not allow_install:
            raise AgeSetupError("age is missing and no verified cached copy is available. " + INSTALL_HELP)
        # Each invocation owns its extraction/download directory. Concurrent runs
        # share only the immutable, reverified archive, never an executable path.
        with tempfile.TemporaryDirectory(prefix="run-", dir=root) as work:
            work = Path(work)
            if not valid:
                print("age is not installed. Downloading verified age " + VERSION + " (about 20 MB)…", file=sys.stderr)
                candidate = work / name
                download(RELEASE + name, candidate, expected)
                os.replace(candidate, archive)
                print("age is ready. Continuing recovery; future runs can use the cached copy offline.", file=sys.stderr)
            # Read the verified archive through a private copy to avoid a shared
            # path replacement between verification and executable extraction.
            private_archive = work / name
            shutil.copyfile(archive, private_archive)
            if digest_file(private_archive) != expected:
                raise AgeSetupError("Cached age archive changed during verification. Nothing was executed.")
            executable = work / ("age.exe" if name.endswith(".zip") else "age")
            unpack_executable(private_archive, executable)
            try:
                version = subprocess.run([str(executable), "--version"], check=True, capture_output=True, text=True, timeout=15).stdout.strip()
            except (OSError, subprocess.SubprocessError) as error:
                raise AgeSetupError("Downloaded age could not run on this computer. " + INSTALL_HELP) from error
            if version != "v" + VERSION:
                raise AgeSetupError("Downloaded age reported an unexpected version. Nothing was decrypted.")
            yield str(executable)
    except (urllib.error.URLError, TimeoutError, tarfile.TarError, zipfile.BadZipFile) as error:
        raise AgeSetupError("Unable to set up age automatically. Check your internet connection and retry. " + INSTALL_HELP) from error
