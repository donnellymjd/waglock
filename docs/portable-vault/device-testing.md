> **October26 build61:** explicit Use entered password action for setup/change/alternative setup; actual Release regression passes and signed61 installed over60, retaining Dev44. [Evidence](../release/evidence/build-61/README.md). Both vaults preserved; owner1Password acceptance is pending.

> **October25 build60:** forgotten-password help and explicit erase/start-over are verified by342 unit/security tests and the full actual-release simulator workflow. [Evidence and deliberate hardware test](../release/evidence/build-60/README.md). Signed candidate60 installed successfully over59; installed inventory confirms60 and retained Dev44. Owner UAT is pending. Nothing has been erased on the phone. Earlier build notes below are historical.

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

Build 37 installation succeeded on the owner phone over the same app identity, preserving data. Installation is not physical acceptance.

## Build 38 — note save lifecycle

Continues D2S-116 after the UI push. Canceled autosaves cannot restore cleared drafts or write into a revoked owner session. Explicit Save clears the draft after database success and stays open on save failure. Presentation-time draft reload fixes the stale Back/reopen snapshot exposed by the integration check. See [note-write boundary](note-write-boundary.md).

Final combined result: 181 unit/security tests and one real editor workflow passed (`/private/tmp/waglock-notes-boundary-corrected.xcresult`). The first editor run failed on Back/reopen and was corrected, not waived. Signed build passed (`/private/tmp/waglock-build38-device-final.log`). Phone installation/acceptance are recorded separately.

Physical check uses disposable notes: Save a new note, reopen New and confirm its fields are empty; type another draft, use Back, reopen New and confirm the latest text; save, background/lock, unlock and reopen the saved note. Verify normal password/Face ID. Do not send passwords or private note text. Persisted notes remain plaintext SwiftData; this is not D2S-143 encrypted notes.

**Build 38 installed (2026-10-22):** installation succeeded on the owner phone with the same bundle identity and without uninstalling/resetting the library (`/private/tmp/waglock-build38-install.log`). Physical acceptance is pending.

## Build 39 — encrypted backup, 2026-10-22

Signed build **WagLock Dev 1.3.8 (39)** installed without uninstall/reset, preserving `com.d2sci.vaultito.dev` and existing credentials/data. Filtered device inventory confirms version39. Automatic launch failed only because the iPhone was locked (CoreDeviceError10002 / FBSOpenApplicationErrorDomain7). Owner can unlock and launch normally; acceptance is pending. No development tool read/exported owner media or passwords.

Automated evidence:

- 206 unit/security tests (95 XCTest +111 Swift Testing), `/private/tmp/waglock-backup-full-regression.xcresult`.
- 41 Python tool tests, `/private/tmp/waglock-backup-python-final.log`.
- Isolated iPhone16 / iOS18.4 UI: password backup creation, native Files dismissal, recipient backup creation, local Files Save callback and original note preservation, `/private/tmp/waglock-backup-ui-save.xcresult`. The actual provider-copied encrypted file independently decrypted with official age and contained the expected disposable note. Fresh Files needed initialization; Xcode27/iOS18 remote AX reported stale toolbar frames, so the fixture uses a supported dismiss gesture and visible system Save coordinates. This is not a cloud upload test.
- Reproducible official age1.3.2 cold recovery and two parent-only credential rejections, plus tamper/truncation rejection: `python3 tools/check_backup_interop.py --age /path/to/age`. See [public evidence](backup-validation-results.json) and [fixture provenance](../../tools/fixtures/age-backup/README.md).
- Signed device build `/private/tmp/waglock-build39-device.log`; install `/private/tmp/waglock-build39-install.log`; inventory `/private/tmp/waglock-build39-inventory.log`.

Owner check requested: with disposable content, Settings → Encrypted backup → Password → create → Save to Files → chosen cloud provider; confirm availability on another device and normal password/Face ID unlock. Separate real biometric-only copy acceptance, large-library/phone memory-pressure and broad provider/platform checks remain outstanding. Do not send passwords/identities/private media. [Recovery procedure and limits](backup-recovery.md) include the explicit 64MiB buffered-legacy-file export blocker. This does not change native storage, approve Cryptomator adoption or clear distribution/security-audit gates.

### Build 39 owner recovery rejection — 2026-10-22

Owner reports official age `incorrect passphrase` while recovering the phone's exported backup, and explicitly confirms using the backup/export password. Treat end-to-end phone acceptance as blocked, not passed or presumed user error. The installed official age1.3.2 still recovers the public native fixture and rejects wrong parent credentials/tampering/truncation. No private backup/password was accessed. Keep original library and backup; compare a fresh export under a distinct filename/new destination before relying on the feature. Root cause remains unresolved. D2S-114 has the blocker recorded; improved error guidance does not fix or certify this backup.

