# First App Store submission

> October24 follow-up: **submission hold** for build53. Track D2S-165–172 and [build55 remediation](../portable-vault/security-review-build55.md). Prior engineering/phone acceptance below does not accept the new changes.

Owner direction: prepare a small first release with manual release. **Current candidate: 1.0(53), engineering and requested owner phone checks passed October24; account-side distribution gates remain open.** Use the [current submission handoff](app-store/README.md) and [build53 evidence](evidence/build-53/README.md). Earlier build-specific sections below are historical and do not override this checkpoint. No upload or submission has occurred.

## Scope and order

1. Finish the October23 [security triage](../portable-vault/security-launch-triage.md), then independent Guest Mode with populated-vault isolation/recovery evidence. Resolve the distribution route in [the licensing packet](licensing-review.md), while preparing metadata, privacy/support and build assets.
2. Finish password-protected native metadata/notes/thumbnails and safe source-preserving integration. Preserve current album/password boundaries. Build45 mounts encrypted models/drafts only for a fresh release library; legacy development data remains untouched.
3. Verify supported complete backup recovery, readable originals and album credentials without the original Keychain. Define excluded/unsupported cases honestly; a complete export must fail rather than silently omit content. Finish the pending owner readable-output and filename checks separately from build 41 notes acceptance.
4. Freeze a small candidate; complete install/update, lock/unlock, import/view/share/background, album, notes and recovery regressions on the release identity. Capture final screenshots from disposable samples on supported iPhone/iPad sizes. Review compatibility and any stored references under that identity.
5. Match the final source tag, license notices, privacy policy/manifest, Apple privacy answers, encryption determination, review instructions and listing to that exact archive. Upload/validate through the authorized Apple account only after gates are cleared. Select manual release when submitting; do not release automatically.

Shared albums, Trash, encrypted search, self-destruct lock and unlock-camera capture remain deferred from first-release scope. **Independent Guest Mode is now required for1.0 (D2S-115 Urgent), following the owner’s October23 clarification.** Keep their Linear requirements; do not claim they are shipped. Existing presentation-only Guest Mode must be removed from the public candidate or retain unambiguous limited claims under review; it is not duress protection. The public candidate hides presentation-only Guest Mode. No legacy native storage migration is enabled by this document.

## Readiness gates

| Gate | Current evidence / outstanding work |
| --- | --- |
| Distribution rights — D2S-106/118 | GPL commercial use is permitted; upstream explicitly describes branded App Store forks. Exact platform/source-conveyance compliance review remains open. A lawyer or separate monetization permission is not a GPL prerequisite; see the clarified review packet. |
| Native security — D2S-105/116/143 | 314 unit/security tests pass. Independent vaults and requested final phone checks are accepted; see build53 evidence. Actual encrypted release UI verifies password changes and cold relaunch without losing notes. Fresh release libraries encrypt metadata/notes/thumbnails; legacy Dev A01 and broader preview/key/rollback findings remain open. Requested build53 physical acceptance passed. |
| Recovery — D2S-110/114/141 | Independent official age recovery passes for both legacy and actual encrypted-library fixtures, including seven exact payloads, notes/drafts, Unicode and nested passwords without phone/Keychain. Owner final readable-output/filename confirmation and provider behavior remain; older buffered sources above64MiB are explicitly blocked. No native in-app restore is claimed. |
| Identity — D2S-117/118 | Proposed store identity `com.d2sci.waglock`, display WagLock, initial marketing version 1.0. Opt-in [release configuration](../../config/AppStore.xcconfig) does not change Debug or register an App ID. Existing phone `com.d2sci.vaultito.dev` is preserved. |
| Privacy/support | Current English [policy](../../PRIVACY_POLICY.md), [support](support.md) and in-app links prepared; inherited policy preserved verbatim. Recheck against final release; select private developer/review contact and validate public URLs before upload. |
| Apple privacy/crypto | Privacy manifest exists; final accessed-API reasons, privacy-label answers, backup behavior and export classification need exact-binary review. No exemption flag has been assumed. See [compliance worksheet](compliance.md). |
| Listing/assets | [Draft listing/review instructions](store-listing.md) prepared. Eight native build53 iPhone/iPad screenshots are prepared; age/content questionnaire, territory selection, ownership review of every icon, contact fields and account agreements remain. |
| Archive/source | Unsigned release archives verify packaging; a development-signed release-identity build uses the existing cached wildcard profile without registration. Development-signed build53 archive, source freeze and device/recovery evidence are prepared. Distribution signing/validation and account declarations remain. No App Store Connect app record/upload/submission has been performed by this preparation. |

