# Build65 — D2S-151 adversarial-review corrections

October26,2026. [Full review, blunt critique and dispositions](../../../portable-vault/audits/D2S-151.md). This is a developer-AI review, not independent human security certification.

Fixes: album-preview ciphertext binding (D2S-179), exact UTF-8 password confirmation (180), generic Files audio selected-vault storage (181), and session-authorized album biometric enrollment (182). Native formats, KDF parameters, vault/album keys, bundle identity and installed libraries are preserved. No automatic orphan cleanup or cross-vault migration.

## Verified automated evidence

- `unit-tests.json`:363 passed, zero failures/skips; `/private/tmp/waglock-d2s151-final363.xcresult`.
- `review-regressions.json`: each bug reproduced before the fix; targeted green runs and the final complete suite retained. Album enrollment tests model consent returning after vault/parent lock; existing real-Keychain sentinel tests cover pre-mutation authorization.
- A new age recipient test rejects valid-encoded low-order X25519 points before archive creation. Age construction and recovery tools are unchanged; [official age1.3.2 recovery evidence](../prelaunch-2026-10-26/independent-recovery.json) retains its actual earlier provenance.

## Candidate and remaining gates

Signed archive: `/private/tmp/WagLock-1.0-build65-adversarial-review.xcarchive`. `package.json` verifies identity, signature, original notices/provenance and privacy manifest. `source.json` binds immutable source1996670 and source archive digest without claiming byte-identical reproducibility. `association.json` and `distribution-association.json` verify the exact signed entitlement/profile and live HTTPS domain. `distribution-signing.json` verifies the locally exported Apple Distribution IPA, App Store profile and disabled debugger entitlement. No account refresh was needed for65 and no upload/server validation occurred.

`confirmation-release-ui.json` records the actual separately installed65 setup/change/mismatch/fallback pass. `management-backup-release-ui.json` records two passes for primary-only management, collision rejection, both-vault isolation, clearing on background, backup filename/reuse and per-vault reminder settings. All tests use the new public Confirmation Audit65 simulator, not the owner's phone.

Eight matching native public [iPhone/iPad captures](../../screenshots/build65/README.md) pass and were visually checked. Original native JPEG pixels are retained;64 is not relabeled. `installation.json` records65 installed/launched over64 with Dev44 retained, no reset/uninstall or private-content read. Owner replied “passed” to the full focused65 phone/recovery checklist on October26; `owner-uat.json` retains the exact scope and reply.

`owner-risk-acceptance.json` records explicit October26 acceptance of the disclosed material limits for1.0, including AI-only assurance and183/184 deferrals. No upload/submission/release authorization follows.64 must not be submitted; focused65 phone UAT now passes. D2S-151 is complete; the external gates in the authoritative release ledger remain.
