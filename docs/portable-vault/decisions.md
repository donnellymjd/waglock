# Vaultito architectural decisions

Recorded 2026-10-17. Accepted decisions below govern development; proposals do not authorize implementation or make product capability claims. Requirements: [requirements.md](requirements.md). Current implementation evidence: [D2S-105](audits/D2S-105.md).

## ADR-001 — Preserve the existing store during feasibility

**Status: accepted development constraint.**

The current app stores custom AES-GCM files under Documents/EncryptedMedia, SwiftData metadata/thumbnails/notes, and password-related Keychain entries. Keep this implementation and legacy readers intact while auditing. No data conversion, dependency addition, namespace change or storage replacement is part of setup. Bundle ID/Keychain service changes can strand existing data and need explicit migration design.

Future migration must use a separate destination, verified originals and metadata, resumable progress, interruption/disk-full tests and a rollback path. Do not overwrite the only copy or assume a lossless in-place conversion. This favors data preservation over early architectural commitment.

## ADR-002 — Evaluate Cryptomator as the portable format

**Status: proposed, not adopted.** Owners: D2S-106, 107, 109, 110.

The desired user operation is to copy an encrypted vault directory and unlock it with unmodified desktop software using documented recovery materials. Cryptomator is the candidate. The existing salt/IV/tag format and ZNSC chunks do not implement its vault layout; merely using AES-GCM cannot establish compatibility.

Before acceptance:

