#!/usr/bin/env python3
"""Check local submission consistency; never upload, mutate accounts or infer compliance."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def check(metadata_path):
    metadata = json.loads(metadata_path.read_text())
    build = str(metadata['build'])
    if not build.isdecimal() or metadata['bundleId'] != 'com.d2sci.waglock':
        raise ValueError('Invalid release identity/build')
    evidence = ROOT / 'docs/release/evidence' / ('build-' + build)
    package = json.loads((evidence / 'package.json').read_text())
    source = json.loads((evidence / 'source.json').read_text())
    tests = json.loads((evidence / 'unit-tests.json').read_text())
    if str(package['build']) != build or package['version'] != metadata['version']:
        raise ValueError('Metadata selects a different build/version from the verified archive')
    if package['bundle'] != metadata['bundleId'] or not package['signatureVerifies'] or not package['encryptedMetadata']:
        raise ValueError('Signed encrypted-release evidence missing')
    tag = 'candidate-1.0-build' + build
    if metadata['sourceTag'] != tag or source['tag'] != tag:
        raise ValueError('Source tag differs from selected release build')
    commit = subprocess.check_output(['git', 'rev-parse', tag], cwd=ROOT, text=True).strip()
    if commit != source['commit']:
        raise ValueError('Source receipt does not match immutable candidate tag')
    if (tests['result'] != 'Passed' or tests['failedTests'] or tests['skippedTests']
            or tests['passedTests'] != tests['totalTestCount'] or tests['passedTests'] < 1):
        raise ValueError('Candidate security suite has not passed completely')
    for field in ['descriptionFile', 'reviewNotesFile', 'releaseNotesFile']:
        path = metadata_path.parent / metadata[field]
        if not path.is_file() or not path.read_text().strip():
            raise ValueError('Missing copy-ready text: ' + field)
    if metadata['releaseType'] != 'MANUAL' or metadata['price'] != 'FREE':
        raise ValueError('Release/pricing differs from owner-approved first release')
    captures = metadata_path.parent / metadata['screenshotDirectory']
    screenshots = 0
    for device in ['iphone-6.9', 'ipad-13']:
        record = json.loads((captures / device / 'capture.json').read_text())
        if (str(record['build']) != build or record['workflowExitStatus'] != 0 or not record['nativeCapture']
                or record['bundle'] != metadata['bundleId'] or record['version'] != metadata['version']
                or not record['encryptedMetadata'] or len(record['screenshots']) != 4):
            raise ValueError('Screenshots are not verified native captures of the chosen candidate')
        if record['resized'] or record['retouched'] or not record['publicFixturesOnly']:
            raise ValueError('Screenshot provenance differs from the approved capture workflow')
        for item in record['screenshots']:
            image = captures / device / item['file']
            if image.name != item['file'] or hashlib.sha256(image.read_bytes()).hexdigest() != item['sha256']:
                raise ValueError('Screenshot digest/path mismatch')
            screenshots += 1
    if screenshots != 8:
        raise ValueError('Expected four iPhone and four iPad screenshots')
    ledger = json.loads((ROOT / 'docs/release/prelaunch-gates.json').read_text())
    pending = [row for row in ledger['gates'] if row['status'] not in ['passed', 'not-applicable']]
    # The ledger is recorded evidence, not a live portal/session check.
    return {'build': build, 'localConsistency': 'passed', 'screenshotsVerified': screenshots,
            'remainingGates': pending, 'readyForSubmission': not pending,
            'liveAccountVerifiedByThisTool': False, 'uploaded': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', type=Path, default=ROOT / 'docs/release/app-store/metadata.json')
    args = parser.parse_args()
    try:
        result = check(args.metadata)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(json.dumps({'localConsistency': 'failed', 'readyForSubmission': False, 'error': str(error)}, indent=2))
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