## Identity preparation without stranding existing data

The preview config selects `com.d2sci.waglock` only when explicitly passed for an app build/archive. It keeps the Swift module name stable. A new bundle ID gets a separate container and bundle-derived Keychain service; it does not transfer the development library. Do not point it at the old live store, copy credential namespaces or uninstall the development app. Register the final ID only after the distribution route is resolved and selected; review provisioning, entitlements, tests and any biometric enrollment independently. For a fresh public install, old development data stays in the separate development app until a verified transfer path exists.

Configuration-only compilation (no signing, provisioning updates, registration, upload or installation):

```sh
xcodebuild build -project WagLock.xcodeproj -scheme WagLock \
  -configuration Release -xcconfig config/AppStore.xcconfig \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/waglock-appstore-preview \
  CODE_SIGNING_ALLOWED=NO
```

Do not use the global bundle override for unit/UI test targets; normal tests retain their separate development test identities. Successful compilation is not submission readiness.

Apple supports [manual release after review](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/). Follow-up development can continue in source; later App Store versions require their own submission and Apple's [version-status requirements](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/). No approval time or approval outcome is promised.

## Preparation validation — build 42 source

Full unit regression passed 247 tests (136 XCTest +111 Swift Testing). The existing Light/Dark remaining-destinations UI flow passed, including the updated offline/privacy screen. Unsigned Release compilation with the opt-in overlay passed; Info.plist confirms `com.d2sci.waglock`, display WagLock, version 1.0/build 42. Normal simulator Debug remains `com.d2sci.vaultito.dev`, WagLock Dev, version 1.3.8/build 42. The owner phone remains accepted build 41; no build 42 install, registration, upload or native migration occurred. Exact upstream policy bytes/hash and original audit preservation were checked.

These results validate preparation, not public readiness. Licensing/rights review, active metadata security, complete recovery and final signed-archive/account/screenshot/privacy/crypto validation remain open.


## Build 43 preparation follow-up — October 23, 2026

The complete unit suite passes 260 tests. Explicit model writes now require the active mount lease, automatic saving is disabled on managed main contexts, and uncertain saves preserve potentially referenced resources. The explicit-root encrypted repository exercises that boundary without production activation. Signed development and unsigned opt-in store Release builds pass, with the same stable development ID and proposed store ID respectively. [Implementation and remaining activation gates](../portable-vault/library-write-boundary.md). This is security groundwork; A01, complete supported recovery and final distribution-package validation remain open.

Build 43 is installed and launched on the owner phone under the stable development identity. The final 260-test suite includes a rendered SwiftUI attachment test confirming the managed main context remains autosave-disabled; all three selected application UI workflows pass. Owner acceptance is pending. No store upload/submission occurred.

Owner follow-up October23: normal app checks reported working; revised build44 video-viewer review remains pending. This does not independently confirm complete backup recovery or close release/security gates.


## Build 45 fresh release candidate — October 23

[Fresh-library contract](../portable-vault/fresh-encrypted-library.md). New public-identity libraries encrypt metadata, thumbnails, notes and drafts; new credentials use independent random data secrets, preserved across password changes. Exclusive bootstrap/Keychain identity anchoring reject missing/substituted roots and preserve interrupted stages. No legacy migration, source retirement or owner-library access was performed. Public Guest Mode is hidden and rejected. Encoded image originals supplied by Photos/Files are preserved; edit history and Live Photo motion remain excluded.

