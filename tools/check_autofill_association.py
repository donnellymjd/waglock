#!/usr/bin/env python3
"""Verify the dedicated public association; never reads or submits vault credentials."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import urllib.request

DOMAIN = 'waglock.d2sci.co'
APP_ID = 'Z3B45KM866.com.d2sci.waglock'
ENTITLEMENT = 'com.apple.developer.associated-domains'
EXPECTED = {'webcredentials': {'apps': [APP_ID]}}
ROOT = Path(__file__).resolve().parents[1]

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, url):
        return None

def unique_keys(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('Duplicate JSON key in association')
        value[key] = item
    return value

def association(data):
    if len(data) > 128 * 1024 or json.loads(data, object_pairs_hook=unique_keys) != EXPECTED:
        raise ValueError('Association must allow only the exact production application identifier')

def remote(url):
    opener = urllib.request.build_opener(NoRedirect)
    with opener.open(url, timeout=20) as response:
        if response.status != 200 or response.headers.get_content_type() != 'application/json':
            raise ValueError('Association requires HTTP200 and application/json, without redirects')
        association(response.read(128 * 1024 + 1))

def local():
    association((ROOT / 'hosting/autofill/public/.well-known/apple-app-site-association').read_bytes())
    entitlements = plistlib.loads((ROOT / 'config/PasswordAutoFill.entitlements').read_bytes())
    if entitlements != {ENTITLEMENT: ['webcredentials:' + DOMAIN]}:
        raise ValueError('Unexpected entitlement or associated domain')
    config = (ROOT / 'config/PasswordAutoFill.xcconfig').read_text()
    if '#include "AppStore.xcconfig"' not in config or 'CODE_SIGN_ENTITLEMENTS = config/PasswordAutoFill.entitlements' not in config:
        raise ValueError('Opt-in configuration does not include the production configuration and entitlement')
    hosting = json.loads((ROOT / 'hosting/autofill/firebase.json').read_text())['hosting']
    if hosting.get('target') != 'waglock-autofill' or hosting.get('public') != 'public' or hosting.get('redirects') or hosting.get('rewrites'):
        raise ValueError('Hosting must use the isolated static target without redirects or rewrites')
    if '**/.*' in hosting.get('ignore', []):
        raise ValueError('Hosting would exclude the .well-known association file')

def signed_app(app):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.d2sci.waglock':
        raise ValueError('Only the public release app may use this association')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, check=True)
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True)
    values = plistlib.loads(result.stdout)
    if values.get('application-identifier') != APP_ID or values.get(ENTITLEMENT) != ['webcredentials:' + DOMAIN]:
        raise ValueError('Signed app is missing the exact release association')
    profile = subprocess.run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')], capture_output=True, check=True)
    permitted = plistlib.loads(profile.stdout)['Entitlements']
    if permitted.get('application-identifier') != APP_ID:
        raise ValueError('Use an explicit WagLock App ID provisioning profile')
    domains = permitted.get(ENTITLEMENT, [])
    if domains != '*' and '*' not in domains and 'webcredentials:' + DOMAIN not in domains:
        raise ValueError('Provisioning profile does not permit the association')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--online', action='store_true', help='Verify the live HTTPS association endpoint')
    parser.add_argument('--app', type=Path, help='Verify an actual device-signed production app and provisioning profile')
    args = parser.parse_args()
    try:
        local()
        if args.online:
            remote('https://' + DOMAIN + '/.well-known/apple-app-site-association')
        if args.app:
            signed_app(args.app)
        print(json.dumps({'domain': DOMAIN, 'applicationIdentifier': APP_ID, 'localContract': 'passed',
            'liveHTTPS': 'passed' if args.online else 'not checked',
            'signedDeviceApp': 'passed' if args.app else 'not checked',
            'passwordManagerDeviceUAT': 'required', 'readyForRelease': False}, indent=2))
        return 0
    except Exception as error:
        print('AutoFill verification stopped: ' + str(error), file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
