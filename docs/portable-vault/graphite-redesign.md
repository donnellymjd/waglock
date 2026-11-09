# Graphite redesign (handover 2026-11-08)

Status: implemented on 2026-11-09 in two passes (core screens, then the remaining canvas screens). It has not been compiled, run, screenshotted or checked on a device. Sources: the "WagLock Redesign — Handover & Privacy Spec" document and the "WagLock Redesign" canvas (39 screens and the "Spec · tokens & components" board). Where they disagree, the canvas wins for layout and the document wins for behavior. The privacy and passcode half is in [library-slots.md](library-slots.md).

## Design system

- **Dark only.** `.preferredColorScheme(.dark)`, `UIUserInterfaceStyle = Dark`, and the Appearance setting is removed (its stored preference is cleared at launch). Library layout (grid columns and sort order) moved to its own Settings row.
- **Tokens:** `Graphite` in `WagLock/Utilities/ColorTheme.swift` mirrors the spec board: bg/base #1A1E29, scrim #0E1118, media #0A0C11, surface/bar #242936, surface/1 #262B38, input #2C3140, surface/2 #2F3544, line #3A4152, text #F3F5F9 / #C1C7D3 / #A7AEBD, accent #8DBEFF, gradient #A9CEFF→#4C8DFF, on-accent #0A1530, warn #FFC46B, danger #FF9C9C (line #FF8A8A). The older `ColorTheme` names map onto these, so every existing screen re-skins.
- **Type:** bundled Poppins 400/500/600/700/800 (OFL 1.1; see `WagLock/Resources/Fonts/PROVENANCE.md`), registered through `UIAppFonts` with a runtime fallback. The styles `wlDisplay`, `wlTitle`, `wlSheetTitle`, `wlHeading`, `wlBodyStrong`, `wlBody`, `wlMeta`, `wlLabel`, `wlButton` and `wlTab` all use `Font.custom(_:size:relativeTo:)`, so they scale with Dynamic Type. Display and title sizes stop growing at `accessibility1`, about 1.4×.
- **Components** in `WagLock/Views/Shared/WagLockDesign.swift`:
  - buttons: primary (54 pt gradient with glow), destructive outline, secondary
  - `WagLockField` (default, focus and error states)
  - `WagLockKeyboardPicker` (Number pad / Full keyboard)
  - `WagLockRow` (standard, destructive and dashed add)
  - `WagLockNote` (info, caution and error)
  - `WagLockSheetHeader`
  - `WagLockSectionLabel` and `WagLockTitle`
  - restyled progress, empty-state and card components
  - `WagLockChrome` (tab bar, navigation bar and segmented control appearance)
- **Icons:** SF Symbols as named on the board. Tab icons: square.grid.2x2, rectangle.stack, folder, note.text, slider.horizontal.3.
- **Motion:** a shake on a wrong passcode, skipped under Reduce Motion. The unlock dial animation and haptic are not built; the handover says they still need prototyping.

## Screens implemented