Independent official age 1.3.2 recovery of the checked-in actual encrypted-library backup verifies seven PNG/MOV/PDF/WAV payloads byte-for-byte, notes/drafts, Unicode and nested protection without the original phone/Keychain. Both parent-only credentials and damaged archives fail. The older fixture also still passes. All 58 Python tests and both before/after-commit process-termination probes pass. A 1,000-record scale sample saved in 2.91 seconds/reopened in 1.55 seconds on simulator. The final unit run after the gallery remount correction passes 279 tests with no failures or skips.

Actual release UI checks cover notes/drafts through cold relaunch, Photos/video imports and standard playback, backup filename clearing/editing and Files picker cancellation, nested protected albums, and changing/restoring the owner password without losing the library. An inherited background missing-file cleanup caused a confirmed password-remount crash and was removed; missing ciphertext must never trigger automatic metadata deletion. Password change/restoration and cold reopen pass on the actual release bundle. Final screenshot/archive results are recorded below when complete.

Still required before submission: owner physical acceptance of the separate encrypted app; final signed-distribution validation and matching source freeze; account-holder privacy/export/territory/contact and age/content declarations; distribution-compliance review; App Store record/upload and manual-release selection. No automatic iOS native restore or provider remote-upload completion is claimed. The owner selected worldwide availability where permitted and supplied private App Review contact details in conversation; keep them out of public source. No registration, upload, submission or release has occurred.


### Final package and installed candidate

The final279-test regression has zero failures/skips;58Python tests, both recovery fixtures and both process-termination probes pass. Development-signed WagLock1.0(45) is installed on the owner phone under **com.d2sci.waglock**, alongside unchanged WagLock Dev. Remote launch was denied by the phone lock; [physical acceptance](device-acceptance.md) is pending. The final unsigned verification archive succeeds at `/private/tmp/WagLock-1.0-build45-final.xcarchive`, with source build counter45 preserved. The package checker verifies identity, actual encrypted-mode activation, fullGPL/BSD notices, original source hashes and privacy reasons, and correctly rejects a legacy Dev bundle. [Machine-readable evidence](evidence/build-45/README.md). The archive is not distribution-signed/upload-ready. No export declaration was invented.


### Owner acceptance failure — release blocked

The owner reports that a newly created build45 library cannot reopen after locking: “Unable to open this library”, Retry/Lock. Previous cold-relaunch/password-change simulator passes do not override this physical failure. Preserve both apps, all original credentials and library files; no reset/recreation/migration is authorized. Investigate same-process lock/remount and add only fixed non-sensitive failure references if hardware diagnosis requires them. Build46 is diagnostic work, not a submission-ready successor. Worldwide availability where permitted is the owner's choice; private review contact details were supplied in conversation and must stay out of this public repository. Export classification and distribution acceptance remain unfiled.


### Build47 phone-path correction

The phone's fixed diagnostic reference WL-M03 confirmed bootstrap path validation. Foundation can abbreviate resolved `/private/var` paths back to Apple's `/var` symlink. The new fresh-bootstrap validator mistakenly rejected that OS alias, although the existing ciphertext index already handled it. It now expands only verified `/var`/`/tmp` OS aliases with their expected targets and continues rejecting all other symlink components. New regression verifies the allowed system aliases and an untrusted nested symlink, without weakening root identity/authentication or resetting files. Build46 supplied redacted diagnostics; build47 includes the correction. Only the new app's top-level Application Support directory was enumerated for diagnosis; no media, descriptor, credential or index content was read.

Build47 installs over the separate new WagLock app, preserving its container/credentials. The owner confirms it now opens with the same password and survives two lock/unlock cycles. That closes this specific phone blocker; the rest of the final disposable-media/album/FaceID/backup acceptance checklist remains to be completed. WagLock Dev is unchanged. Worldwide where permitted and the private App Review contact are recorded from the owner; private contact fields stay outside the public repo. Distribution compliance/export declarations and final account signing/upload remain unfiled.


