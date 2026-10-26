> **October26 current candidate: build62.** [Vault-password backup option and private reminders](../evidence/build-62/README.md) passes349 unit/security tests, actual-release UI and independent public-fixture age/helper recovery. Installed over61 with Dev44 retained; owner UAT and account-side distribution gates remain. Older checkpoints below are historical. No upload/submission.

> **October26 current candidate: build61.** [Explicit confirmation after password-manager fill](../evidence/build-61/README.md) passes the actual-release UI workflow and signed package/live association checks. Installed over60 with Dev44 retained; owner1Password UAT is pending. Older checkpoints below are historical. No upload/submission.

> **October25 current work: build60.** [Forgotten-password help and explicit erasure](../evidence/build-60/README.md) has342 passing unit/security tests plus a passing full release erase/cancel/fresh-library UI workflow; build60 is installed, with owner UAT pending. Build59 AutoFill association is live; provider UAT remains pending. Older checkpoints below are historical. No upload/submission.

> **Build58 UAT follow-up:** fixes hidden Face ID controls for an authenticated pre-ownership enrollment. See [evidence](../evidence/build-58/README.md); owner confirmation is pending. Older candidate status below is historical.

> **Current candidate: build57, awaiting owner UAT.** Remaining security engineering and limits are recorded in [build57 evidence](../evidence/build-57/README.md). Historical build53/55 packages below must not be used for this candidate. No App Store submission has occurred.

> **Submission hold — October24 follow-up:** build53 must not be submitted while the second security review is remediated (D2S-165–172). Known listing fields may be prepared/saved. Do not submit, release or infer acceptance of build54 from historical build53 tests.

# WagLock 1.0 build53 submission handoff

Engineering preparation and the requested owner phone checks are complete for build53. This supersedes the historical build50 security hold/package. It is **prepared, not uploaded or submitted**. The broader audit remains open; the narrow launch mitigations and residual limits are recorded in [build53 evidence](../evidence/build-53/README.md).

Use [description](description.txt), [review notes](review-notes.txt), [release notes](release-notes.txt), [metadata](metadata.json), [encryption facts](encryption-brief.md) and [eight current screenshots](../screenshots/build53/README.md). Review notes explicitly disclose the independent alternative-passcode library and Face ID assignment. Initial price: Free. Release control: Manual.

The accepted development-signed archive is `/private/tmp/WagLock-1.0-build53-candidate.xcarchive`. It passes identity, encryption, license/source provenance, privacy-reason and signature checks. It is not an App Store distribution IPA. Local export fails with exit70 because no App Store provisioning profile for `com.d2sci.waglock` is installed; this Mac has an Apple Development identity and no distribution identity or configured App Store Connect API credential. No portal registration, profile generation, declaration, upload or submission was performed.

## Account-holder steps

1. In Xcode, sign into the paid Apple Developer team and establish App Store distribution signing/provisioning for `com.d2sci.waglock`. Open the prepared archive in Organizer, export/re-sign and validate it. Keep the separate WagLock Dev app installed. Resolve the account/distribution gates before approving portal changes; do not bypass them with automatic provisioning flags.
2. Create/select the WagLock App Store Connect record. Enter the prepared copy/screenshots, confirm the public publisher/copyright field, and enter the already supplied contact in Apple's private App Review fields. No server account or supplied demo password is required; reviewers create a local library.
3. Complete the actual privacy, age/content, encryption and worldwide-where-permitted territory questionnaires. Use the factual encryption brief; record any required documentation or supported exemption before changing declarations. Do not invent a compliance code or silently exclude France. Review the [source/platform distribution packet](../licensing-review.md); GPL commercial use does not itself require a lawyer letter or separate monetization permission.
4. Upload the distribution-signed validated build, select it after processing, attach the assets and select **manual release** before submission. Confirm the uploaded build is 1.0(53). No release is automatic.

Exact application source: `candidate-1.0-build53`. Matching source, original notices, build guidance and recovery tools are packaged as `/private/tmp/WagLock-1.0-build53-source.tar.gz`; the evidence record gives its commit and checksum. Preserve this source/binary association. Byte-identical reproducible builds and independent audit certification are not claimed. Private Apple passwords, keys and vault passwords must never be pasted into chat or committed.
