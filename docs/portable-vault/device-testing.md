# WagLock development build and phone testing

Working brand: **WagLock** — *We Always Guard*. This is an early functional test build using the inherited storage format. Cryptomator compatibility, cold recovery, independent encrypted decoys and the security findings in [D2S-105](audits/D2S-105.md) remain outstanding. Use disposable sample media.

Build **22** adds [nested albums and biometric unlock](albums-and-biometrics.md). Open Photos → Albums for album/subalbum creation, import, verified moves and album security. Enable vault Face ID under Settings → Face ID Unlock using the current vault password. Face ID-only albums require explicit acknowledgement of device-bound loss risk. Existing main-library media is not automatically moved or re-encrypted.

Build **23** adds [authenticated stream framing and atomic output](stream-integrity.md) for new streamed media. It retains legacy readers and performs no automatic conversion. Keep independent originals; older builds cannot open new v2 streams. After updating, check an existing sample and import/open a new video or document, then background and reopen. Installation/launch does not establish media round-trip success.

Build **24** adds [credential/cache/storage hardening](credential-and-cache-hardening.md): failure-safe password changes, preservation of credentials when preferences are missing, opaque new ciphertext names, enforced free-space preflight and rejection of late cache results after clear/cancel. Ordinary legacy login leaves credentials unchanged. Setup or an explicit password change uses a new credential record that older builds cannot read; do not downgrade afterward. Before further storage changes, test existing/new samples, wrong/right passwords after a password change and relaunch, vault/album Face ID and background locking using disposable media. Hardware results remain separate from simulator tests. The isolated Cryptomator probe is not included in the phone app.

Build **25** adds [import lifecycle hardening](import-lifecycle.md) and a scoped older-iOS calculator cleanup workaround. The final signed build passed; 103 unit tests and one album UI workflow passed on iPhone 16 / iOS 18.4. The original installation attempt was blocked by the phone connection (CoreDeviceError 4016). Build 26, which includes these changes, subsequently installed and launched successfully on 2026-10-18; build 24 remains the last build with user-reported functional acceptance. Once connected, check Files/Photos import and cancellation on disposable media, especially cancellation or logout while an import is pending. The migration comparison tools are Mac-side research tools, not a new phone import/migration feature.

Build **30** adds [shared password options and a live local strength estimate](password-entry.md): main and current Guest Mode passwords accept the same 6–128-character policy, login offers Number pad/Full keyboard switching, and a shared preference remembers that choice for app/album login. Calculator display long-press → Use Password opens the shared login. Build 29 passed owner phone acceptance. Build 30 is signed, installed and launched on the same phone; owner acceptance is pending. Independent alternative-vault login remains unfinished.

Build **31** hides password quality feedback during all app/album unlock prompts. It remains on password creation/change screens. Owner confirmed build 30 on the phone.

## Separate installation and data boundary

- Home-screen display name: **WagLock Dev**, including localized InfoPlist.strings.
- App bundle ID: `com.d2sci.vaultito.dev`; tests use separate `.tests` / `.uitests` identifiers.
- Default Keychain service follows the installed app's bundle ID. WagLock does **not** automatically migrate credentials from `com.zeronetspace.unlimited-imports` or `com.wq.ZeroNet-Space`. It starts with a separate app container, database, preferences and encrypted media directory.
- No Keychain sharing entitlement is configured. Existing app data is not imported, reset or converted by this installation. Retain the existing app and its originals.
- Through build 26, the Xcode target/scheme, executable/product name and Swift module kept their inherited names. Build 27 renamed the product/executable to Vaultito. Build 28 renames the product, source/test folders, project, scheme and Swift module to `WagLock` (`WagLock.app`). The app's installed identity and display name are separate from these internal names.
- The project uses Michael Donnelly's development team (`Z3B45KM866`), discovered from the installed public signing certificate. Other builders should select their own team and unique bundle ID. Keychain service follows their resulting app identity.

Photo/file/gallery/audio imports no longer depend on the old 75-item cap or a purchase. Settings shows development limitations instead of purchase/restore controls and no longer requests StoreKit products on entry. Guest Mode is available for inspection but still only filters owner content. Build 26 also removes inherited audio-sharing/icon gates, VIP state, purchase prompts and StoreKit configuration. All alternate icons and audio export are available to authenticated owners without entitlements. No purchase or restore flow remains.