### Final build47 engineering package

All **281** unit/security tests pass with zero failures/skips. Two actual release UI workflows on iOS26.5 pass password changes/cold persistence and repeated in-process locking. The actual release iPad13 workflow passes notes/drafts, real image/video imports and native playback, editable backup naming, system Files cancellation and nested password protection. The iPhone listing workflow passes too. Eight native JPEG screenshots are checked in at [build47 captures](screenshots/build47/README.md), with accepted pixel dimensions, no alpha and per-file hashes. Earlier iPad harness failures were corrected by using top navigation, the native Cancel control and the picker value hit area; no app behavior was bypassed.

The final unsigned archive succeeds at `/private/tmp/WagLock-1.0-build47-candidate.xcarchive`; the source counter remains47. Actual signed phone and unsigned archive package checks verify public identity, encrypted mode, notices/source hashes and privacy reasons. [Evidence](evidence/build-47/README.md). Exact source freeze: `candidate-1.0-build47`. The owner confirms only the specific opening/repeated-lock fix so far; broader physical acceptance remains pending. Use [the final submission runbook](submission-runbook.md) for outstanding distribution/account actions. No App Store upload/submission has occurred.


### Build48 naming-only follow-up

The owner reported both icons named WagLock Dev. A shared localized CFBundleDisplayName overrode the release setting; removing that override makes the effective English names **WagLock** (release) and **WagLock Dev** (development). Build48 is signed and installed over the same public identity without reinstall/reset or storage/credential changes. Three localization/identity tests and actual built-name checks pass. The package checker now rejects mismatched localized release names, including the older build47 archive, and accepts the corrected build48 signed package. Source tag: candidate-1.0-build48. Regenerate the distribution archive from this newer source; historical build47 archive/evidence remains retained. Broader physical/distribution gates remain unchanged.


### Build49 note follow-up

The owner clarified that the unsaved note remained accessible through New and was missing only from the list. Add a visible Resume draft entry under Unfinished note, retaining the existing encrypted draft and explicit Done behavior. Also close a deterministically reproduced pending-save/background-revocation timing gap by flushing the matching authorized editor synchronously before revocation; cancelled timers stay revoked. No native format, identity, credential or existing library migration changes. [Draft behavior and security boundary](../portable-vault/draft-preservation.md). Build49 validation/installation and the exact background-without-Done physical check remain to be recorded; earlier source tags/archives are historical and do not include this follow-up.


Build49 final engineering evidence:282 unit/security tests pass without failure/skip; the actual encrypted release iOS26.5 UI passes background without Done, visible Resume draft, exact text recovery through cold relaunch and another background cycle, Done clearing the draft row, and background persistence of an existing-note edit. The controlled-delay background regression failed before the fix and now passes with wrong-session/late-timer protections. Signed build/package checks pass. Build49 is installed over the same release app with library/credentials intact; owner repetition is requested. Source tag: candidate-1.0-build49. This does not update historical archives/screenshots or clear the remaining physical/distribution/account gates.


### Build50 follow-up — intermittent unfinished note report

Build49 owner acceptance remains incomplete: the owner reported another newly typed draft missing, then a successful attempt. The release identity/build was verified. An initial suspected navigation reproduction was invalid: Foundation ignored the negative auto-lock test argument, so the app locked as configured. Final no-lock checks select Never through Settings. Build50 uses stable UUID-bound editor presentation, seeds draft text before constructing controls, and stops reloading text on each appearance. It retains build49's authorized background flush and persistence format. Simulator testing must cover both auto-lock settings and cold relaunch; physical iOS27.0.1 acceptance remains required. [Details](../portable-vault/draft-preservation.md). Unrelated design-handoff changes in the checkout are preserved separately. No App Store submission occurred.


