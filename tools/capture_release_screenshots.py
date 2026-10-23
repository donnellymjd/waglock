#!/usr/bin/env python3
"""Capture unedited native simulator screens from the actual separately installed release.

Only the isolated, publicly seeded release QA devices are accepted. Does not reset,
install or read a user's vault. XCTest drives public sample data; simctl records pixels.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('simulator')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
    device = next(d for group in devices['devices'].values() for d in group if d['udid'] == args.simulator)
    if not device['name'].startswith('WagLock Encrypted Release QA Store '):
        parser.error('Requires a dedicated public-fixture Store QA simulator')
    app = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator, 'com.d2sci.waglock', 'app'], text=True).strip())
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.d2sci.waglock' or info.get('WagLockEncryptedLibrary') != 'YES':
        parser.error('The actual installed bundle must use fresh encrypted release storage')
    args.output.mkdir(parents=True, exist_ok=False)
    command = ['xcodebuild', 'test', '-project', 'WagLock.xcodeproj', '-scheme', 'WagLock',
               '-destination', f'platform=iOS Simulator,id={args.simulator}', '-parallel-testing-enabled', 'NO',
               '-derivedDataPath', '/private/tmp/waglock-release45-ui-tests',
               '-resultBundlePath', str(args.output / 'Workflow.xcresult'),
               '-only-testing:WagLockUITests/EncryptedReleaseUITests/testFreshReleasePersistenceAndScreenshots']
    shots = []
    with (args.output / 'workflow.log').open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout:
            log.write(line); log.flush()
            if line.startswith('WAGLOCK_NATIVE_CAPTURE:'):
                name = line.strip().split(':', 1)[1].replace('Store - ', '').lower().replace(' ', '-')
                target = args.output / (name + '.png')
                subprocess.run(['xcrun', 'simctl', 'io', args.simulator, 'screenshot', str(target)], check=True)
                shots.append(dict(file=target.name, sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
                print('Captured ' + target.name, flush=True)
        status = process.wait()
    record = dict(bundle=info['CFBundleIdentifier'], version=info['CFBundleShortVersionString'],
                  build=info['CFBundleVersion'], encryptedMetadata=True, simulator=device['name'],
                  uneditedNativePixels=True, publicFixturesOnly=True, workflowExitStatus=status, screenshots=shots)
    (args.output / 'capture.json').write_text(json.dumps(record, indent=2) + '\n')
    return status if status else (0 if len(shots) == 6 else 1)


if __name__ == '__main__':
    sys.exit(main())
