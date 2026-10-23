# Figma UI implementation — build 35

Source: [the complete WagLock design](https://www.figma.com/design/sOaFXyvdlCstDTQ4Zfn7xz?node-id=40-2436), created in the other project chat. See the [70-state inventory](../../design/ui-refinement/SCREEN-INVENTORY.md). Implementation started on 2026-10-22; the existence of 140 design frames does not mean every frame is implemented or individually tested.

## Implemented first pass

- Exact adaptive Figma brand/background/surface/text/border colors, native SF typography and SF Symbols. Shared primary buttons, navigation rows, information cards, search fields and empty-state components.
- Unlock screen with the existing Blue Guardian artwork, password help and keyboard selector above password entry. Password strength remains absent at login.
- Vault creation layout and its no-reset/originals warning, retaining setup validation and strength feedback.
- Photos: live count, search, album navigation card, rounded clean thumbnails and six-point grid gaps. Grid columns and sorting use the existing saved preferences; accessible tile labels retain filenames.
- Media: full-width Videos/Audio selector and subtitle; video/audio name search and common surfaces. Video thumbnails retain the aspect-fitting renderer from D2S-126.
- Files: live count, search, common surfaces and empty state. The immutable preview/pager selection from build 34 is retained.
- Notes: common library appearance and subtitle, retaining the existing editor and persistence behavior. This work does not implement encrypted Markdown notes (D2S-143).
- Import: three source cards, originals/cloud-file explanations and existing native iOS pickers/progress handling.
- Settings: five main navigation cards, lock action and System/Light/Dark appearance persisted independently of vault credentials. Security/access and storage controls remain available in drilldowns; About opens the existing native modal with source/license/privacy destinations.
- Album browser, protection forms, Face ID, Guest Mode, app icons and password-change forms use the shared appearance without changing authentication actions, acknowledgement requirements or ancestor protection.
- Export selection explains that sharing creates unencrypted copies; the original per-session export/share lifecycle is unchanged.

## Deliberate native adaptations

Keep real navigation/tab bars, segmented controls, Forms, alerts, confirmations, Face ID prompts, system pickers and share sheets. Figma's status bars, home indicators, outline glyph fallbacks and Inter font are review assets, not application assets. Screen titles and cancellation controls follow native navigation placement. Storage values, media, dates and names come from live application data; no design sample media is installed in a user's vault.

## Completed UI implementation — build 37

The remaining implementation now covers date grouping; note, file and audio cards; note editing; the photo viewer and information sheet; audio/video player layouts; security, auto-lock, Guest Mode, storage and library layout drilldowns; calculator styling; album media grids; progress/password/error states; and privacy/license screens. New albums are created from the always-visible toolbar and appear first. Selected-photo export passes the selection to the existing export service.

See the [complete 70-state runtime mapping and explicit native adaptations](../../design/ui-refinement/IMPLEMENTATION-COVERAGE.md). This closes the UI implementation pass for current functionality, not the feature/security roadmap. The prototype Favorite action uses the working Info destination; persistent photo favorites remain in D2S-112. Native confirmations, iOS pickers and share-ready presentation use the real system flows. The prototype's mock/example links and data are not production features. Individual screen screenshots do not establish exhaustive hardware/accessibility acceptance.

## Security boundary

No storage format, key lifecycle, migration, schema, installed bundle identity or library mounting changes. The photo teardown correction extends the immutable preview/session boundary already used for documents in build 34. Guest Mode still only hides content; alternative-vault isolation, portable recovery and encrypted Markdown notes remain separate work. Keep D2S-105/D2S-116 open. Physical-device acceptance and comprehensive screen/accessibility coverage remain separate from simulator test success.

## Validation

- Initial unit/security regression: 60 XCTest tests plus 111 Swift Testing tests passed. After the photo-preview fix, the complete run passed 61 XCTest tests plus 111 Swift Testing tests (172 total).
- Initial UI regression: appearance persistence/core destinations, password keyboard switching, Face ID consent cancellation and photo import/share/background revocation passed (four tests).
- Build 35: signed iOS device build succeeded. Extended UI found a real photo-preview teardown crash before phone installation. The simulator report captured `MediaItem.fileName.getter` from `PhotoDetailView.bottomBar(for:)` after the library closed. Photo presentation now captures immutable entries before presentation, renders from snapshots, and gates source actions by the originating session. `MediaLoaderService` accepts immutable read metadata without changing its cache-generation checks. The new `PhotoPreviewRenderingTests` releases its disposable backing store after logout and forces another render. The repeat UI result and physical-device acceptance are recorded below when available.

Local evidence: `/private/tmp/waglock-design-units-1.xcresult`, `/private/tmp/waglock-design-ui-1.xcresult`, `/private/tmp/waglock-design-ui-2.xcresult`, `/private/tmp/waglock-build35-device.log`. The final crash-fix unit evidence is `/private/tmp/waglock-design-photo-units.xcresult`; repeat UI evidence is `/private/tmp/waglock-design-ui-3.xcresult`. Result bundles are temporary local diagnostics, not repository dependencies.

### Final build 35 candidate results

- Complete post-fix unit/security run: **172 passed** (61 XCTest + 111 Swift Testing).
- Final UI run: **6 passed** — appearance/core navigation, real photo import/share/cancel/background/reopen and original-notice access, each repeated twice. Earlier keyboard, Face ID consent, Guest Mode and owner-library remount checks also passed. The preceding extended run's photo crash and obsolete About test selector were corrected; that failed run is not presented as passing.
- Final signed device compilation passed. Installed build 35 over the existing `com.d2sci.vaultito.dev` app successfully; no uninstall/reset or storage conversion. Owner phone acceptance remains pending.
- Final source whitespace check passed. [Native implementation screenshots](../../design/ui-refinement/implementation/README.md) contain only disposable simulator fixtures.

Build 35 launch request was refused because the phone is locked. Installation succeeded; the owner can unlock the phone and open WagLock Dev normally. No phone unlock or runtime acceptance is claimed.

### Build 36 — Notes background correction

Owner accepted build 35 with one visual defect: Notes background did not cover the screen. The Notes container now fills its available width and height, with the adaptive background extending through safe areas. The existing appearance/navigation UI check passed, and the captured empty Notes screen was visually verified in Light and Dark. Signed device compilation passed. Evidence: `/private/tmp/waglock-build36-ui.xcresult`, `/private/tmp/waglock-build36-device.log`; screenshots: `design/ui-refinement/implementation/build36-notes-{light,dark}.png`. No note content, persistence or authentication changes.

### Completed UI validation — build 37

- Final complete unit/security run: **173 passed** (62 XCTest + 111 Swift Testing), including hosted photo and video teardown after the backing store is released. The real audio encryption/decryption round trip includes Light/Dark player renders.
- Final corrected UI run: nested album/password/ancestor locking; photo import/share/cancel/background/reopen; generated-video import/player; and the remaining-screen walkthrough in both appearances all passed. Earlier Face ID consent, keyboard switching, Guest Mode credentials, appearance persistence and original-license access checks passed. An unreachable album footer and ambiguous modal close selector were corrected before the final run.
- Signed iOS build 37 compiled successfully. The Python export/migration tools passed 18 tests. No Cryptomator dependency or storage conversion was added.
- [Reviewed screenshots and contact sheets](../../design/ui-refinement/implementation/build37/README.md) cover actual app-owned layouts and native adaptations. The host microphone request stalled in one simulator attempt; physical sound/recording is not established by these UI checks.
- Local results: `/private/tmp/waglock-ui-complete-final-units.xcresult`, `/private/tmp/waglock-ui-complete-checks3.xcresult`, `/private/tmp/waglock-build37-device.log`. Failed intermediate runs are retained as local diagnostics and are not presented as passing.

The staged repository snapshot also built successfully from a clean directory (`/private/tmp/waglock-clean-ui37`, unsigned simulator build). This checks that required source, assets and project files are present without relying on untracked local build inputs.


## Owner override — native video viewer, build 44 (2026-10-23)

The owner rejected the redesigned stacked video-player page and requested a standard interface. Full-screen playback now uses Apple's AVPlayerViewController on a black canvas with aspect-fit video and native transport/scrubbing/volume/rate controls. Done and Share live in the navigation bar; an actions menu contains Info and confirmed deletion. This deliberately supersedes the Figma video-player card layout. Grid thumbnail proportions and other screens are unchanged.

Playback remains session-bound. Background/logout/dismissal cancel pending loads, pause/detach the player and clean its owned plaintext temporary file; late results cannot republish a player. Sharing keeps the existing session-bound export service with an additional per-view generation check. Picture in Picture, external playback and lock-screen Now Playing publication are disabled for this authenticated viewer. Native device sound, rotation and sharing remain owner acceptance checks.