## Build, install and launch

Open `WagLock.xcodeproj`, select scheme **WagLock**, and use Signing & Capabilities to confirm your Apple development team and automatic signing. Pair the iPhone, enable Developer Mode and keep it unlocked while Xcode prepares development services. Choose the phone and Run. Minimum app deployment target is iOS 17.6.

Equivalent signed compile:

```sh
xcodebuild -project WagLock.xcodeproj -scheme WagLock \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/vaultito-device -allowProvisioningUpdates build
```

For command-line installation, replace `YOUR_DEVICE_ID` with the paired identifier reported by `xcrun devicectl list devices`:

```sh
xcrun devicectl device install app --device YOUR_DEVICE_ID \
  '/tmp/vaultito-device/Build/Products/Debug-iphoneos/零网络空间.app'
xcrun devicectl device process launch --device YOUR_DEVICE_ID com.d2sci.vaultito.dev
```

If the phone is locked, unlock it and retry. If Xcode reports no account/profile, sign into the correct account in Xcode and select its team; an unsigned compile cannot be installed on the phone. No TestFlight upload or release distribution is part of this workflow.

## First acceptance pass

1. Confirm a separate **WagLock Dev** app appears and the existing app remains installed.
2. Open it, confirm the WagLock name/tagline and development notice, then create a new test password. Record the password separately; the current build does not provide proven portable recovery.
3. Import disposable photos, a video and a document. Confirm browsing, preview/playback and counts. Test a batch beyond 75 items; watch free disk space. The Photos path still recompresses images, so do not infer original-byte or metadata fidelity.
4. Background/reopen with immediate auto-lock, enter a wrong password, then unlock correctly. Check the app-switcher cover and repeat during playback.
5. Export sample photo/video/document files and compare them with the imported content. Decrypted sharing intentionally creates plaintext copies outside the vault.
6. Change the test password; confirm the old password is rejected, the new one unlocks and existing samples still open after relaunch.
7. Optionally inspect Guest Mode: it must hide owner content but is not an independently keyed decoy. Do not treat this as forensic protection.

Record device model/OS, build version, actions, failures and results in BUILD_ERRORS_SUMMARY.md. Installation/launch alone does not pass these manual acceptance steps or close D2S-105.

For build 22, also create a password-protected album and nested subalbum, import disposable media, lock the parent and confirm both need unlocking. Test the wrong album password, a correct unlock, a security-policy change, a verified main-library move, and background/reopen. Enable vault Face ID, lock/unlock it, then test an album using password-or-Face-ID. Cancel biometric prompts and confirm access is not granted. Test Face ID-only only with disposable media and keep independent originals; changing enrollment/passcode can destroy access. Never change your phone's biometric enrollment merely to test the app if it would disrupt other important Keychain data.

## Automated checks

`WagLockDevelopmentTests` checks imports beyond the inherited cap with an 80-item in-memory library, separate credential namespaces and bundle-derived Keychain identity. `WagLockSmokeUITests` checks the fresh-install name/tagline/limitations and captures a screenshot. Run the smoke test on a fresh simulator installation, before creating its password. Existing encryption/audio/calculator tests remain relevant; these tests are not complete security coverage.

## Preparation results — 2026-10-17

The development-signed generic iOS build passed with the configured team. On iPhone 17 / iOS 26.5 simulator, 40 unit tests (28 XCTest + 12 Swift Testing) and the fresh-install UI smoke test passed. Test command:

