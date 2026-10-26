# Build 64 — dated backups and final submission preparation

October 26, 2026. Build 63 remains the owner-accepted security/provider baseline. Build 64 adds UTC Gregorian date/time/millisecond default backup names, refreshed when a completed backup becomes ready, while preserving explicit custom names through handoff. The standard release configuration now selects the same dedicated AutoFill entitlement already accepted with real 1Password on 63. No native ciphertext format, password derivation, album factor, login route or library migration changes.

The final signed development archive is `/private/tmp/WagLock-1.0-build64-prelaunch.xcarchive`; package.json verifies build/identity, encrypted-library activation, signature, original license notices and privacy manifest. association.json verifies the exact live HTTPS webcredentials association and signed app/profile. These are development-signing checks, not App Store distribution clearance.

## Verification

- Full unit/security suite: 355 passed, zero failures/skips; `/private/tmp/waglock-build64-security-final.xcresult`, summarized in unit-tests.json. The earlier low-disk run failed and was interrupted; it is preserved separately and never counted as accepted. After the owner freed space, the complete serial rerun passed.
- Actual separately installed Release64 backup workflow: passed; backup-release-ui.json. Both vaults retain password/reminder scope, risk consent and wrong-password rejection. Defaults match the dated-name contract; clearing disables Save and a custom filename opens the native Files picker. Cancellation does not record a successful backup. The first UI attempt caught a test-only comparison of the Return key with single-line field content; the corrected runner passed without an app-code change.
- Independent official age1.3.2 cold recovery: seven real-format public payloads, nested credentials, metadata/notes/drafts/Unicode and wrong-password/tamper rejection; 16 recovery/layout plus 11 bootstrap tests pass. See [pre-launch evidence](../prelaunch-2026-10-26/).

Actual Release64 reset and decoy UI also pass, one test each with zero failures/skips; see reset-release-ui.json and decoy-release-ui.json. The decoy fixture now waits for initial keyboard presentation before selecting the title; this is a test-only correction. All eight native iPhone/iPad screenshot captures pass and were visually inspected; see ../../screenshots/build64/README.md. Build64 is installed over63, with Dev44 retained; installation.json records the update. Source freeze is bound separately by source.json. Never execute erase automation against the owner’s phone. Existing phone libraries and WagLock Dev are preserved.

## External gates

Local export of this exact64 archive fails because the existing distribution profile lacks Associated Domains. No provisioning updates or upload were performed. Automatic approval review rejected a provisioning refresh as an unapproved persistent Apple-account change; explicit owner approval is required. Preserve the accepted AutoFill entitlement.

The [current ledger](../../prelaunch-status.md) records account fields, encryption/territories and source/platform distribution decisions still required before submission. Passing engineering checks is not an independent audit or App Store approval.
