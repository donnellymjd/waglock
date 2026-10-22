# English-only friend beta priorities — 2026-10-18

Current brand (2026-10-20): **WagLock — All wag. No tell.**, development display name **WagLock Dev**. [Build 28](waglock-branding-and-thumbnails.md) preserves the installed `com.d2sci.vaultito.dev` identity and credentials. Earlier Vaultito references below record the beta preparation history.

The owner prioritized understandable English branding/diagnostics, unrestricted free features and the security audit before inviting a friend. The beta UI is English only for now. The owner also prioritized [an independent alternative vault selected by a secondary passcode](secondary-vault-design.md); build 27 does not implement it. This document tracks preparation, not permission to publish or evidence of a completed independent audit.

## 1. Language and identity strategy

| Surface | Action / boundary |
| --- | --- |
| Crash process and app product | Build 27 renames the product/executable to `Vaultito` (`Vaultito.app`), including shared scheme and unit-test host. Target/scheme/module stay `ZeroNet-Space` / `ZeroNet_Space` for build compatibility. |
| Installed identity and existing data | Preserve `com.d2sci.vaultito.dev`, signing team, Keychain service/accounts, database schema, encrypted paths and album IDs. A product-name change must be verified as an update; never uninstall/reset the owner's vault to make a test pass. |
| App-controlled UI and permission messages | Bundle English catalog and English InfoPlist resources only. Other translations are preserved in [provenance](provenance/README.md), outside the app. Translate remaining literal progress/errors into English and avoid exposing internal paths. SwiftUI/date/relative-date presentation uses an explicit English locale; user content is unchanged. |
| Logs | Remove inherited `print` diagnostics rather than translate sensitive filenames, dimensions, paths, credentials/state or raw errors into English logs. Future diagnostics need fixed English event names and redaction; no raw media/credential interpolation. |
| Source comments | Translate file by file as the code is reviewed, preserving meaning and attribution. After runtime cleanup, 1,239 Chinese-containing Swift comment lines remain. Do not delete comments wholesale or pretend this phase is complete. Corrected the misleading thumbnail-encryption comment in MediaItem. |
| Copyright, license and history | Preserve LICENSE, copyright notices, TRADEMARK.md and original provenance. Add readable English explanations alongside originals. Never replace an author's name or alter license text merely to satisfy a character scan. |
| User content and OS text | Do not transliterate/change user filenames, album names, passwords, metadata or ciphertext. Device language can still affect OS-owned screens; an English beta cannot guarantee that every OS crash field or user string contains Latin characters. |

Renaming process labels does not remediate a crash or improve encryption. Build 25's calculator cleanup workaround remains in place. Do not rename existing on-disk paths to match the new product name.

## 2. Free features

Build 26 removed the purchase manager, StoreKit product/configuration, entitlement flags, import caps and alerts, paid-icon badges and audio share/export gates. Build 27 removes the now-unused review/demo purchase flag and public demo-password constant; normal password verification still applies to every login, including an existing vault using that string as its own password. No password is changed by this cleanup.

All existing local features are available without payment. Owner/guest/album authentication and hardware/permission errors remain meaningful access conditions. Future pricing is deferred; do not add a payment flow while preparing this free beta.

## 3. Focused audit status

| Finding | Current assessment / beta consequence |
| --- | --- |
| A01: metadata/thumbnails/notes | Still high/open. MediaItem persists names, metadata and raw thumbnails; SecretNote persists title/content/tags. Album names/hierarchy also need protection. OS Data Protection is not application-level encryption. No sensitive-library beta acceptance. |
| A02: recovery | Still high/open. Current password plus copied ciphertext is not a general recovery package after password changes. Device-only Keychain and Face ID-only album recovery limitations persist. Never use the beta as the only copy. |
| A03: decoys | Still high/open. Guest Mode is presentation filtering, not an independent populated encrypted vault. No deniability promise. |
| A04/A05/A06/A11 | Prior stream framing, atomic credentials, import/session and cache fixes have regression evidence, with documented legacy/journal/physical-device limits. They do not close their entire findings. |
| A07: original quality/migration | Still open. Photos import recompresses images; disposable source export matrix and round-trip evidence are required before migration claims. |
| A08: plaintext working copies | Still open. Share/export/preview cleanup after crash, background and cancellation requires further review. |
| A09: credential formats/KDF | Current owner envelope is hardened; old guest/disguise/legacy formats and KDF benchmarking remain open. |
| A10: diagnostics | Build 27 removes all 151 inherited app Swift `print` calls. New ciphertext names were already opaque. Legacy ciphertext names, plaintext database metadata, crash content and OS logging are separate residual risks. |

The [D2S-105 audit](audits/D2S-105.md) remains open. These are source-review conclusions and scoped test results, not an external penetration test, recovery certification or absence-of-vulnerabilities claim. Cryptomator remains an isolated proposal; no production adoption or storage conversion is authorized.

## Friend beta gates

1. Pass a clean signed simulator test run and device build with Latin executable, English fallback on a Chinese-language device setting, no StoreKit resource/purchase UI, stable bundle identity and old/new sample readability. Record physical update/install results separately.
2. Preserve/export original disposable test media outside Vaultito. Test import/cancel/background/logout, wrong/right password, Face ID success/cancel and audio export/icon changes. No real sensitive or irreplaceable media until the relevant security/recovery findings are resolved.
3. Resolve branding assets: current primary and alternate icons are inherited and were not replaced by the process-name cleanup. TRADEMARK.md restricts official logos/icons; distinct Vaultito artwork and attribution review are required before distributing to the friend.
4. Prepare the exact corresponding source, modification notices (see [NOTICE.md](../../NOTICE.md)), license/dependency inventory and reproducible build instructions for the actual beta. GPL compliance and Apple's distribution terms need a recorded route; do not assume a free binary or private TestFlight group removes obligations. No upload/invitation has been performed.
5. Choose installation: a registered-device development/ad hoc install needs the friend's device registration/provisioning; external TestFlight's first build requires Beta App Review. No promise of same-day Apple approval. Select the route once the candidate and distribution review are ready.

Primary references checked 2026-10-18: [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.en.html), [GNU copyright/license notice guidance](https://www.gnu.org/licenses/gpl-howto.en.html), [Apple external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), [Apple beta distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases). This records implementation/distribution work still needed; it is not a legal approval.