1. Pin candidate source versions and inspect licenses/dependencies; document a viable fork and distribution route (D2S-106). The [Cryptomator Swift repository](https://github.com/cryptomator/cryptolib-swift) identifies AGPL-3.0 and advertises a commercial route; applicable terms and a reviewed distribution agreement remain unverified. Existing fork LICENSE contains GPLv3 text. This is an inventory observation, not legal clearance.
2. Prototype local create/unlock, filename/directory/content encryption, streaming large videos, cancellation and low storage; determine what orchestration the cryptographic library lacks and whether File Provider is actually needed (D2S-107).
3. Record vault format, library/client/toolchain versions and encrypted directory layout. Prove iOS-created originals readable in unmodified desktop clients, with a macOS/Windows/Linux validation matrix, and document any safe reverse-write support (D2S-109).
4. Prove fresh-device recovery without original Keychain, preserving required key wrappers/configuration and verifying data/metadata integrity (D2S-110).
5. Specify protected index/album representation, decoy key separation and non-destructive migration from both legacy formats. Validate KDF choices against the chosen format rather than inventing incompatible Argon2id parameters.

If feasibility fails, retain the current store for development, compare alternatives and revisit product scope explicitly. Do not ship an app-only custom format under the portable-standard claim.

## ADR-003 — Protect each vault as an independent security domain

**Status: accepted requirement; design/implementation pending.** Owners: D2S-111, 115, 116.

Use independent main/decoy key material and ciphertext roots, protected metadata and thumbnails, and explicit authenticated vault context at service boundaries. Current Guest Mode is presentation filtering over one shared store and cannot satisfy this. A password must be independent of the device passcode; optional biometric access must not become a recovery dependency. Keychain is an optional local convenience, not the only recoverable key store. Define lifecycle cancellation so pending decode/decrypt jobs cannot repopulate caches after lock. No guarantee of forensic plausible deniability.

## ADR-004 — Treat backup and migration as verified data operations

**Status: accepted requirement; implementation pending.** Owners: D2S-108, 110, 113, 114, 117.

Backups copy complete encrypted vaults and required recovery metadata, with no plaintext library snapshot. Validate iCloud coverage and quota on real devices. Migration streams from supported exports and reports retained/lost metadata, counts/hashes, duplicates and retries. Preserve source assets and exports until the user independently chooses cleanup. Encrypted whole-vault backup and intentionally decrypted per-file sharing are separate operations and need distinct UX and tests.

## ADR-005 — Preserve evidence and open-source distribution options

**Status: accepted process decision; release eligibility pending.** Owners: D2S-106, 118–121.

Retain upstream attribution, LICENSE and TRADEMARK.md. Rebrand for release with separate identifiers and migration planning. Publish full matching source and self-build/recovery guides, distinguishing source inspectability from independent review and byte-identical reproducibility. Initial free launch followed by a one-time price and continued early-user access is product direction, subject to validation; legacy 75-item/VIP restrictions are not the target. No mandatory accounts, telemetry, subscription or referral gate. Do not resolve uncertain GPL/AGPL/App Store questions through assumptions; record a reviewed distribution path before release.

## ADR-006 — Adopt Vaultito as the working name

**Status: accepted provisional branding direction.** User-selected name: **Vaultito**. Tagline: **Your photos. Your keys. Your rules.**

Use this name for the app/fork in current documentation. Earlier Linear project titles and the source snapshot retain Portable Vault for provenance. The documentation directory stays `docs/portable-vault/` to preserve existing links. This naming decision does not establish store/domain/trademark availability or validate the security and recovery promises. Runtime display names, icons, Xcode targets, bundle identifiers and Keychain services require a separate coordinated rebranding change with data-access continuity checks.

## ADR-007 — Use an isolated Vaultito development installation

**Status: accepted for phone testing.** The user authorized preparing and installing a separate test build. Its display name is Vaultito Dev and its app ID is `com.d2sci.vaultito.dev`. Keychain service follows bundle identity; automatic legacy-service migration is disabled for this fork. Existing app/container/credentials remain separate. This is a fresh-vault test installation, not an upgrade or data migration from the existing app. The inherited encryption readers, format and directory structure inside the new container are retained.

Remove the arbitrary item cap across photo/file/gallery/audio import entry points and remove the main purchase prompt/product-fetch flow. Keep internal target/module/product names stable to avoid unrelated build/test-host churn. Mark setup and Settings as early testing and describe recovery/decoy limitations. Follow [device-testing.md](device-testing.md) for signing, namespace regression checks and manual acceptance; full migration and release branding remain separate decisions.

## ADR-008 — Nested album key domains and optional biometrics

**Status: accepted implementation direction, user-authorized 2026-10-17.** Add nested albums without replacing the inherited storage layer or adopting Cryptomator. Every album receives its own random key and encrypted catalog, with an envelope under the parent key; independent password and biometric modes add a factor inside that parent envelope. Protected media never enters the legacy global MediaItem query table. Parent lock/background/logout revokes descendant access and pending results. Existing data is retained through an additive SwiftData entity migration.

Vault Face ID is opt-in password-backed convenience. Album policies are inherited, separate password, password-or-Face-ID, and **Face ID only**, as explicitly requested by the user. Face ID-only albums require acknowledgement of device-bound loss risk and have no root/password bypass. This explicit request supersedes the earlier biometric-convenience-only guidance for this album mode; it does not validate portable recovery. See [albums-and-biometrics.md](albums-and-biometrics.md) for encryption, lifecycle rules, exposed album names, recovery exceptions and test limitations.

## ADR-009 — Authenticate new streams while retaining legacy readers

**Status: accepted bounded security hardening for development.** Owner: D2S-116 / audit A04. Build 23 writes ZNSC v2 streams using authenticated headers, record ordinal/length and a tagged final record. File operations stage protected output and publish atomically only after validation; secure randomness and I/O errors fail the operation. Buffered writes and legacy readers remain, with stricter framing and allocation limits. Existing libraries are not automatically rewritten.

This is an extension of the inherited implementation, not acceptance of a long-term portable format. ADR-001 still prohibits automatic conversion/storage replacement and ADR-002 remains proposed. V1 ordering/omission weaknesses, whole-file substitution/rollback, metadata leakage and cold recovery remain open. Older builds cannot read new v2 streams. See [the format, tests and limits](stream-integrity.md) before changing storage or downgrading a test installation.

## ADR-010 — Commit owner credentials together and preserve existing recovery material

**Status: accepted bounded hardening for development.** Owners: D2S-111/116, audit A05/A09. Setup and explicit password changes use one authenticated, namespace-bound owner credential record. Prepare it before the Keychain mutation; retain the existing media/album data key. Do not delete-and-add when updating an existing Keychain item. Once a current record exists, do not fall back to stale legacy credentials. Retry obsolete-entry cleanup only after successful current-record authentication.

Legacy login remains read-only. A missing preferences marker, inaccessible Keychain, corrupt record or partial credential set must never trigger automatic deletion or permission to overwrite existing credentials. New owner records require build 24 or newer; document the downgrade restriction. This does not establish independent recovery or rewrite media. See [credential, storage and cache hardening](credential-and-cache-hardening.md).

## ADR-011 — Keep the Cryptomator feasibility executable outside the app

**Status: accepted experiment boundary; format adoption remains proposed.** The [isolated pinned probe](../../spikes/cryptomator/README.md) operates only on generated disposable data. It adds no dependency to the Xcode app and performs no live conversion. The library tests and key-file fixture restore are promising evidence, but an unmodified desktop client has not validated the candidate layout. The observed acceptance of a whole final-chunk removal requires an authenticated completeness design and an explicit statement of desktop-reader limits. Album key domains and licensing/distribution also remain open. See [the initial feasibility report](cryptomator-feasibility.md); none of this accepts ADR-002 or authorizes migration.

## ADR-012 — Bind import commits to the originating owner session

**Status: accepted bounded reliability/security hardening.** Owners: D2S-116/117, audit A06/A08. Require an owner context/session before importing and revalidate the operation generation and session identity after awaits. Share one database commit path for ordinary and encrypted-file imports. Emit success only after save; stale results cannot reset a newer run. On failure, remove only newly produced outputs verified absent from committed database state; preserve files on uncertain outcomes. Cancellation discards service-owned batches, while ordinary per-item failures retain successful siblings. This does not provide a durable import journal or permit deleting unknown startup files. See [import lifecycle](import-lifecycle.md).

## ADR-013 — Remove inherited VIP monetization from the app

**Status: accepted; explicitly requested by the owner on 2026-10-17.** Build 26 removes the inherited purchase manager, StoreKit product/configuration, entitlement preferences, import-limit alerts, audio-sharing/export gates and paid-icon badges/upgrade flows. All alternate icons and audio export are available under their existing authentication/owner checks. Old entitlement preferences are ignored; no credential, media, album, key or library migration is required. Localized disclosures no longer describe purchase traffic.

This implements the fork's unrestricted offline-use requirement. It does not decide release pricing or distribution: ADR-005's initial free launch and later one-time price remain proposals subject to review. Historical upstream docs and the source requirements snapshot retain their provenance; they do not describe the current fork's purchase behavior.

## ADR-014 — English-only beta identity without changing vault identity

**Status: accepted by the owner on 2026-10-18.** The initial friend beta uses English-only app resources and date presentation, Latin `Vaultito` product/executable labels, and no purchase restrictions. Preserve installed bundle/signing/Keychain/schema/path identities and Unicode user data. Retain original license/copyright/trademark documents and archived translations outside app resources. Remove sensitive inherited diagnostic prints; translate source comments incrementally with review instead of deleting meaning. See [beta readiness](beta-readiness.md) for remaining comment, security, asset and distribution gates. This permits local build/test preparation, not a license conclusion, storage conversion or public beta upload.

## ADR-015 — Same-login secondary passcode for a truly separate vault

**Status: accepted user requirement (2026-10-18); storage/session design proposed, not shipped.** Prioritize D2S-115: a second passcode opens an independent populated vault with no ordinary-UI disclosure of the primary vault. Require separate keys, indexes, storage and context-scoped services/settings. The inherited Guest Mode is not a security boundary. Preserve existing primary data; do not substitute visibility filters or silently convert storage. Passcode-first biometric routing is proposed pending review. See [the concrete design and acceptance matrix](secondary-vault-design.md). This makes no forensic-deniability/coercion-safety guarantee and does not accept Cryptomator adoption.

## ADR-016 — Validate vault separation in a test-only experiment first

**Status: accepted experiment boundary (owner authorization 2026-10-19); production adoption pending.** Build the first context/key/index/storage prototype only in the test bundle with explicit disposable roots. Reuse the existing checked buffered encryption API; use independent random data secrets and authenticated store/vault/purpose/asset identities. No app authentication, Keychain, SwiftData, current storage adapter, library conversion or Cryptomator dependency is connected. A successful isolated reopen is not a device-loss recovery certification. See [implementation, validation and limits](vault-isolation-prototype.md). Encrypted-index scalability, legacy-primary transition, journaling, biometrics and cross-service integration remain separate gates.


## 2026-10-20 — WagLock branding and stable installed identity

Accepted: the owner selected **WagLock — All wag. No tell.** Rename active source/project/scheme/module/product labels while retaining `com.d2sci.vaultito.dev`, credential accounts and legacy cleanup/read aliases. The pre-rename synthetic SwiftData fixture opens under WagLock; this is compatibility evidence rather than a new storage design. Keep original license/copyright and upstream attribution in bundled Open Source Notices. See [build 28 branding and thumbnails](waglock-branding-and-thumbnails.md).


## ADR-017 — Mount legacy libraries only inside an authenticated session

**Status: bounded production session hardening for build 29; independent-vault storage design remains proposed.** The owner configuration/schema/URL/keys remain unchanged. Mount the persistent legacy index only for authenticated owner sessions; use an empty in-memory schema for presentation-only Guest Mode. Revalidate authorization and operation generations before publishing asynchronous authentication or mount results. Fail closed on mount errors, with no reset or fallback persistent library. The [metadata transition rehearsal](authenticated-library-boundary.md) stays in the test target. No legacy conversion, new production storage format, Cryptomator adoption or true alternative-passcode feature is enabled by this decision.


## ADR-018 — Explicit Face ID assignment with disclosure warning

**Status: user requirement accepted 2026-10-21; independent-vault routing pending.** The owner selected optional Face ID assignable to either vault, rather than disabling it when a secondary passcode exists. One app-level target is explicitly assigned at a time. Show a popup before enabling/reassigning, explaining that Face ID opens the assigned vault and cannot infer the user's intended vault under questioning. Album Face ID remains within its selected domain. Build 29 adds the warning to existing-vault enrollment and validates authorization before biometric Keychain writes. It does not provision a second domain or claim that cross-vault biometric routing is implemented. See [the accepted routing requirements](secondary-vault-design.md#face-id-and-album-policies).

## ADR-019 — Bind legacy exports to their originating authenticated session

**Status: implemented in build 32; device acceptance pending.** Give each export a separate protected output directory, immutable metadata snapshot and per-operation revocation. Only owner authentication activates the legacy exporter. Reject stale results and foreign paths, preserve original ciphertext, and retry cleanup only for known revoked outputs. A system-share callback cannot remove another job’s files. This incremental service boundary supports D2S-115/116 but does not provision a second vault or approve any storage migration. [Design and evidence](export-session-boundary.md).


## ADR-020 — Shared albums permit at most 24 hours offline

**Status: accepted product policy (2026-10-22); protocol and implementation pending.** The owner chose up to 24 hours offline after online authorization verifies both participants’ consent. Never renew offline. Recheck consent on connection; known withdrawal stops honest-client access immediately. Expiry or uncertain freshness requires a new online check. This cannot revoke retained keys/plaintext or external copies. Clock rollback, restart, replay and backup restoration need validation before shipping. See [the shared-album brief](shared-albums.md). No networking, protocol library or cloud purchase is selected by this policy.

## ADR-021 — Prioritize independently usable encrypted export and nested password boundaries

**Status: accepted product priorities (2026-10-22); format/transition design pending.** Export a complete encrypted vault in a documented format with tested instructions for an independent open-source tool. Prefer native/export alignment where feasibility supports it. Preserve distinct password boundaries for nested albums/subdirectories through export and recovery; the main password cannot silently become a universal child key. Device-bound biometric-only content needs an explicit reviewed path or blocker. Current format/readers remain intact; Cryptomator is a proposal. D2S-114/110 and D2S-141 are High and precede new sharing/camera work. See [requirements](requirements.md) and [sequence](backlog-priorities.md).

## ADR-022 — Prove portable export and nested password domains before app integration

**Status: implemented isolated experiment; production format and transition remain proposed (2026-10-22).** Owner authorized implementation when ready. A format-8 writer now produces synthetic nested vaults on macOS and the iOS simulator; independent recovery uses the unmodified official CLI and a bounded encrypted-manifest verifier. Separate passwords and recovered byte hashes passed; missing/tampered/truncated recovery is rejected. Standard-client reads alone still accept valid whole-chunk-truncated prefixes, unlike current ZNSC v2 completeness. No library/native conversion or phone export is enabled. Resolve the production integrity contract, licensing/distribution, full-library capture, password/biometric-only recovery and failure/scale gates before integration. See [the concrete design and results](portable-export-design.md).

## Read-only export snapshot boundary — 2026-10-22

**Implemented groundwork within ADR-001; format adoption remains proposed.** D2S-114/110/116/141. Capture supported persisted content only under the active owner mount/capability, reject unsupported models/fields and unavailable content, and keep password domains separate in the plan. Require explicit portable recovery design for Face ID-only content. Return immutable in-memory values without keys, model references, plaintext files or automatic store mutation. [Snapshot contract and limits](portable-export-snapshot.md). This accepts no production backup format, dependency, credential weakening or migration.

## ADR-023 — Additional age backup with native Files destinations

**Status: accepted implementation under the owner's 2026-10-22 instruction; native replacement remains unapproved.** Build 39 adds standard age-encrypted tar exports with password/scrypt or X25519-recipient choices, independent nested password archives, complete supported-content manifests and explicit Face ID-only copy consent/new export passwords. Use the iOS system export picker for manual on-device/iCloud/installed-provider copying of finished ciphertext. Preserve native readers, credentials, policy and source data. The BSD-2-Clause scrypt core is pinned with verbatim notices and hashes; no Cryptomator app dependency is added. Independent official age CLI recovery and parent-only credential rejection are validation requirements. Provider upload completion, app restore, native metadata encryption, broad platform/scale validation and inherited GPL/App Store/TestFlight review remain distinct gates. [Design](age-backup-design.md), [recovery](backup-recovery.md).


## ADR-024 — Rehearse a mutable encrypted metadata index before live migration

**Status: implemented unused candidate; production activation remains proposed (2026-10-22).** Use SQLite as a ciphertext transaction engine with CryptoKit AEAD, domain-bound opaque tokens and authenticated bucket inventories. No third-party dependency, automatic conversion, original rewrite or credential change. Require full inventory verification and typed source-fidelity/rollback evidence before activation; whole-copy rollback protection and safe source retirement remain unresolved. A01 stays open while the phone uses plaintext SwiftData. See [candidate contract, evidence and transition gates](encrypted-metadata-candidate.md).


### ADR-024 implementation follow-up — typed models and encrypted resume progress

Versioned adapters now preserve all three current SwiftData models into an unused memory-only projection. Staging binds a declared model-only scope and immutable source fingerprint to encrypted progress committed atomically with each batch; resume verifies the saved prefix and completed stages are idempotent. No live activation, default-root capture, source cleanup, credential/identifier change or approved native-format replacement. Draft/settings/every-writer/WAL coordination and reviewed recovery/rollback remain gates. [Contract and integration boundaries](encrypted-metadata-candidate.md#typed-model-adapter-and-resumable-staging).


## ADR-025 — Narrow first App Store submission, manual release

**Status: owner direction accepted 2026-10-22; readiness gates open.** Prepare a small initial store version while developing later improvements separately. First close inherited distribution/licensing, native sensitive-metadata protection, complete supported recovery and exact-release privacy/crypto/source validation. Shared albums, Trash, independent alternative vaults, encrypted search, self-destruct and unlock-camera capture remain later work. Prepare a separate opt-in `com.d2sci.waglock` store identity without changing the installed development identity or claiming a data transfer. Select manual release when an accepted candidate is submitted; no automatic publication or guaranteed review time. [Scope, evidence and gates](../release/submission-plan.md). No live storage migration or rights clearance follows from this scheduling decision.


### ADR-024 implementation follow-up — session-bound save gateway

Build 43 routes all explicit app model saves through a revocable mount lease and disables managed main-context autosave. Uncertain saves preserve potentially referenced ciphertext and biometric keys. An explicit-root model-only encrypted repository exercises this same boundary with durable-before-projection commits and reconciliation on uncertain outcomes. It remains unmounted and cannot read the complete staging scope. No live migration, root-key provisioning or source retirement is approved. [Contract, resource bounds and activation gates](library-write-boundary.md).


## ADR-026 — Fresh encrypted first-release identity, preserve development library

**Status: implemented for fresh installs under the owner's October 23 instruction to finish; release acceptance pending.** Enable the authenticated encrypted metadata repository only in the explicit `com.d2sci.waglock` release configuration. Use new random data/root secrets, a create-only device identity anchor, exclusive recoverable bootstrap and a memory-only UI projection. Persist notes/drafts with models inside the encrypted index. Preserve existing Dev identity, credentials, plaintext store and readers; do not migrate, retire sources, reset or infer empty-state permission from errors. Hide presentation-only Guest Mode in the public candidate. Portable recovery is explicit age export, not a claim that native files plus the current password suffice. Whole-copy rollback, legacy migration and independent alternative vaults remain open. [Contract and evidence](fresh-encrypted-library.md).