```sh
xcodebuild test -project ZeroNet-Space.xcodeproj -scheme ZeroNet-Space \
  -destination 'platform=iOS Simulator,id=42099BD8-B583-41F9-BF53-A4CCEB71872E' \
  -derivedDataPath /private/tmp/vaultito-tests \
  -resultBundlePath /private/tmp/vaultito-tests.xcresult \
  -only-testing:ZeroNet-SpaceTests \
  -only-testing:ZeroNet-SpaceUITests/VaultitoSmokeUITests \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

Physical iPhone 17 Pro was paired, with Developer Mode enabled and iOS 27.0.1. The initial locked-device installation attempt failed. After the user unlocked it, `devicectl device install app` successfully installed `com.d2sci.vaultito.dev` and `devicectl device process launch` successfully launched it in the foreground (both exit 0). A standalone Mac signature check reported an untrusted chain, but the phone accepted the signed app. The manual media/lock/password-change checklist remains outstanding; installation/launch alone does not close D2S-105. See BUILD_ERRORS_SUMMARY.md for logs and exact limitations.

Build 22 subsequently passed 51 unit tests and one album workflow UI test, installed/launched on the phone, and the user reported the app working as expected. This is functional feedback, not evidence that every hardware biometric or recovery case was exercised. Build 23 passed 65 unit tests and a signed generic-device build; see the root BUILD_ERRORS_SUMMARY.md for installation/launch evidence and remaining device checks.

Build 24 passed 91 unit tests and a signed generic-device build. After reconnecting/unlocking the phone, installation and foreground launch both succeeded. The user explicitly reported the requested disposable-media/password-change/relaunch/Face-ID/background pass as **passed**, with P2 follow-ups for video thumbnail ratios and numeric-first login prompts. This does not cover enrollment/lockout, cold recovery or independent security review. The first simulator UI runner could not launch; the isolated retry result is recorded in BUILD_ERRORS_SUMMARY.md. No biometric enrollment, live password change, root-media conversion or vault reset was performed by the agent on the phone.

Build 26 removes all inherited VIP checks and purchase code. All 103 unit tests passed on the disposable iOS 18.4 simulator, along with the album workflow and alternate-icon selection/restoration UI checks. The icon test explicitly acknowledges the iOS confirmation; its first attempt timed out before dismissal. The signed device build passed. The original installation attempt was blocked by device connectivity error 4016; on 2026-10-18, installation and foreground launch succeeded and the installed-app query confirmed version 1.3.8/build 26. Manual device acceptance of builds 25/26 is still outstanding. See the root build summary for evidence.

Build 27 switches the beta to English-only resources and date presentation, removes inherited app diagnostic prints and uses the Latin `Vaultito` executable/product. Existing bundle, Keychain, data paths and schema remain unchanged; install as an update, never uninstall to work around a launch/test issue. For build 27+ use `Vaultito.app` instead of the historical Chinese-named product in the commands above. See [beta readiness](beta-readiness.md) for remaining audit, source-comment, artwork and distribution gates.

The build 27 update installed and launched on the paired iPhone on 2026-10-18; installed-app metadata confirms 1.3.8/build 27. The initial clean run passed 103 unit tests and three UI workflows; the final date-presentation follow-up passed 103 unit tests plus English navigation under Chinese device-language settings. Existing-media readability after the product rename remains a manual device check.


Build 28 adopts **WagLock — All wag. No tell.** Source/project/scheme/module names are WagLock; use `WagLock.xcodeproj`, scheme `WagLock`, and product `WagLock.app`. The installed app remains `com.d2sci.vaultito.dev` and displays **WagLock Dev**. Do not uninstall or rename Keychain accounts. See [branding and thumbnail compatibility](waglock-branding-and-thumbnails.md) for legacy-database and proportional-video checks.


Build 29 adds the [authenticated library boundary](authenticated-library-boundary.md), stale-authentication/biometric-commit rejection and the Face ID disclosure warning. All 146 unit tests and six UI workflows passed; the signed candidate installed/launched and reports version 1.3.8/build 29. Verify existing disposable samples/albums, lock/relaunch and hardware Face ID before advancing live storage changes. This prepares independent vaults but does not enable the alternative passcode or perform metadata/media conversion. The build also preserves the newer Blue Guardian / We Always Guard branding selected in the branding conversation.

## Build 32 — exports and background locking

Owner accepted build 31. Build 32 is signed and installed; simulator tests passed. Remote launch was denied because the phone was locked (CoreDevice 10002 / Locked); the owner can unlock and open the installed app normally. With disposable media, open a photo/video/file and share it, cancel the share sheet, then share again to a destination of your choice. Confirm the received sample opens. Start another share, background or lock the phone, return and unlock, and confirm the old share is dismissed and a fresh share works. Existing media and password/Face ID unlock should still work. Report any failure without sending passwords or private media. Local cancellation cannot retract a copy already handed to another app. Hardware acceptance is pending.

**Build 32 owner result (2026-10-22): passed** the requested disposable-media share/cancel/received-sample/background-lock/fresh-share and password/Face ID checks. This supersedes the pending functional acceptance above; broader security and recovery gates remain open.

## Build 33 — common document preview lifecycle

Signed build installed on the owner phone. Full units (169) and both selected simulator UI regressions passed. Using disposable PDF and text/Markdown samples, open each from Files or Media, background/lock while viewing, then return/unlock and reopen it; verify the correct content and normal password/Face ID. If a preview offers Retry after unlocking, confirm it opens normally. Also close/reopen a preview and check sharing still works. This is a common-format lifecycle change; generic QuickLook and other remaining audit paths are not claimed fixed. Owner physical result pending.

**Build 33 owner result: FAILED (2026-10-22).** PDF background → foreground showed Load Failed and terminated; second launch returned normally to login. Phone crash stacks confirm stale SwiftData metadata access during sheet dismissal. Build 34 correction and validation are tracked in [document preview boundary](document-preview-boundary.md); build 33 must not be marked accepted.

## Build 34 — repeat the failed PDF background flow

Build 34 installed successfully over the same app identity, preserving credentials and library data. Complete units passed 171 tests, including real PDF and Files-pager render/revoke/resume/logout with fixture-library closure. Please repeat the original phone failure path with a disposable PDF: open, background or lock the phone, return, unlock if requested and reopen the PDF. Repeat a second time. Expected: no Load Failed warning merely from suspension and no termination; the document opens normally after authorization. Phone acceptance pending. See [confirmed crash cause and correction](document-preview-boundary.md).

**Build 34 owner phone result (2026-10-22): passed.** Owner repeated the requested two PDF open/background-or-lock/foreground/unlock/reopen cycles and reported success, without the prior Load Failed/termination. This completes the functional retest, not the broader audit.

## Build 35 — Figma implementation and photo preview teardown

First implementation pass of [the linked Figma design](figma-ui-implementation.md), including System/Light/Dark appearance and reorganized Settings. This is not complete parity with all 70 design states. A simulator share/background check exposed the photo counterpart of the build 34 PDF teardown problem. Immutable photo presentation data and originating-session checks now prevent a dismissed viewer from faulting a released SwiftData record. The new real-render teardown regression passes as part of 172 unit/security tests.

Phone acceptance: use disposable media to check normal password and Face ID unlock; keyboard switching; Settings → Appearance (System/Light/Dark); existing photos/albums/files; and sharing a photo, backgrounding/locking, returning/unlocking and sharing again. Recheck the PDF background/resume flow. Do not delete or reset the app. Installation and acceptance results follow when available.

**Build 35 installed (2026-10-22).** Signed device build and installation succeeded over the same app identity. Post-fix units: 172 passed. Final repeated UI checks: six passed (two each for appearance/navigation, photo import/share/background and original-license access). Phone acceptance remains pending; installation alone is not acceptance. Logs: `/private/tmp/waglock-build35-device-final.log`, `/private/tmp/waglock-build35-install.log`; result bundles are linked from the implementation record.

Build 35 launch request was refused because the phone is locked. Installation succeeded; the owner can unlock the phone and open WagLock Dev normally. No phone unlock or runtime acceptance is claimed.

**Build 35 owner result:** passed, with a Notes background layout defect: the color did not fill the screen. Build 36 expands the Notes container to the full available area and extends its background through the safe areas. Notes content and persistence are unchanged.

**Build 36 installed:** signed compilation, existing appearance/navigation UI check and installation succeeded. Empty Notes screenshots were visually checked in both Light and Dark; the background covers the full screen. Installation log: `/private/tmp/waglock-build36-install.log`. Owner retest of this visual correction is pending.

## Build 37 — completed current-feature UI

Completes the remaining Figma layouts and native runtime counterparts. See the [70-state implementation map](../../design/ui-refinement/IMPLEMENTATION-COVERAGE.md) and [validation](figma-ui-implementation.md). Complete units: 173 passed. Corrected final UI workflows and generated-video import/player passed; signed device compilation passed. Physical hardware acceptance remains separate from the passing simulator checks. Existing app identity and encrypted storage are preserved.
