# Build65 — D2S-151 adversarial-review corrections

October26,2026. [Full review, blunt critique and dispositions](../../../portable-vault/audits/D2S-151.md). This is a developer-AI review, not independent human security certification.

Fixes: album-preview ciphertext binding (D2S-179), exact UTF-8 password confirmation (180), generic Files audio selected-vault storage (181), and session-authorized album biometric enrollment (182). Native formats, KDF parameters, vault/album keys, bundle identity and installed libraries are preserved. No automatic orphan cleanup or cross-vault migration.

## Verified automated evidence

- `unit-tests.json`:363 passed, zero failures/skips; `/private/tmp/waglock-d2s151-final363.xcresult`.
- `review-regressions.json`: each bug reproduced before the fix; targeted green runs and the final complete suite retained. Album enrollment tests model consent returning after vault/parent lock; existing real-Keychain sentinel tests cover pre-mutation authorization.
- A new age recipient test rejects valid-encoded low-order X25519 points before archive creation. Age construction and recovery tools are unchanged; [official age1.3.2 recovery evidence](../prelaunch-2026-10-26/independent-recovery.json) retains its actual earlier provenance.

## Candidate and remaining gates

Signed archive being prepared: `/private/tmp/WagLock-1.0-build65-adversarial-review.xcarchive`. Receipts for actual-release UI, package/distribution signing, source freeze and installation are added only after those steps succeed.64 remains historical and must not be submitted. Focused65 phone UAT and explicit owner acceptance of material review limits remain required. No upload, submission or public release is authorized by these receipts.
