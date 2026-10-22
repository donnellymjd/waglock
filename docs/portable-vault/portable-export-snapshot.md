# Complete-library snapshot groundwork — 2026-10-22

D2S-114/110/116/141. `PortableExportSnapshotService` is implemented in the app target and exercised only with disposable fixtures. The build 39 [age backup writer/UI](age-backup-design.md) now consumes it. Capture itself remains read-only and creates no archive, plaintext directory or schema migration. The original 196-test evidence below records the preceding snapshot-only increment.

## Capture contract

Capture requires the active legacy-owner mount, matching authentication session and revocable owner capability, plus a live owner authorization check. Guest mounts are rejected even if supplied with an owner session UUID. Dirty contexts are rejected rather than saved, rolled back or reset. Schema entities and persisted field names must match the explicit supported inventory. This prevents a future persisted property or Trash model from being silently omitted.

The synchronous MainActor capture copies values into immutable records. Background work never receives SwiftData model references. It does not cache snapshots internally, unlock albums, prompt for biometrics, return keys or decrypt media originals. Missing/corrupt/inaccessible content stops capture; no partial snapshot is returned. Storage/decoder failures are reduced to typed errors without source-path text.

| Source | Captured values | Export domain |
| --- | --- | --- |
| `MediaItem` | Stable ID, name/extension, stored and effective type, declared size, thumbnail, creation/modification dates, dimensions/duration and checked ciphertext source reference | Root |
| `SecretNote` | Stable ID, title/body, dates, favorite/pinned flag and tags | Root |
| Keychain note draft | Title/body/date, with explicit origin | Root |
| Legacy preferences draft | Preserved separately, even when a Keychain draft also exists; no migration/deletion | Root |
| `VaultAlbum` | Stable ID, parent ID, name, protection mode and creation date | Nearest independent password domain, including its own |
| Authenticated album catalog | Every current `AlbumAsset` field, including original name, type, size, thumbnail and date; unsupported JSON fields reject capture | Album's domain |

Current album assets do not store separate modification times, dimensions or duration; capture does not invent them. Device-only biometric accounts, existing wrapped keys and physical source paths are not portable recovery records. The source reference is local job input, not an archive filename. No exporter should serialize this entire cross-domain snapshot or place it in logs/temporary plaintext.

## Nested protection

Each password or password-or-Face-ID album starts an independent planned export domain. Inherited descendants belong to the nearest protected ancestor, or root. Root and parent domains receive only opaque child-domain references; child names, catalogs and content remain in the child's records. Validate the whole hierarchy before reading catalogs: unknown policies, missing parents, cycles, duplicate IDs and inaccessible ancestors fail closed.

All albums must already be accessible through the installed policies. A locked album blocks the complete snapshot instead of disappearing from it. Even an unlocked Face ID-only album blocks capture with `biometricRecoveryRequired` by default. Build 39 permits only an explicit set of approved Face ID-only IDs, bound to the snapshot token; the caller must obtain per-album consent, actual biometric authorization and a new confirmed export password. This creates an independent password-readable backup copy without changing native protection. An unlocked password-backed album does not supply its original password: the writer must explicitly collect/verify each required export credential and encrypt domains independently. This partition is a plan, not cryptographic isolation of the returned in-memory values.

## Consistency and resource checks

Snapshot authorization binds collector, mount identity, owner session, capability revision and album revision. Revocation remains effective when background/resume retains the same session UUID. A different collector, relocked album or remounted store cannot reuse an old snapshot. A future asynchronous writer must validate the original authorization after awaits rather than refreshing it.

Before future publication, `validateUnchanged` recaptures and compares all supported metadata, both draft stores and ciphertext stat evidence. This detects tested changes even if a model's modification date was not updated. Text comparisons check exact UTF-8 bytes: Swift's default equality would treat NFC/NFD spellings as equal. A targeted regression reproduced five missed changes in names, note content/tags and drafts before the comparison was corrected. Names and content are never normalized by capture. Source references must be regular files directly inside the configured media root; missing files, foreign files, root/leaf symlinks and traversal are rejected. Capture never deletes/rewrites these sources.

The metadata payload estimate defaults to 64 MiB, counting UTF-8 strings, thumbnail bytes and fixed per-record allowances. Draft decoding also has a 64 MiB per-entry guard. This is a technical snapshot guard, not an import/paywall limit or proof of bounded process memory: initial SwiftData fetches, catalog decoding and model overhead still require large-library measurement/paging. Current-model unknown types, invalid sizes/dates and malformed or inaccessible drafts fail closed. Checked Keychain reads distinguish item-not-found from interaction/storage errors; the existing editor's optional-read API remains unchanged.

## Validation

Fifteen new XCTest cases cover all media kinds, notes/drafts and nested password domains; real encrypted catalogs/wrappers; inherited descendants; snapshot independence from live models; byte-exact Unicode spelling changes; unchanged modification dates; owner/Guest/background/remount boundaries; collector identity; cancellation; album relocking; unlocked Face ID-only blocking; malformed hierarchy/policies/catalogs; unknown authenticated catalog fields; missing/foreign/symlink sources; metadata budgets; duplicate asset IDs; unsupported schemas; revocation during draft reads; and failure-preserving reads of both draft stores.

Final full suite: **196 passed** (85 XCTest + 111 Swift Testing), including all 15 snapshot cases. Result: `/private/tmp/waglock-export-snapshot-final-verification.xcresult`; log: `/private/tmp/waglock-export-snapshot-final-verification.log`. The preceding Unicode regression reproduced five missed changes before the correction (`/private/tmp/waglock-export-snapshot-unicode-repro.xcresult`). Signed-device compilation also passed (`/private/tmp/waglock-export-snapshot-device-final-verification.log`). No UI caller was added, so no new UI/hardware behavior or phone acceptance is claimed. Tests use only temporary synthetic files, in-memory SwiftData, injected Keychain storage and a private UserDefaults suite. No owner media, credentials or defaults were inspected.

## Remaining implementation gates

This captures persisted content at a local consistency point. It is not a transactional WAL/file snapshot across processes. Pending editor keystrokes, active recordings and in-flight imports need explicit UI coordination; device settings are explicitly marked not captured. Trash is explicitly marked not implemented. Future settings/Trash handling must be specified and tested before a complete-backup claim.

Build 39 implements per-domain age metadata encryption, explicit credentials, source/stat and final recapture checks, content hashes, bounded streaming for supported sources, cancellation/low-space handling and independent macOS recovery. See the [implemented contract and remaining limits](age-backup-design.md), including the 64 MiB legacy-buffered-file guard and provider/platform acceptance. Inherited distribution clearance remains open. Stat evidence cannot detect a same-length in-place edit that also preserves timestamp/inode; it does not replace content authentication or prevent TOCTOU changes. Caller-retained plaintext metadata cannot be erased by later capability revocation. No live conversion, alternative vault, forensic erasure or complete security-audit claim follows from this service.
