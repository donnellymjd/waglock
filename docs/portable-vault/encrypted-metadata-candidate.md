# Mutable encrypted metadata candidate

D2S-105/116/115/141 — 2026-10-22. This is implementation groundwork, **not an activated migration or remediation of A01 on the phone**. `EncryptedMetadataStore` has no production mount/login caller. The installed build 40 retains its existing SwiftData library, originals and credentials.

## Storage contract

Use Apple's SQLite and CryptoKit, without a new third-party dependency. The caller supplies a separate root, library/vault UUIDs and 32-byte key. HKDF-SHA256 derives separate AES-GCM and HMAC keys, bound to that domain. SQLite receives only opaque HMAC(kind, record UUID) tokens and authenticated ciphertext. Names, dates, notes, thumbnail bytes, retained key records and model payloads belong inside encrypted records. No native credentials are collected by this candidate.

Each record authenticates its format, library, vault, purpose and token. An encrypted head binds a revision, record count and hashes of 256 encrypted bucket manifests; manifests bind tokens to ciphertext hashes. Updates authenticate existing records before replacement. A transaction changes only affected records, buckets and the head. Reads page at most 128 records and 32 MiB of encoded ciphertext; raw payloads are capped below 12 MiB, encoded records at 16 MiB. Oversized metadata fails rather than being omitted. Current ordering is opaque token order, not title/date search.

`BEGIN IMMEDIATE` serializes writes; expected revisions reject stale callers. Revocation invalidates capabilities and key references; active transactions roll back before closing their connection. Precommit failure rolls back. Failure after a commit attempt revokes the instance and reports an uncertain result: reopen and reconcile, never infer permission to delete originals. DELETE journaling, FULL synchronous writes, fullfsync, in-memory temporary storage and disabled memory mapping are configured. Root/file creation is exclusive, with restrictive permissions and complete iOS file protection. Existing roots, symlinks and unrecognized schemas fail closed. Only known OS path aliases are expanded; every path component is checked for symlinks before the canonical file is passed to SQLite's NOFOLLOW open mode.