Additional diagnostic: copied only the finished password-encrypted output of the actual password-entry UI on the disposable QA simulator, before Files handoff. Official age1.3.2 and the recovery helper opened it with the known public test password and verified seven disposable note bodies. This does not reproduce the owner's failure or validate their file. Repeated full Files-save UI checks reached the system's expected “Replace Existing Items?” alert for the earlier synthetic backup, which the fresh-only fixture does not handle; no full new UI pass is claimed. Original provider-copy pass remains historical evidence.

## Build 40 — readable recovery and backup filenames, 2026-10-22

Owner confirmed that a fresh build39 export opens on the Mac; the earlier copy's password rejection remains unexplained. Owner screenshot exposed UUID-only extracted filenames without extensions. The updated helper supports those existing archives and now publishes a readable **Library** after all requested domains verify. It restores usable original names/extensions and nested album folders, writes notes/drafts as Markdown, adds thumbnail extensions and records archive-to-output paths in report version2. Original metadata/manifests remain. Unsafe/duplicate/long names get safe unique alternatives; `--raw-layout` preserves the prior file layout. Default console output points to the folder to open; `--json` prints the full report. No actual user files were read or renamed by development tools.

The app's ready screen now has an editable filename with a clear button. The required .tar.age suffix is added once; only finished ciphertext is renamed exclusively inside the owned job. Invalid path names and occupied destinations fail without replacing files. Source library/keys/native formats are unchanged.

Validation: **207 app unit/security tests** (96 XCTest+111 Swift Testing), `/private/tmp/waglock-readable-unit.xcresult`; **57 Python tests**, `/private/tmp/waglock-readable-python-tests.log`; official age1.3.2 independent recovery verifies seven payload hashes, metadata and two protected domains in the readable layout, plus parent-only rejection/tamper/truncation, `/private/tmp/waglock-readable-interop-final.json`. The final UI test clears/edits the exact filename, checks Save disabled for an empty name, cancels Files, creates the other encryption mode and saves with the exact chosen filename, `/private/tmp/waglock-readable-ui-final.xcresult`. Actual system-copied synthetic output independently recovers nine expected readable note files, `/private/tmp/waglock-readable-system-copy-final.json`. The first automation attempt deleted from the text cursor and left part of the old name; the final explicit clear-button flow asserts exact text and exact provider filename. This was a test-input issue, not password corruption.

Signed build40 passed, `/private/tmp/waglock-build40-device-final.log`; installed without reset/uninstall, `/private/tmp/waglock-build40-install-final.log`; device inventory confirms1.3.8(40). Owner check requested: clear/edit/save a backup filename and rerun recovery into a new output folder, then open a few real sample photos/videos under Library. Filename/readable-media acceptance is pending; provider-specific cloud completion, Windows/Linux runtime/large-library checks and broader security/distribution gates remain separate.


## Build 41 prepared — draft conflict preservation

Signed WagLock Dev 1.3.8 (41) compiles with unchanged `com.d2sci.vaultito.dev`, team and Keychain namespaces. Its production change preserves conflicting legacy/Keychain drafts and verifies read-back before removing only an identical duplicate; the app source link now points to the WagLock GitHub repo. Typed draft/model staging remains unused and performs no live metadata migration. Full units: 247 passed; simulator note Save/Back regression: passed. Product Info.plist confirms build 41 and the existing identity. Physical installation is pending because device discovery reports the iPhone disconnected. Do not uninstall/reset to work around connectivity. [Draft behavior and limits](draft-preservation.md).


**Build 41 installed:** after the owner reconnected/unlocked the phone, installation and foreground launch succeeded without uninstall/reset. Filtered device app inventory confirms WagLock Dev 1.3.8/build 41, `com.d2sci.vaultito.dev`. No media/passwords were read or exported. Physical note Save/Back, existing media and unlock acceptance is pending. Logs: `/private/tmp/waglock-build41-install.log`, `/private/tmp/waglock-build41-launch.log`, `/private/tmp/waglock-build41-app-info.log`. The preceding disconnected status is historical preparation evidence.

**Build 41 owner acceptance:** owner replied “passed” to disposable note edit → Back → reopen → Done/save, existing sample access, and password/Face ID unlock after backgrounding. This validates the requested phone workflows, not legacy-conflict reproduction, complete backup recovery or live metadata migration.


## Build 43 — session-bound library writes (2026-10-23)