Build50 investigation also confirms a delayed-save defect: the debounce task cancelled itself immediately before calling the cancellation-checking encrypted repository. A controlled real-repository/reopen regression fails on old code. Detaching the completed timer handle before flush fixes that path without bypassing cancellation or lock checks. Immediate background could succeed while pausing first failed, consistent with the owner's intermittent report. Final post-fix regression/device evidence follows; initial282 passes preceded this additional correction and are not final evidence for it.


Final build50 engineering verification:283 unit/security tests pass, including the formerly failing delayed encrypted-save/reopen regression. Actual signed release UI passes paused body-only draft/background/cold reopen and the longer draft/Done/existing-note workflow; corrected Settings-based Never mode passes five paused edit/background cycles. [Checked-in evidence](evidence/build-50/README.md). The mixed UI bundle's obsolete negative-argument case is a failure, not an overall pass. Physical owner repetition remains pending; no distribution gates are cleared by these tests.

Build50 is installed over the existing release identity, preserving its library/credentials. Owner repetition is requested; do not mark the intermittent phone issue accepted until that reply. Source freeze: candidate-1.0-build50.

Build50 physical follow-up: owner reports a new/backgrounded item appeared as a regular saved note without Done/Save note; another stayed a draft. The owner cannot reproduce it on a subsequent disposable retry. Keep this intermittent classification report open, separate from the verified delayed-write cancellation fix. Added UI coverage checks actual saved-note counts/content, draft A/B, keyboard Return, both auto-lock settings and cold reopen. No speculative production change or library conversion is made. Full physical acceptance remains incomplete.


## October23 final package and owner acceptance

Owner confirms the complete build50 phone checklist passed, including independent Mac backup recovery. The intermittent note-classification report remains tracked without a claimed fix. Current build50 archive succeeds using cached development signing and passes identity/encryption/notices/privacy/signature checks. Exact application source is unchanged from candidate-1.0-build50. Matching tagged source tarball and hash are prepared. Both current iPhone/iPad screenshot workflows pass; eight unedited images have verified dimensions/hashes in [build50 screenshots](screenshots/build50/README.md). Ready-to-copy store text and factual encryption brief are in [app-store](app-store/README.md).

A local App Store export fails with exit70: no iOS App Store provisioning profile for com.d2sci.waglock. This Mac has one usable Apple Development identity, no local distribution identity and no configured App Store Connect API key. No provisioning updates, remote identifier registration, declaration, upload or submission occurred. Account signing/provisioning and final privacy/encryption/territory/publisher entries remain required. [Machine-readable handoff](evidence/build-50/submission-preparation.json).

The first attempt to save this handoff was not executed because automatic approval review reached a usage limit; this was a review-service failure, not a safety finding. After the limit reset, the owner requested continuation and the normal approval path succeeded. No approval bypass was used.


## Security review hold — build51 work

The owner supplied a13-item security review after build50 preparation and explicitly authorizes disabling calculator login for1.0. Create D2S-152–164 and address confirmed launch exposure before another archive/source freeze. Build50 is historical and must not be uploaded. [Report and triage](../portable-vault/security-launch-triage.md). Existing device acceptance does not validate the upcoming security changes.

October24: owner confirms the requested build51 physical checks passed (password changes/media persistence, draft/background resume, Face ID/immediate locking and already-active recording protection). Guest Mode integration, remaining review items and account-side submission gates are still open. This does not accept any later Guest Mode development build.


## Build52 independent-vault candidate — October24

Build52 connects ordinary primary/secondary passcodes to immutable selected-vault services, separate modern credentials, encrypted indexes/media roots, album biometric/attempt namespaces and selected-only age backups. Explicit Face ID assignment to either vault retains the disclosure warning and primary legacy-enrollment compatibility.309 unit/security checks and the actual-release two-vault persistence/settings UI check pass; see [implementation and limits](../portable-vault/secondary-vault-design.md). The signed development candidate is installed over WagLock on the owner's iPhone without resetting the primary library. Physical acceptance of populated vaults, Face ID assignment, background previews/drafts and secondary backup recovery is requested and pending. This supersedes earlier statements that the public candidate only hides/rejects Guest Mode; it does not clear any remaining security/distribution/declaration gate or authorize upload. Build50 archives/screenshots/source freezes remain historical.