The [SQLite atomic commit description](https://www.sqlite.org/atomiccommit.html) describes the transaction assumptions. [CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm) provides the authenticated encryption primitive. These references do not establish an independent audit of this composition.

## Evidence and limits

- Initial index-only full simulator regression: 221 tests passed (110 XCTest and 111 Swift Testing), including 14 candidate tests. Signed iOS compilation also passed. Coverage includes wrong key/domain, revocation, stale handles, Unicode payload fidelity, 1,000-record paging, corruption/substitution/deletion, schema/path rejection, precommit failure and uncertain commits.
- Synthetic legacy capture round-trips every current media/note/album field plus a synthetic retained-key record, preserving exact payload bytes and leaving source objects unchanged. Canonical JSON ordering makes repeat captures comparable. This is a test adapter, not a production WAL snapshot or migration bridge.
- Database and active rollback-journal scans check for public synthetic plaintext and its base64 form. This is evidence for those fixtures, not proof against every possible leak.
- `spikes/encrypted-metadata/run.py` compiles the same store on macOS and terminates a separate process immediately before/after commit. Reopen must recover the old/new complete revision respectively. This does not simulate power failure mid-fsync or certify hardware durability.
- Opening authenticates the head and checks row counts; pages authenticate their records/buckets. `verifyAll` verifies the entire ciphertext inventory before accepting a staged transition. It does not decode every payload's schema.
- Whole-database rollback to an authentic older copy is not detected. An external trusted freshness strategy remains open. SQLite page allocation, row counts, ciphertext sizes and update patterns remain visible. This is not forensic plausible deniability.
- Caller-owned decoded values cannot be recalled or guaranteed zeroized. Sequential path validation does not prove resistance to malicious concurrent filesystem replacement. The implementation runs on MainActor; large-library responsiveness, memory peaks and migration scheduling require measurement. Fault hooks model storage failure; actual filesystem-full and power-loss tests remain open.

## Typed model adapter and resumable staging

`MetadataModelCodec` now captures every current stored field of MediaItem, SecretNote and VaultAlbum into versioned canonical payloads. It requires a clean context, an exact entity/property inventory and caller authorization. Count preflight and 128-model enumeration batches avoid first fetching every source object. The encoded snapshot is still buffered, with a 20,000-record/64-MiB ceiling. Unknown fields, envelope versions, kinds and identity mismatches fail rather than being silently dropped. Raw future media/policy values are preserved as data; preserving them does not authorize treating an unknown policy as unprotected.

The inverse adapter creates only its own **memory-only** SwiftData projection. It preserves IDs, raw UTF-8 text, timestamps, thumbnail bytes, optional fields, hierarchy references, biometric account strings, wrapped keys and encrypted catalogs. It never restores into a persistent source or follows an original-media path. The projection is not connected to the UI and has no encrypted write bridge yet. Caller-held projections are not automatically revoked or zeroized.

`MetadataTransitionStage` requires an explicit new-root/create or existing-root/resume choice, source ID, immutable records, domain, key and authorization check. An encrypted `transition` record binds a version, explicit model-only scope, SHA-256 source fingerprint, count, completed prefix, phase and commit revision. Up to 127 source rows plus the next progress record commit in the same SQLite transaction. There is no plaintext progress file. One explicitly supplied retained legacy-secret record is supported; the service does not read credentials or unwrap album keys.

Before resuming, it authenticates the inventory and compares **every saved row's exact payload** to the same source prefix and progress record. A changed source, foreign key/domain, edited prefix, stale revision, duplicate input or occupied create root fails closed. A completed stage can be reopened and verified without another write. Errors/revocation preserve already committed progress. A failure after the verified marker leaves a reconcilable copy rather than deleting it. An interrupted, uninitialized root is rejected on resume; there is no automatic reset, unknown-root cleanup, directory publication or mount-pointer change.

The `verified` phase means these supplied model records match the staged inventory. **It does not mean complete-library recovery, safe activation or a completed migration.** Drafts, preferences/settings, active credentials/biometric enrollment, streamed original validation and all-writer quiescence still require separate adapters and policy. Neither service has a production mount/login caller.

### Staging validation

The full regression with typed adapters/resume passed **230 tests** (119 XCTest plus 111 Swift Testing). After adding the disk-backed WAL case, all **10 staging tests** passed. Signed generic-iOS compilation passed. The standalone macOS index crash probe also passed again before/after commit.

The staged 261-record fixture includes a retained synthetic secret. Tests interrupt after a committed batch, reopen, reject a changed source/foreign domain/key, verify the exact saved prefix, finish and reopen idempotently. Edited stages fail instead of being overwritten. Revocation and a lost completion result preserve recoverable progress. Model round-trip tests include raw future type/policy values, optional metadata, binary wrappers/catalogs, distinct Unicode encodings and timestamps. Fixture plaintext/raw base64 markers are absent from the stage files.

The WAL case uses an already-open, quiescent **disposable** persistent ModelContext. It establishes that the note marker is present in committed WAL but absent from the main SQLite file; capture sees it, and source SQLite/WAL bytes are identical after encrypted staging. No plaintext clone, checkpoint or journal-mode change occurs. This does not establish a coordinated snapshot against other active writers, nor prove read-only reopening of an arbitrary external WAL database. Actual filesystem-full, abrupt process death during a multi-batch source transition, source-freeze/activation interruption and hardware power-loss tests remain open. The existing process probe covers the underlying index transaction boundaries, not the complete staging coordinator.

### Next integration boundaries

| Boundary | Required behavior before activation |
| --- | --- |
| ImportViewModel/import services | Commit metadata through the originating revocable repository; retain committed media on uncertain outcomes. |
| AlbumStore | Route every hierarchy, policy, wrapper and encrypted-catalog change through the same domain transaction; preserve separate password boundaries. |
| SecretSpaceView/draft manager | Coordinate note edits/deletion/autosaves and both existing draft stores; never overwrite or silently omit one draft source. |
| Gallery/Photos/Videos/Files/Audio/detail views | Replace direct save/delete/rename paths; do not remove ciphertext before durable metadata reconciliation. |
| Mount/export/preview services | Mount a verified generation only; make decoded values revocable at consumer boundaries; adapt export capture without changing its supported-content contract. |
| Activation and recovery | Define the key wrapper, source freeze/WAL strategy, pointer publication/reconciliation, rollback and explicit plaintext-source retirement. |

The model-only scope is intentionally recorded inside the progress record so a future complete-library migrator cannot mistake this rehearsal for a finished source capture. Live-source coordination and the review gates below remain required.

## Required transition before live use

1. Integrate the typed model adapters and finish draft, setting, key-wrapper and export-reader adapters. Route all saves/autosaves through the revocable library context. Prove independent album/top-level key domains; encrypting a shared owner index alone does not implement an independent alternative vault.
2. Quiesce writers and capture a consistent supported-schema source including WAL state. No plaintext clone, journal-mode mutation or cleanup of a live source is authorized by these tests.
3. Stage in a separate owned root; checkpoint/resume safely, verify inventory plus decoded field equality, retain originals/keys, and test interrupted creation, disk exhaustion and incompatible versions. Publish a mount pointer only after verification. Define rollback and uncertain-activation reconciliation.
4. Verify complete independent backup recovery with the correct separate album passwords and readable photos/videos, including the owner's build 40 acceptance. Prove fresh-device/cold restore and source-compatible rollback with disposable data first.
5. Review the concrete activation procedure before changing the live library. Retaining plaintext SwiftData as rollback leaves A01 open; source retirement needs an explicit later decision and verified recovery. Deleting SQLite/WAL files does not prove forensic erasure.

Cryptomator remains a proposal. This index does not change native original encryption or the independent age export format. No phone conversion, data deletion, credential reset or beta security approval occurred.
