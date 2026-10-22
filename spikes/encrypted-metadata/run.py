#!/usr/bin/env python3
"""Disposable process-boundary checks; never opens the app library."""
import json
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='waglock-metadata-probe-') as temporary:
    root = Path(temporary).resolve()
    executable = root / 'probe'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    str(repo / 'WagLock/Services/Metadata/EncryptedMetadataStore.swift'),
                    str(Path(__file__).with_name('CrashProbe.swift')), '-lsqlite3', '-o', str(executable)], check=True)
    for mode, status, revision, payload in [('before', 71, 1, 'original-public-fixture'),
                                            ('after', 72, 2, 'changed-public-fixture')]:
        destination = root / mode
        subprocess.run([str(executable), 'create', str(destination)], check=True)
        result = subprocess.run([str(executable), mode, str(destination)])
        assert result.returncode == status, result.returncode
        recovered = json.loads(subprocess.check_output([str(executable), 'read', str(destination)]))
        assert recovered == dict(fixtureOnly=True, revision=revision, count=1, payload=payload), recovered
        print(f'{mode}-commit process termination: passed')
