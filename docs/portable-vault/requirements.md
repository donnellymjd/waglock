# Vaultito requirements

Planning baseline: 2026-10-17, America/New_York. These are goals; implementation status is tracked separately in [D2S-105](audits/D2S-105.md).

Sources: [Linear project](https://linear.app/d2sci/project/portable-vault-sealedpocket-fork-10d5618162e3), [linked product specification](https://linear.app/d2sci/document/product-requirements-and-release-gates-portable-vault-20b0d84aa2c2), and issues D2S-105–121. The [snapshot](linear-requirements-snapshot.md) preserves the linked specification and issue inventory. Resolve conflicts explicitly; later issue D2S-119 clarifies the free-launch/paid-transition direction beyond the project's general price preference. The user's setup instruction makes Cryptomator a proposal to validate before storage replacement.

## Audience and product commitments

Sensitive, long-lived photo/video libraries need a native media gallery and practical independence from the original app and phone. The distributed app's entire source should be inspectable, forkable and independently buildable from tagged releases.

| Requirement | Expected behavior and evidence | Linear work |
| --- | --- | --- |
| Local use | No mandatory cloud, account, server, telemetry or subscription. Unlimited local items, subject to disk capacity; optional encrypted backup off by default. | D2S-112, 114, 118 |
| Portability | Copy the complete encrypted directory and open files with an unmodified Cryptomator desktop client. Validate supported versions/platforms; no compatibility claim from shared cipher choice alone. | D2S-107, 109 |
| Recovery | Restore from encrypted files plus documented password/recovery materials without original phone or Keychain; verify contents, metadata and corruption detection. | D2S-110, 114 |
| Independent password | Separate vault password from device passcode; analyze supported KDF parameters, key lifecycle, lock behavior, wrong-password/lockout and recovery. Optional Face ID is convenience. | D2S-111 |
| Media gallery | Photos-like grid, albums, favorites, search/basic metadata, videos, selection and bulk Photos/Files import; preserve original quality and browse thousands efficiently. | D2S-112, 117 |
| Safe migration | Verify Private Photo Vault export methods with disposable assets, preserve available originals/EXIF/names/dates/albums/videos, resume/deduplicate and report counts/hashes/mismatches; never automatically delete originals or plaintext exports. | D2S-108, 113 |
| Decoy isolation | Distinct real/decoy ciphertext and keys, separate passwords, no metadata/log/backup cross-leaks; no forensic deniability guarantee. | D2S-105, 115 |
| Data security | Stream large files; protect thumbnails/indexes/temporary files/logs; integrity checking, crash-safe writes, disk-full handling and lifecycle cleanup. | D2S-105, 116, 117 |
| Transparent release | Full matching source, dependency/license inventory, beginner-friendly macOS/Xcode/signing/install guide, recovery docs and verifiable test limitations. No byte-identical or independent-audit claims without evidence. | D2S-106, 118, 120, 121 |
| Pricing and referrals | Initial free launch, then approximately $5–$10 one-time upfront price; early users retain access. No recurring fee for core offline use or referral-gated vault access. Share-sheet-first referrals, no contact uploads or incentivized reviews; any metrics require consent and privacy validation. | D2S-119, 121 |

Cryptomator is the proposed route to the portability requirement. Failure of feasibility triggers a recorded alternative and explicit requirements review, not silent weakening of independent desktop recovery. Do not assume albums round-trip or existing custom ciphertext converts in place.

## Validation gates

| Gate | Required evidence before passing |
| --- | --- |
| A — feasibility | Repository/source and signed device build validation, architecture audit, licensing route, tested Private Photo Vault export matrix. |
| B — compatibility | iOS-created encrypted media opened by unmodified desktop Cryptomator; record format/client/library versions, encrypted layout and reproducible checks. Cover macOS/Windows/Linux goal with a supported-platform matrix. |
| C — recoverability | Cold restore on a fresh device with no original Keychain; verify content hashes, metadata and integrity failures. |
| D — migration | At least 1,000 sample source assets; interruption/resume, duplicates, albums/metadata, counts/hashes and mismatch report. |
| E — security | Threat model, severity-rated findings, main/decoy separation tests and storage/cache leakage review; fix release blockers. |
| F — distribution | Performance/reliability and TestFlight validation; license/branding/App Store review, source tags/build guide, privacy/recovery documentation and paid-store eligibility. |

Project milestones: audit/feasibility → portable prototype → gallery/migration MVP → hardening/beta → open-source release. No committed timeline until architecture and migration feasibility pass. Exact distribution terms, Apple developer fees, dependency versions and licensing conclusions must be verified when the related work is performed.

## Initial MVP exclusions and open questions

Exclude two-way multi-device sync, automatic source plaintext cleanup, forensic-deniability guarantees, server-hosted photo backup and AI photo search.

Open decisions: Cryptomator library/version/license and filesystem orchestration; File Provider necessity; protected/rebuildable gallery index and album representation; actual Private Photo Vault Photos/Files/Wi-Fi/share export fidelity; iCloud quota/inclusion/restore behavior; GPL/AGPL and App Store/TestFlight distribution; reproducible builds and release equivalence; pricing transition and privacy-preserving referral experiment. Existing notes/audio/calculator features are reuse candidates, not added MVP promises.

## Phone feedback — 2026-10-17, build 24

The user reported the requested functional hardware pass successful and added two P2 backlog items:

- [D2S-126 — Preserve original aspect ratio in video thumbnails](https://linear.app/d2sci/issue/D2S-126/preserve-original-aspect-ratio-in-video-thumbnails): correct proportions/orientation in the gallery and nested albums without changing originals.
- [D2S-127 — Default login prompts to a PIN-style numeric keypad](https://linear.app/d2sci/issue/D2S-127/default-login-prompts-to-a-pin-style-numeric-keypad): numeric-first login with a clear unlock action and an obvious text-password option. Existing alphanumeric vault/album passwords, Face ID, credential policy and key material must remain usable and unchanged by the UI default.

These are follow-up requirements, not claims that either presentation change is already implemented. They do not change the original Linear requirements snapshot.

## Owner priorities — 2026-10-18

1. English-only beta UI for now, Latin executable/product labels and understandable/redacted diagnostics. Preserve license/copyright originals, provenance and Unicode user data; translate remaining source comments incrementally. See [the language strategy and beta gates](beta-readiness.md).
2. All existing features free now. VIP walls were removed in build 26; do not add purchase/entitlement checks. The earlier possible later upfront pricing remains deferred.
3. Continue D2S-105/116 security review before sensitive-library use; prepare a friend beta ASAP with explicit source, branding, distribution and data-safety gates. Functional dummy-media testing is distinct from audit/recovery acceptance. No external beta invitation/upload is authorized or performed by this priority update.

4. **Secondary passcode / independent alternative vault**: at the same login prompt, a different passcode must open a separate usable vault without revealing the primary vault through ordinary UI. Current Guest Mode does not qualify. [D2S-115](https://linear.app/d2sci/issue/D2S-115/design-and-implement-decoy-vault-guest-password-isolation) is High priority; [design and acceptance](secondary-vault-design.md) require distinct keys/indexes/storage, scoped services/caches/settings, non-destructive legacy handling and biometric review. Forensic invisibility and coercion safety are not guarantees. Not implemented in build 27.

## Encrypted Trash — owner request 2026-10-22

[D2S-140: encrypted Trash and configurable retention](https://linear.app/d2sci/issue/D2S-140). Backlog requirement; not implemented in build 32.

Deletion should move items into an encrypted Trash bin inside their originating vault, allowing users to undo deletion by restoring them. Trash is **enabled by default with seven-day retention**. Settings must allow changing retention duration or turning Trash off; other duration choices remain to be designed.

Preserve encrypted originals, thumbnails and restoration metadata, and enforce vault/album access on Trash and restored items. Restore album placement where possible; resolve missing albums or name conflicts without overwriting data or weakening protection. Confirm permanent deletion/Empty Trash and explain that disabling Trash makes future deletions bypass recovery. Define how existing Trash is handled when disabling or shortening retention before implementation; preference changes must not silently purge retained items. Expiry cleanup may be delayed while iOS is not running the app; no exact background deadline or forensic-erasure promise. Validate restoration, expiry, disabled mode, session isolation, restart/clock changes, interrupted writes and low storage with disposable fixtures.

## Elevated export and nested-vault priorities — 2026-10-22

- **[D2S-114](https://linear.app/d2sci/issue/D2S-114), High:** complete-vault export in a secure, documented format supported by an independently usable open-source tool. Prefer the same validated native and export format. Include version-pinned opening/decryption and verification instructions, originals, protected metadata/hierarchy and required recovery material; test cold recovery without the original iPhone/Keychain. Define notes/Trash coverage and never silently omit required content. Current storage is custom; this request does not establish interoperability or approve a replacement. Cryptomator remains a candidate under D2S-106/107/109/110.
- **[D2S-141](https://linear.app/d2sci/issue/D2S-141), High:** vaults within a vault, represented as albums/subdirectories with their own passwords/passcodes at multiple levels. Existing Photos → Albums supports the basic nested protection workflow. Complete its metadata, lifecycle and recovery requirements; parent/outer credentials alone cannot bypass separately protected children. Retain explicit inherited and biometric choices, and test cross-level/sibling isolation.

The export design must preserve these child-password boundaries; it must not flatten protected albums or bundle usable child keys protected only by the main vault password. A copied custom ciphertext directory is not independently recoverable merely because its cipher is open. Demonstrate actual opening with the selected open-source tool and documented inputs. Face ID-only factors remain device-bound: resolve a reviewed recovery/protection-change path or explicit blocker before claiming a complete portable backup. Do not silently omit content or downgrade its security. Native format changes need a separate non-destructive migration/rollback design and validation. See [updated backlog order](backlog-priorities.md).

## Additional requested backlog features — 2026-10-22

- [D2S-142 — Self-destruct lock](https://linear.app/d2sci/issue/D2S-142): optional behavior after repeated wrong passwords. Define lockout versus destructive action, threshold, scope and recovery before implementation. Destruction requires explicit opt-in, is disabled by default, and must not trigger from biometric cancellation or infrastructure errors. No destructive setting is enabled by adding this issue.
- [D2S-143 — Private Markdown notes](https://linear.app/d2sci/issue/D2S-143): encrypted note titles/bodies/tags/drafts, Markdown editing and preview, vault/session isolation, safe rendering without automatic external requests, and lossless encrypted export/recovery. Existing plaintext SecretNote storage remains an audit gap requiring a source-preserving transition.
- [D2S-144 — Encrypted file search](https://linear.app/d2sci/issue/D2S-144): offline search over authorized names/folders/metadata with an encrypted persistent index and session-scoped decrypted results. Locked albums and other vaults must not leak matches/counts/snippets. Full-text format coverage remains to be specified; no cryptographic search-over-ciphertext claim.

All three are Backlog items; the existing top-priority export, recovery, nested-vault and security work is unchanged.

## 2026-10-22 — Backup choices and system cloud destinations

The owner authorized the complete export work, cryptographic options and optional on-device cloud backup through the iOS interface. Build 39 uses an additional standard age format (password/scrypt or X25519 recovery recipient), preserving the current native store and Cryptomator proposal. The native Files export picker receives completed ciphertext and lets the user choose local, iCloud Drive or installed providers. This is manual copy, not automatic backup/sync. Device settings/biometric registrations are excluded explicitly; each independently protected child keeps its own password. Face ID-only export requires explicit copy consent, real biometrics and a new confirmed export password without changing native policy. [Implementation/limits](age-backup-design.md), [recovery procedure](backup-recovery.md). Existing recovery/security/distribution gates are narrowed by the recorded evidence, not waived.