| Canvas frame | Implementation |
|---|---|
| Unlock, Unlock · wrong passcode | `LoginView`: hero, "Welcome home!", field with error state, global "Use number pad / full keyboard" link, UNLOCK and Face ID buttons, "Can't unlock? Get help" |
| Settings (home with backup card) | `SettingsView`: Lock now, backup card (BACKUP DUE, last backup, BACK UP NOW, reminder frequency), Security & access, App icon, Library layout, Storage, Encrypted backup, About, LOCK WAGLOCK |
| Security & access, Passcodes, Add a passcode (+ rejected), Time lock, Delete this library, Face ID setup | `PasscodeSettingsViews.swift` (slot mode); identical in every library |
| Onboarding 1 and 3, Backups (4) | `OnboardingViews.swift`: Welcome → Create passcode (with the no-reset acknowledgment) → "Your way back", shown once after the first library opens, with "Not now" |
| Unable to open library | `AuthenticatedLibraryView` failure state with its reference code |
| Can't unlock? | Copy updated in `UnlockHelpView`; layout still a list |
| Library, Empty library, Selection | `LibraryView`: All / Photos / Videos / Audio chips (All is a day-grouped grid of this library's photos, videos and audio), add button, backup-health banner and empty-library hero. The Photos selection bar is a floating Move to album / Export / Delete toolbar. |
| Add to WagLock, Import progress, Import complete | `ImportButtonsView`: source rows; progress as "N of M" with the stop-on-lock caution; completion with count, the originals-still-in-Photos warning, Keep or **Remove from Photos…** (only when every selected item committed; iOS shows its own confirmation and items go to Recently Deleted), and Back up now. |
| Photo viewer, Photo information, landscape | `PhotoDetailView`: full-bleed media, top bar (close, date, time, position, more), Info / Album / Export / Delete toolbar that becomes a trailing side rail in landscape, and tap to hide chrome. `PhotoInfoSheet` shows created, dimensions, size/format and duration. |
| Video viewer, landscape | `VideoPlayerView`: the same chrome around the native AVKit player, whose transport controls are kept on purpose (accessibility, scrubbing and speed). AirPlay stays off. |
| Albums, Album, Album unlock, New album | `AlbumBrowserView`: two-column album cards with OPEN/LOCKED and the protection, album header with item counts and protection chips, 4-column grid, ADD TO ALBUM menu, the unlock screen, and the protection radio list. |
| Notes, Note editor | Title, count, search and an autosave note on the list. The editor has a large title field, a saved/encrypted status and a formatting bar (Heading, List and Checklist each start a new line with a marker; notes stay plain text). Bold is omitted because iOS 17 `TextEditor` exposes no selection to wrap. |
| Files | Title, count, search, All / PDFs / Documents / Other chips, icon-tile rows and the open-here note. |
| Audio player | Waveform card (decorative), title and metadata, scrubber, gradient play/pause, ±15 s, export, privacy note. |
| Backup failed, Backup recovery key | `BackupFailedCard` replaces the inline error after a failed preparation. **Generate a recovery key** creates a standard age X25519 identity, shows it once in groups of four with Print and Save to Files, has no copy button, and fills in the public recipient. The Bech32 encoder was checked against rage (pyrage) and has a unit test vector. |
| Settings › Storage | This library's size and per-type counts, the storage-mode card (Standard or Fixed size, Change size…, Switch to Standard / fixed size…) and Clear cache. |
| Onboarding 2, Switching storage, Reserved space full | `StorageViews.swift`, backed by the reserve in [fixed-size storage](fixed-size-storage.md). Switching storage shows a percentage and time left, and Pause/Resume. Reserved space full appears when an import has no room. |

Tabs are now Library · Albums · Files · Notes · Settings. Accessibility identifiers used by UI tests are kept where screens survived. UI tests were updated for the new tabs, chips, add button, import-complete screen, viewer close buttons, album cards (matched by identifier), album unlock buttons and the removed Appearance setting.

## Not built, and why

- **Password plus recovery key in one backup.** The Onboarding 4 and Recovery key frames imply both on one file. The age format allows a password (scrypt) recipient only on its own, so a backup uses either a password or a generated recovery key.
- **Import pause and resume.** The canvas says leaving WagLock pauses an import and resumes it after unlock. Imports still stop on lock, nothing partial is kept, and the progress screen says so.
- The unlock dial animation and the canvas hero artwork; only the app icon ships.
- Portrait lock for non-viewer screens; rotation behavior is unchanged.

## Verification status

This environment was Linux with no Swift toolchain, and the proxy blocked downloading one. Nothing was compiled, run or screenshotted. Before relying on this pass:

1. Build in Xcode.
2. Run `xcodebuild test`.
3. Capture the Graphite screenshots with `DesignAppearanceUITests`.
4. Run a physical-device pass on contrast, Dynamic Type and font registration.
