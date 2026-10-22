> October 21 update: the [Blue Guardian](../blue-guardian/README.md) is now the default. Caught You Looking returns as a separate alternate. Current brand line: **We Always Guard**. The historical selection notes below describe earlier builds.

# Selected beta icon options

Selected by the owner on October 19, 2026. **Caught You Looking is now the default icon**, replacing the inherited Loop. W Spectrum and Watchful Husky remain free alternate options. The icon-selection update originally preserved the Vaultito app name. On October 20, the owner renamed the app to **WagLock — All wag. No tell.** Installed identity remains stable; see [build 28](../../../docs/portable-vault/waglock-branding-and-thumbnails.md).

See the [current picker with Caught You Looking selected as default](default-caught-you-looking-ios18.png). The [initial picker screenshot](app-icon-picker-ios18.png) records the earlier addition before the default changed; it is retained as historical test evidence.

| Picker label | App icon asset | Source |
| --- | --- | --- |
| W Spectrum | `AppIcon-Spectrum` | [Six-W circle](../w-circle-exploration/assets/02-six-ws-icon-1024.png) |
| Caught You Looking (default) | `AppIcon` / `AppIconDisplay` | [Selected rear-view cartoon](../dog-guardian-exploration/mockups/03-caught-you-looking.png) |
| Watchful Husky | `AppIcon-WatchfulHusky` | [New front-facing husky head](../dog-guardian-exploration/watchful-husky/01-watchful-husky.png) |

Open Settings → App Icon while signed in to the owner vault to select an icon. Each option is free and uses the existing iOS icon-change flow. Paper, Calculator, Pebble and Ruler remain available; Loop has been removed. The shared default preview also updates the login/launch and settings artwork. The later WagLock rename preserves signing identifiers, Keychain service, vault data and icon-change authorization. Icon selection changes appearance; it does not hide the installed app or make a vault undetectable.

The previous `AppIcon-CaughtYouLooking` alternate asset stays bundled as an upgrade compatibility alias, containing the same image as the new default. Installations already using that name show the default row as selected. There is no duplicate Caught You Looking row. Switching to an alternate and back restores the system's primary (`nil`) icon normally. Old Loop PNGs were removed from both primary asset sets.

`export-icons.cjs` performs size/format export into the [asset catalog](../../../WagLock/Assets.xcassets): 1024 × 1024 square opaque sRGB PNGs with matching image-set previews. It retains the complete artwork with no baked outer corner mask. The generated originals are preserved separately; these PNGs do not imply editable vector masters. Set `VAULTITO_DESIGN_MODULES` to a directory containing sharp when regenerating on another machine.

Authorship: W Spectrum is AI-assisted procedural vector artwork from the preceding W study. Caught You Looking and Watchful Husky are generated raster illustrations made with the built-in image generator. Exact prompts are preserved in the [four-concept prompt set](../dog-guardian-exploration/mockups/GENERATION-PROMPTS.json) and [Watchful Husky prompt](../dog-guardian-exploration/watchful-husky/GENERATION-PROMPT.json). No third-party cartoon or stock art was used as an input. Existing upstream attribution and license notices remain in place.

These optional beta inclusions do not establish trademark clearance. The earlier [radial-mark resemblance findings](../identity-exploration/RESEMBLANCE-REVIEW-2026-10-19.md) remain relevant to W Spectrum's composition; changing the letter does not resolve them. No new resemblance review has been completed for either dog illustration. Matching source, licensing and brand/distribution review remain necessary before public release.

## Default replacement validation

The follow-up simulator build and **12 selected tests passed** (eight AppIconServiceTests, three LocalizationCoverageTests and the icon UI workflow). The added regression checks an existing `AppIcon-CaughtYouLooking` system selection maps to the single default row and can switch away/back normally. The UI workflow verifies the new default label, no Loop or duplicate row, alternate selection and default restoration. Identical primary/display/compatibility image bytes and removal of old PNGs from the two primary asset sets were also verified. Result: `/private/tmp/vaultito-default-dog.xcresult`; log: `/private/tmp/vaultito-default-dog-tests.log`. No phone install or physical-device validation was performed.

## Initial addition validation

On October 19, 2026, a simulator build and 11 selected tests passed: seven AppIconServiceTests, three LocalizationCoverageTests and one AppIconUITests workflow. The UI test selected all three new icons through the system confirmation and restored the default. Asset-bundling tests checked every picker preview and the current device's icon manifest; a separate inspection confirmed all three alternates in both compiled iPhone and iPad manifests, with bundle ID `com.d2sci.vaultito.dev` unchanged. Asset export checks confirmed opaque 1024 × 1024 RGB PNGs and identical picker previews. Source links and `git diff --check` passed.

The test used disposable simulator `Vaultito Icon QA 18` (`BCABB01C-79F3-4726-A7A0-6F42BC9612C3`), ad-hoc simulator signing, derived data `/private/tmp/vaultito-icon-options`, log `/private/tmp/vaultito-icon-options-tests.log` and result bundle `/private/tmp/vaultito-icon-options.xcresult`. No physical-device install or runtime test was performed for these icon additions. Existing project warnings remain, including Swift concurrency/deprecation diagnostics and the UI test target's inherited deployment-target warnings; the icon build/test run completed successfully.
