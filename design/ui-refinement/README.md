# WagLock — Complete app UI design

[Start here: Figma screen index](https://www.figma.com/design/sOaFXyvdlCstDTQ4Zfn7xz?node-id=40-2436)

The complete design covers **83 screen states in light and dark appearance** (166 editable screen frames), with 732 prototype links. The five existing tabs remain Photos, Media, Files, Notes and Settings. The index provides direct links to every state; the file also contains Light and Dark starting flows. See [the inventory](SCREEN-INVENTORY.md).

## Coverage

- Setup, unlock, keyboard selection, unlock errors and password help.
- Photos, selection, albums, album security, album unlocking, subalbum actions, renaming, deleting empty albums and verified moves.
- Import source choices, progress, completion, interrupted imports and protected-file password entry.
- Video and audio browsing/playback, file previews, unsupported formats, notes and editing.
- Export selection, preparation, share-ready state and native iOS sharing reference.
- Appearance, grid columns, sorting, all eight app icons, storage, cache clearing, app information, offline explanations and the complete original bundled license text.
- Face ID setup/consent, auto-lock, Guest Mode/restricted views, calculator login and password changes.
- Empty, loading, error, success and confirmation states.

## Design decisions

Use the selected Blue Guardian icon and We Always Guard identity. Keep predictable navigation, readable photo tiles, related actions grouped together and short privacy explanations at the point where they matter. Put the Number pad / Full keyboard selector above password entry. Follow device appearance by default, with System / Light / Dark choices.

Preserve the app's actual security boundaries: Guest Mode is not an independently encrypted decoy vault; Face ID opens its assigned vault; album names and hierarchy remain visible; Face ID-only albums are device-bound; password recovery is not implemented. No cloud sharing feature is implied by this design.

## Prototype and implementation limits

The navigation is clickable, but fields, playback, progress, storage values and photo metadata are illustrative. Native pickers, Face ID, share sheets and system confirmations must remain native iOS operations. In-place choices such as sort values and grid columns show representative states rather than fully simulated app logic.

Figma's Apple library import was denied and SF Pro rendered blank. The owner approved Inter for the review. Editable outline icons replace unavailable SF Symbol glyphs. Implementation must retain native SF Pro/SF Pro Rounded, SF Symbols, accessibility, keyboard-switching behavior and authentication checks. No Swift/app source was changed by this design work.

## Verification

All 140 frames were structurally checked: 1,752 editable text nodes, no missing/zero-width text, no unexpected horizontal or vertical overflow. Long forms, icon lists and legal text scroll intentionally. Representative screens across tabs, security, setup, errors and both appearances were visually reviewed. Final navigation audit: 732 links, zero broken destinations. Temporary QA copies were removed.

## Assets and provenance

The six sample photos are AI-generated design content, not private user media. The built-in image generation tool created one six-panel contact sheet; tiles were exported deterministically for the UI. Original sheet, tile exports and exact generation prompt are saved in assets/. Existing app icon artwork was reused. Original Figma review font choice and full-app completion were authorized by the owner.

## Application implementation

Build 35 begins applying this design to the SwiftUI app. See [implementation coverage, adaptations and remaining work](../../docs/portable-vault/figma-ui-implementation.md). The design inventory remains broader than the first implementation pass.

Build 37 completes the remaining current-feature layouts. See the [70-state runtime mapping and native adaptations](IMPLEMENTATION-COVERAGE.md); security/storage roadmap features remain separate.

## Fullscreen media revision — October 23

Photo and video viewers now use the entire viewport, with a black background in both appearances. Media uses aspect fit with no forced crop or stretching. Wide content is letterboxed in portrait and gets a dedicated landscape layout.

Tap the media to hide/reveal chrome. A minimal close control and more menu overlay the media; video playback controls also overlay it and hide during viewing. Export, file information and delete live in the more menu. Metadata and destructive actions no longer compete with the media. Menu cancellation and hidden-control states preserve orientation. Single-item deletion is separate from batch selection deletion; video file information has its own view.

The Figma prototype illustrates these interactions; it does not play an actual movie, simulate device rotation or implement pinch zoom. The application should retain native video playback, safe-area behavior, photo pinch zoom and swiping, and support double-tap zoom without changing original aspect ratio. No app source was changed by this revision.

Viewer layouts were visually checked and the full revised registry audited: 166 frames, 1,802 editable text nodes, no broken navigation destinations or zero-width text.