Installed and launched as an update to the same development identity; installed metadata confirms WagLock Dev 1.3.8 (43). No uninstall, reset or native metadata conversion. Full regression passed 260 tests plus three application UI workflows. See [write-boundary changes and limits](library-write-boundary.md).

Using disposable samples, import/open a photo and video, edit a note and confirm Done/Back/reopen behavior, create a nested password album and relock/reopen it, then background/lock and check password/Face ID and fresh sharing. Check edits persist after app relaunch. Separately finish the outstanding backup check: choose an export filename, recover into a new Mac folder with the correct outer/album credentials and open a few readable recovered files. Do not send passwords or private content. Owner acceptance remains pending; successful phone checks will not alone resolve native metadata encryption, recovery coverage or first-submission gates.


## Build 44 — standard native video viewer (2026-10-23)

Owner requested a standard interface in place of the Figma card layout. The viewer now uses full-screen aspect-fit AVKit playback on black, native transport controls, navigation-bar Done/Share and an Info/Delete menu. Existing media/credentials and installed identity are unchanged. Complete unit regression passed 260 tests; imported-video UI verifies the full-size player and normal close/share controls.

Phone acceptance: open disposable landscape and portrait videos, tap to show controls, play/pause/scrub and rotate the phone. Check Info and share/cancel. Background/lock, return/unlock and reopen a video; sound should stop while backgrounded and a fresh open should work normally. Do not delete non-disposable content. Owner acceptance remains pending.

Build44 installation succeeded and the installed-app query confirms 1.3.8 (44). Remote launch was denied because the phone is locked; unlock/open WagLock normally. The additional tap-to-show native Play/Pause/Replay UI check passed.


**Owner follow-up (2026-10-23):** “otherwise everything else works.” Record the normal application checks associated with build43 as passed, with the video-viewer design preference addressed by build44. This does not establish acceptance of the revised build44 viewer or independently confirm the separate complete Mac backup-recovery check. Build44 viewer acceptance remains pending.

## Build51 — security-hardening installation, October24

Installed the verified development-signed **WagLock1.0(51)** update under `com.d2sci.waglock`, from source commit `cd739e8`. Filtered installed-app metadata confirms name/version/build. No uninstall, reset, library migration, media read/export or credential inspection was performed. WagLock Dev and its separate library remain untouched. The phone reconnected after the owner's “ready” response; remote launch then failed because the phone had locked. Installation is successful; launch and functional acceptance are not established by this result. Open WagLock manually.

Evidence: `/private/tmp/waglock-build51-install.log`, `/private/tmp/waglock-build51-installed.json`, `/private/tmp/waglock-build51-launch.log`, `/private/tmp/waglock-build51-app-info.log`. Final package verification: `/private/tmp/waglock-build51-final-phone-verification.json`;298 unit/security tests and recorded release UI regressions pass. See [launch triage](security-launch-triage.md) for scope and residual findings.

Owner check requested with disposable samples: main/album password changes and relaunch preserve media; an unfinished note survives background locking and resumes; Face ID success/cancellation and immediate background locking work; screen recording started outside WagLock blocks its content until capture stops. Do not send passwords/private content. Native wrappers are strengthened on new setup or explicit password/protection changes; existing reads do not silently convert. Guest Mode is not enabled in51 and remains a required independent-vault integration for1.0. Physical acceptance remains pending. No submission/upload is authorized by this installation.

**Build51 owner acceptance — October24:** owner replied “passed” to all four requested disposable-sample checks: main/album password changes with retained media after relaunch; unfinished-note background/unlock/resume; Face ID success/cancellation and immediate background locking; and screen recording started from Home blocking WagLock until capture stops. This supersedes pending acceptance above. No independent new build51 backup-recovery run, direct AirPlay test or in-app capture-transition check is inferred. Guest Mode is still not enabled in51.


## October24 — final build53 acceptance and handoff

The owner passed the final build53 phone checklist: both existing passcodes and assigned Face ID open the expected vault/samples; disposable video/PDF background/resume has no crash, unexpected playback or preview; recording started through Control Center while unlocked blocks viewing until stopped and then requires unlock. Build52 populated-vault persistence and selected-only independent backup recovery acceptance remains recorded. Both vaults and the separate WagLock Dev app were preserved.

Build53 refuses old fast owner/guest verifier slots, native ZNSC v1 reads and native .encrypted imports in the public encrypted release while preserving explicit Dev/recovery readers and modern credentials. No migration/reset/format conversion occurs. Password inputs clear on background/disappearance; logged-out password changes fail closed. Generic media results must still belong to the active originating context after awaits, and late owned plaintext is removed. A deterministic paused video completion/logout regression verifies this boundary.

