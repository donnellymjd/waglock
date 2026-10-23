#!/usr/bin/env python3
"""Verify release identity, encryption activation, notices and manifest in a built app.

This is a packaging check, not App Store/legal clearance or an independent audit.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def verify(app):
    repo = Path(__file__).resolve().parents[1]
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    expected = {'CFBundleIdentifier': 'com.d2sci.waglock', 'CFBundleDisplayName': 'WagLock',
                'CFBundleShortVersionString': '1.0', 'WagLockEncryptedLibrary': 'YES'}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'{key}: expected {value!r}, found {info.get(key)!r}')
    # Localized values override Info.plist on the Home Screen and in system UI.
    for localized in app.glob('*.lproj/InfoPlist.strings'):
        values = plistlib.loads(localized.read_bytes())
        display = values.get('CFBundleDisplayName', info['CFBundleDisplayName'])
        if display != expected['CFBundleDisplayName']:
            raise ValueError(f'{localized.parent.name}: localized display name overrides the release name')
    notices = (app / 'OpenSourceNotices.txt').read_text()
    if (repo / 'LICENSE').read_text().strip() not in notices:
        raise ValueError('Full GPL license missing from bundled notices')
    if (repo / 'WagLock/Support/Scrypt/COPYRIGHT.txt').read_text().strip() not in notices:
        raise ValueError('Bundled BSD notice missing')
    provenance = json.loads((repo / 'WagLock/Support/Scrypt/PROVENANCE.json').read_text())
    for name, expected_hash in provenance['originalFiles'].items():
        if hashlib.sha256((repo / 'WagLock/Support/Scrypt' / name).read_bytes()).hexdigest() != expected_hash:
            raise ValueError('Original source hash changed: ' + name)
    manifest = plistlib.loads((app / 'PrivacyInfo.xcprivacy').read_bytes())
    reasons = {row['NSPrivacyAccessedAPIType']: set(row['NSPrivacyAccessedAPITypeReasons'])
               for row in manifest['NSPrivacyAccessedAPITypes']}
    expected_reasons = {'NSPrivacyAccessedAPICategoryFileTimestamp': {'C617.1', '3B52.1'},
                        'NSPrivacyAccessedAPICategoryDiskSpace': {'E174.1', '85F4.1'},
                        'NSPrivacyAccessedAPICategoryUserDefaults': {'CA92.1'}}
    if reasons != expected_reasons or manifest.get('NSPrivacyTracking') is not False:
        raise ValueError('Privacy manifest differs from reviewed source inventory')
    signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
    executable = app / info['CFBundleExecutable']
    return dict(bundle=info['CFBundleIdentifier'], version=info['CFBundleShortVersionString'],
                build=info['CFBundleVersion'], encryptedMetadata=True, licenseAndOriginalSourceHashesVerified=True,
                privacyReasonsVerified=True, executableSHA256=hashlib.sha256(executable.read_bytes()).hexdigest(),
                signatureVerifies=signature.returncode == 0,
                exportDeclarationPresent='ITSAppUsesNonExemptEncryption' in info,
                readyForUpload=False,
                remainingGates=['security launch triage and independent guest-vault acceptance', 'physical acceptance', 'distribution signing/validation', 'distribution compliance review',
                                'account-holder privacy/export/territory/contact declarations', 'App Store record and manual-release submission'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.app), indent=2))
    except (OSError, ValueError, KeyError) as error:
        print('Candidate rejected: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
