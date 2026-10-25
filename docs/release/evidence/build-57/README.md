# Build57 security completion — October25

Engineering evidence for D2S-162/169/170/173 and the build55 secondary UI work. Physical owner acceptance remains pending. Do not upload or submit before UAT and outstanding account/declaration gates.

## Changes

- Native ciphertext filenames and SHA256 digests are authenticated in the encrypted index. Buffered and streaming reads, previews, shares and backups verify the exact ciphertext consumed before publishing plaintext. Swapped valid same-vault ciphertext fails closed. Existing pre-release ciphertext is enrolled once without conversion; tampering before enrollment cannot be detected retrospectively.
- Per-library device-only Keychain stamps reject older/different authenticated database copies. A bounded encrypted recovery journal reconciles interrupted SQLite/Keychain commits from exactly the committed or pending state. Missing/corrupt necessary journals and unavailable anchors fail closed; unknown files and source data are preserved. This assumes the trusted Keychain anchor remains intact; restoring/deleting that trust state is outside the guarantee.
- Successful primary-password and album-factor verification atomically upgrades older wrappers while preserving secrets, album policy and original data keys. Wrong passwords, revoked sessions and uncertain writes cannot silently reset credentials. An older primary wrapper requires one password unlock before Face ID resumes; secondary Face ID never inspects primary credentials. Unsupported legacy secondary envelopes remain rejected.
- Optional secondary checks perform comparable modern KDF work whether configured or absent. Eight public observations per path show medians 93.09ms absent, 93.68ms wrong and 92.34ms valid on this simulator. This is limited timing evidence, not a constant-time or forensic-deniability claim.
- Build55 neutral secondary wording and hidden unavailable biometric controls remain included. Primary setup warnings and honest App Review disclosure remain.

## Verification

Final unit/security suite: **333 passed, zero failures/skips** (205 XCTest plus128 Swift Testing), result `/private/tmp/waglock-build57-security-final.xcresult`. Adversarial cases cover whole-copy/same-revision rollback, corrupt committed inventory, pre/post-commit interruptions, missing/damaged journals, Keychain uncertainty, source/output preservation on ciphertext mismatch, same-key substitution in sharing/backup, authenticated legacy upgrades and secondary isolation.

The initial rollback test attempt exposed the known older-runtime main-actor isolated-deinitializer crash. An explicit nonisolated deinitializer fixes it; all six rollback tests and the full suite pass afterward. Initial compile errors were corrected before these final results.

Official age1.3.2 independently recovers both the retained historical fixture and the newly generated build57 fixture: all seven payload hashes, actual PNG/MOV/WAV/PDF signatures, nested domains, Unicode, notes and drafts match; wrong parent-only credentials and tampering/truncation fail without publishing a destination. Public fixture credentials are synthetic and intentionally checked in. The unit fixture verifies the current backup pipeline; actual release UI separately verifies production mount/binding behavior. No phone media or credentials are included.

Actual release UI, signed archive/package and installation results are recorded below. Full Swift/OS memory erasure, screenshot/external-camera prevention, secure physical erasure and forensic deniability are unsupported. Legacy Dev metadata is unchanged. D2S-105 remains the broader audit; this is not independent audit certification.

## Signed package and installation

Release simulator compilation and development-signed device archive succeed. The actual archive is1.0(57), com.d2sci.waglock, encrypted metadata enabled; signature, original-source/license hashes and privacy-reason checks pass (package.json). Device installation succeeded over the existing public WagLock, preserving vaults and the separate Dev identity; owner UAT is pending. There is no new App Store upload/submission.

The shared Xcode session advanced working build counters to58 during final checks. The source index freezes tested57 and retains the Xcode58 working changes separately, along with unrelated design edits. The archive/package is verified57, not an inferred working-counter value.

## Final actual release UI results

Three workflows pass against the separately installed encrypted Release build57: independent alternative-passcode notes/settings/persistence; main password change preserving the library; and the full note/draft cold-reopen, public photo/video import/native playback, completed encrypted backup, filename editing, Files cancellation, nested album password and relaunch workflow. The first two pass in `/private/tmp/waglock-build57-release-ui.xcresult`. That mixed bundle also contains a failed media test because its system photo cell was not hittable; it is not an overall passing bundle.

The dedicated seeded-media simulator repeated the full workflow. Its first run correctly kept backup creation disabled because the fixture retained a protected album and the test omitted its password. The test now supplies the public fixture album password and unlocks that retained album on repeat runs, without product/security changes. The corrected full workflow passes in `/private/tmp/waglock-build57-store-ui-repeat.xcresult`; the earlier failed result remains `/private/tmp/waglock-build57-store-ui.xcresult`. No unresolved product failure was observed in these final checks.

## Owner UAT

Use WagLock57 with disposable samples. Confirm both existing passcodes open separate persistent libraries; inspect secondary Settings/backup/errors for ordinary vault wording and hidden unavailable biometric controls. Test eligible Face ID assignment, success/cancel, album passwords/change, backgrounded draft/PDF/video, screen-recording blocking and share/cancel. Make and independently recover a backup from each vault, checking only the selected vault appears. Older primary wrapping may require one password unlock before Face ID resumes. Keep originals and send no passwords/private content. App Store submission stays on hold until owner acceptance and account/declaration gates are complete.