## October24 — build52 owner acceptance passed

The owner replied “passed” to the complete requested build52 phone checklist: the existing main library opens; an alternative passcode creates/opens its own photo, note and protected-album library with cold-relaunch persistence and separation in both directions; Face ID can be explicitly assigned to each vault, shows the disclosure warning, opens only the assigned vault and remains locked on cancellation; backgrounded note/PDF behavior works; and a backup made from the secondary vault independently recovers only that vault. No passwords or private media were requested or retained.

D2S-115 is Done for the requested1.0 feature. This is owner-reported physical functional/recovery acceptance paired with309 unit/security tests and3 actual-release UI workflows, not independent audit, forensic-deniability or full security certification. D2S-105 and remaining review findings/distribution gates stay open. Installed candidate remains WagLock1.0(52), implementation cd9741f; no new binary, migration, reset, archive/upload or submission was made for this acceptance record.


## October24 — final build53 acceptance and handoff

The owner passed the final build53 phone checklist: both existing passcodes and assigned Face ID open the expected vault/samples; disposable video/PDF background/resume has no crash, unexpected playback or preview; recording started through Control Center while unlocked blocks viewing until stopped and then requires unlock. Build52 populated-vault persistence and selected-only independent backup recovery acceptance remains recorded. Both vaults and the separate WagLock Dev app were preserved.

Build53 refuses old fast owner/guest verifier slots, native ZNSC v1 reads and native .encrypted imports in the public encrypted release while preserving explicit Dev/recovery readers and modern credentials. No migration/reset/format conversion occurs. Password inputs clear on background/disappearance; logged-out password changes fail closed. Generic media results must still belong to the active originating context after awaits, and late owned plaintext is removed. A deterministic paused video completion/logout regression verifies this boundary.

Verification:314 unit/security tests (186 XCTest +128 Swift Testing),57 focused credential/import/stream tests,7 final media-lifecycle tests,2 actual-release regression UI workflows, both native iPhone/iPad screenshot workflows and16 Python backup-tool tests pass. Official age1.3.2 independently recovers both checked-in public fixture sets; actual encrypted-library MOV/PDF/PNG/WAV payloads, notes/drafts/Unicode, nested passwords and tamper/truncation rejection pass without phone/Keychain. Full suite: `/private/tmp/waglock-build53-full.xcresult`; release UI: `/private/tmp/waglock-build53-release-regressions.xcresult`. An initial lifecycle-test compile failure attempted an unsupported Swift extension override; the corrected injectable loader seam and final runs supersede it.

D2S-158/159/161/164 launch mitigations are Done, bringing completed report findings to12 of13; D2S-115 independent Guest Mode remains Done. D2S-162 stays open for ciphertext-to-record identity binding: a filesystem writer may substitute valid same-vault ciphertext. v2 authenticates framing/order/length/end, not metadata-entry identity. Whole database rollback, legacy Dev metadata, complete memory zeroization and direct AirPlay hardware validation remain limitations. No screenshot/external-camera prevention, secure physical erasure, forensic deniability or independent audit certification is claimed. D2S-105 remains open for broader audit work.

The final development-signed build53 archive/package/signature checks pass. Eight native unedited public-fixture screenshots and copy-ready store metadata/review instructions are prepared. App Store export fails exit70: missing App Store distribution provisioning profile for com.d2sci.waglock. Only a development identity is available; no App Store Connect API credential is configured. Account distribution signing, source/platform distribution review and privacy/encryption/territory/publisher declarations remain external gates. No automatic provisioning update, upload or submission occurred. See [current handoff](app-store/README.md).