Verification:314 unit/security tests (186 XCTest +128 Swift Testing),57 focused credential/import/stream tests,7 final media-lifecycle tests,2 actual-release regression UI workflows, both native iPhone/iPad screenshot workflows and16 Python backup-tool tests pass. Official age1.3.2 independently recovers both checked-in public fixture sets; actual encrypted-library MOV/PDF/PNG/WAV payloads, notes/drafts/Unicode, nested passwords and tamper/truncation rejection pass without phone/Keychain. Full suite: `/private/tmp/waglock-build53-full.xcresult`; release UI: `/private/tmp/waglock-build53-release-regressions.xcresult`. An initial lifecycle-test compile failure attempted an unsupported Swift extension override; the corrected injectable loader seam and final runs supersede it.

D2S-158/159/161/164 launch mitigations are Done, bringing completed report findings to12 of13; D2S-115 independent Guest Mode remains Done. D2S-162 stays open for ciphertext-to-record identity binding: a filesystem writer may substitute valid same-vault ciphertext. v2 authenticates framing/order/length/end, not metadata-entry identity. Whole database rollback, legacy Dev metadata, complete memory zeroization and direct AirPlay hardware validation remain limitations. No screenshot/external-camera prevention, secure physical erasure, forensic deniability or independent audit certification is claimed. D2S-105 remains open for broader audit work.

The final development-signed build53 archive/package/signature checks pass. Eight native unedited public-fixture screenshots and copy-ready store metadata/review instructions are prepared. App Store export fails exit70: missing App Store distribution provisioning profile for com.d2sci.waglock. Only a development identity is available; no App Store Connect API credential is configured. Account distribution signing, source/platform distribution review and privacy/encryption/territory/publisher declarations remain external gates. No automatic provisioning update, upload or submission occurred. See [current handoff](../release/app-store/README.md).


## October24 — security candidate55 installed

Final signed package1.0(55), com.d2sci.waglock, installed successfully over WagLock after owner confirmed ready. Both vaults and the separate Dev app are preserved.317 unit/security tests and both final actual-release UI flows pass. Owner requested checks: both existing passcodes/samples, primary Face ID assignment followed by hidden app-unlock Face ID controls/status in secondary, neutral secondary text, guest password change/relaunch/separation, biometric cancellation and note/PDF background lifecycle. Physical acceptance pending; no passwords/private files requested. Safari form-entry task canceled by owner, no forms changed. [Review and evidence](security-review-build55.md). No upload or submission.


## October25 — build57 installed, owner UAT pending

Signed WagLock1.0(57), com.d2sci.waglock, installed successfully over the public release app via devicectl; no reset/uninstall/library migration. The separate WagLock Dev identity remains unchanged. The signed archive is /private/tmp/WagLock-1.0-build57-security.xcarchive. Package/signature/encrypted-library checks pass. Owner acceptance of build53 and earlier does not cover this candidate.

UAT with disposable samples: unlock both existing libraries by passcode; confirm distinct photos/notes/protected albums persist after relaunch; test album password success/failure and changing primary/album passwords; test Face ID success/cancel from each eligible assignment and hidden unavailable biometric settings in the secondary vault; review secondary Settings/backup/errors for ordinary neutral wording; test backgrounded unfinished note/PDF/video, active recording blocking, share/cancel, and separate readable age backups recovered on Mac. A previously older primary wrapper can require one password unlock before Face ID resumes. Do not send passwords or private content.


## October25 — build58 Face ID settings follow-up

Signed1.0(58) installed successfully over WagLock, preserving both vaults and the biometric grant. Corrects missing own-vault Face ID settings when an older authenticated grant lacked or disagreed with its newer ownership marker. Full334 unit/security tests pass; the regression fails before correction and passes after. No vault reset/re-enrollment needed. Owner check: unlock through Face ID after update, open Settings → Security & access → Face ID and tap Disable Face ID, then lock and confirm normal passcode entry still opens the same library. The control remains hidden from a different vault's password session.


## October25 — AutoFill preview59 installed

After owner Google sign-in and Squarespace DNS changes, verified Firebase active hostname/ownership/certificate, strict custom-origin HTTPS and Apple's exact public association CDN record. Installed signed opt-in WagLock1.0(59) over the existing public app without reset/uninstall; device inventory confirms Dev44 remains. Exact source tag autofill-preview-build59, archive /private/tmp/WagLock-1.0-build59-autofill.xcarchive. Provider UAT pending: save https://waglock.d2sci.co as the disposable credential's website and verify suggestion/fill, correct library, cancellation, keyboard/visibility and lock. Test two disposable entries for provider-side disclosure; no guarantee the provider hides the other entry. Default AppStore association activation waits for acceptance.
