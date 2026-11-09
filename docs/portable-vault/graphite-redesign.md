# Graphite redesign (handover 2026-11-08)

Status: first implementation pass on 2026-11-09. It has not been compiled, run, screenshotted or checked on a device. Sources: the "WagLock Redesign — Handover & Privacy Spec" document and the "WagLock Redesign" canvas (39 screens and the "Spec · tokens & components" board). Where they disagree, the canvas wins for layout and the document wins for behavior. The privacy and passcode half is in [library-slots.md](library-slots.md).

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
| Library | `LibraryView`: title, "N items · On this device" (this library only), Photos / Videos / Audio chips over the existing audited screens |
| Albums | `AlbumsTabView`: own tab around the unchanged `AlbumBrowserView` |
| Settings (home with backup card) | `SettingsView`: Lock now, backup card (BACKUP DUE, last backup, BACK UP NOW, reminder frequency), Security & access, App icon, Library layout, Storage, Encrypted backup, About, LOCK WAGLOCK |
| Security & access, Passcodes, Add a passcode (+ rejected), Time lock, Delete this library, Face ID setup | `PasscodeSettingsViews.swift` (slot mode); identical in every library |
| Onboarding 1 and 3, Backups (4) | `OnboardingViews.swift`: Welcome → Create passcode (with the no-reset acknowledgment) → "Your way back", shown once after the first library opens, with "Not now" |
| Unable to open library | `AuthenticatedLibraryView` failure state with its reference code |
| Can't unlock? | Copy updated in `UnlockHelpView`; layout still a list |

Tabs are now Library · Albums · Files · Notes · Settings. Accessibility identifiers used by UI tests are kept where screens survived, and UI tests were updated for the new tabs, the Library chips, the keyboard link and the removed Appearance setting.

## Not yet implemented

These need follow-up work. Most reuse the components above.

- Onboarding 2 (storage privacy) and the whole fixed-size storage feature, including Settings › Storage mode, Reserved space full and Switching storage.
- An "All" chip that mixes photos, videos and audio in one grid. The current chips switch between the existing screens.
- Empty library hero, Import progress, the Import complete sheet (keep or remove originals in Photos, back up now), Selection, Backup failed and Backup recovery key.
- Photo viewer, Photo information and Video viewer restyles and their landscape side rail. Portrait-only for every other screen is not enforced; viewer rotation is unchanged.
- An album unlock that lasts until WagLock locks (existing behavior unchanged), and the album and New album protection restyles.
- Notes, Note editor (formatting bar), Files (filter chips) and Audio player restyles beyond the tokens.
- Recreating the canvas hero artwork (only the app icon is used) and the dial animation.

## Verification status

This environment was Linux with no Swift toolchain, and the proxy blocked downloading one. Nothing was compiled, run or screenshotted. Before relying on this pass:

1. Build in Xcode.
2. Run `xcodebuild test`.
3. Capture the Graphite screenshots with `DesignAppearanceUITests`.
4. Run a physical-device pass on contrast, Dynamic Type and font registration.
