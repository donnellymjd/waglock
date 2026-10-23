# First App Store submission

Owner direction: October 22, 2026. Prepare a small first release, submit when ready with **manual release**, and develop follow-up improvements separately. **Status: not ready for submission.** The owner accepted normal development-app flows through build43; a separate fresh encrypted build45 now needs final physical acceptance. Earlier build41 checks provide functional evidence, not public-release security/licensing acceptance.

## Scope and order

1. Resolve the distribution route in [the licensing packet](licensing-review.md), while preparing metadata, privacy/support and build assets.
2. Finish password-protected native metadata/notes/thumbnails and safe source-preserving integration. Preserve current album/password boundaries. Build45 mounts encrypted models/drafts only for a fresh release library; legacy development data remains untouched.
3. Verify supported complete backup recovery, readable originals and album credentials without the original Keychain. Define excluded/unsupported cases honestly; a complete export must fail rather than silently omit content. Finish the pending owner readable-output and filename checks separately from build 41 notes acceptance.
4. Freeze a small candidate; complete install/update, lock/unlock, import/view/share/background, album, notes and recovery regressions on the release identity. Capture final screenshots from disposable samples on supported iPhone/iPad sizes. Review compatibility and any stored references under that identity.
5. Match the final source tag, license notices, privacy policy/manifest, Apple privacy answers, encryption determination, review instructions and listing to that exact archive. Upload/validate through the authorized Apple account only after gates are cleared. Select manual release when submitting; do not release automatically.

Shared albums, Trash, encrypted search, self-destruct lock, unlock-camera capture and a true independent alternative vault are deferred from first-release scope. Keep their Linear requirements; do not claim they are shipped. Existing presentation-only Guest Mode must be removed from the public candidate or retain unambiguous limited claims under review; it is not duress protection. The public candidate hides presentation-only Guest Mode. No legacy native storage migration is enabled by this document.

## Readiness gates

| Gate | Current evidence / outstanding work |
| --- | --- |
| Distribution rights — D2S-106/118 | GPL commercial use is permitted; upstream explicitly describes branded App Store forks. Exact platform/source-conveyance compliance review remains open. A lawyer or separate monetization permission is not a GPL prerequisite; see the clarified review packet. |
| Native security — D2S-105/116/143 | 279 unit/security tests pass. Actual encrypted release UI verifies password changes and cold relaunch without losing notes. Fresh release libraries encrypt metadata/notes/thumbnails; legacy Dev A01 and broader preview/key/rollback findings remain open. Final physical acceptance is pending. |
| Recovery — D2S-110/114/141 | Independent official age recovery passes for both legacy and actual encrypted-library fixtures, including seven exact payloads, notes/drafts, Unicode and nested passwords without phone/Keychain. Owner final readable-output/filename confirmation and provider behavior remain; older buffered sources above64MiB are explicitly blocked. No native in-app restore is claimed. |
| Identity — D2S-117/118 | Proposed store identity `com.d2sci.waglock`, display WagLock, initial marketing version 1.0. Opt-in [release configuration](../../config/AppStore.xcconfig) does not change Debug or register an App ID. Existing phone `com.d2sci.vaultito.dev` is preserved. |
| Privacy/support | Current English [policy](../../PRIVACY_POLICY.md), [support](support.md) and in-app links prepared; inherited policy preserved verbatim. Recheck against final release; select private developer/review contact and validate public URLs before upload. |
| Apple privacy/crypto | Privacy manifest exists; final accessed-API reasons, privacy-label answers, backup behavior and export classification need exact-binary review. No exemption flag has been assumed. See [compliance worksheet](compliance.md). |
| Listing/assets | [Draft listing/review instructions](store-listing.md) prepared. Actual release screenshots are being captured; age/content questionnaire, territory selection, ownership review of every icon, contact fields and account agreements remain. |
| Archive/source | Unsigned release archives verify packaging; a development-signed release-identity build uses the existing cached wildcard profile without registration. Distribution-signed validated archive, exact source tag/build guidance and final device/restore checks remain. No App Store Connect app record/upload/submission has been performed by this preparation. |

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

Still required before submission: owner physical acceptance of the separate encrypted app; final signed-distribution validation and matching source freeze; account-holder privacy/export/territory/contact and age/content declarations; distribution-compliance review; App Store record/upload and manual-release selection. No automatic iOS native restore or provider remote-upload completion is claimed. Country and private review-contact questions are pending. No registration, upload, submission or release has occurred.


### Final package and installed candidate

The final279-test regression has zero failures/skips;58Python tests, both recovery fixtures and both process-termination probes pass. Development-signed WagLock1.0(45) is installed on the owner phone under **com.d2sci.waglock**, alongside unchanged WagLock Dev. Remote launch was denied by the phone lock; [physical acceptance](device-acceptance-build45.md) is pending. The final unsigned verification archive succeeds at `/private/tmp/WagLock-1.0-build45-final.xcarchive`, with source build counter45 preserved. The package checker verifies identity, actual encrypted-mode activation, fullGPL/BSD notices, original source hashes and privacy reasons, and correctly rejects a legacy Dev bundle. [Machine-readable evidence](evidence/build-45/README.md). The archive is not distribution-signed/upload-ready. No export declaration was invented.
