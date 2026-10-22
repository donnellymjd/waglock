# Mutable encrypted metadata candidate

D2S-105/116/115/141 — 2026-10-22. This is implementation groundwork, **not an activated migration or remediation of A01 on the phone**. `EncryptedMetadataStore` has no production mount/login caller. The installed build 40 retains its existing SwiftData library, originals and credentials.

## Storage contract

Use Apple's SQLite and CryptoKit, without a new third-party dependency. The caller supplies a separate root, library/vault UUIDs and 32-byte key. HKDF-SHA256 derives separate AES-GCM and HMAC keys, bound to that domain. SQLite receives only opaque HMAC(kind, record UUID) tokens and authenticated ciphertext. Names, dates, notes, thumbnail bytes, retained key records and model payloads belong inside encrypted records. No native credentials are collected by this candidate.

Each record authenticates its format, library, vault, purpose and token. An encrypted head binds a revision, record count and hashes of 256 encrypted bucket manifests; manifests bind tokens to ciphertext hashes. Updates authenticate existing records before replacement. A transaction changes only affected records, buckets and the head. Reads page at most 128 records and 32 MiB of encoded ciphertext; raw payloads are capped below 12 MiB, encoded records at 16 MiB. Oversized metadata fails rather than being omitted. Current ordering is opaque token order, not title/date search.

`BEGIN IMMEDIATE` serializes writes; expected revisions reject stale callers. Revocation invalidates capabilities and key references; active transactions roll back before closing their connection. Precommit failure rolls back. Failure after a commit attempt revokes the instance and reports an uncertain result: reopen and reconcile, never infer permission to delete originals. DELETE journaling, FULL synchronous writes, fullfsync, in-memory temporary storage and disabled memory mapping are configured. Root/file creation is exclusive, with restrictive permissions and complete iOS file protection. Existing roots, symlinks and unrecognized schemas fail closed. Only known OS path aliases are expanded; every path component is checked for symlinks before the canonical file is passed to SQLite's NOFOLLOW open mode.

The [SQLite atomic commit description](https://www.sqlite.org/atomiccommit.html) describes the transaction assumptions. [CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm) provides the authenticated encryption primitive. These references do not establish an independent audit of this composition.

## Evidence and limits

- Final full simulator regression: 221 tests passed (110 XCTest and 111 Swift Testing), including 14 candidate tests. Signed iOS compilation also passed. Coverage includes wrong key/domain, revocation, stale handles, Unicode payload fidelity, 1,000-record paging, corruption/substitution/deletion, schema/path rejection, precommit failure and uncertain commits.
- Synthetic legacy capture round-trips every current media/note/album field plus a synthetic retained-key record, preserving exact payload bytes and leaving source objects unchanged. Canonical JSON ordering makes repeat captures comparable. This is a test adapter, not a production WAL snapshot or migration bridge.
- Database and active rollback-journal scans check for public synthetic plaintext and its base64 form. This is evidence for those fixtures, not proof against every possible leak.
- `spikes/encrypted-metadata/run.py` compiles the same store on macOS and terminates a separate process immediately before/after commit. Reopen must recover the old/new complete revision respectively. This does not simulate power failure mid-fsync or certify hardware durability.
- Opening authenticates the head and checks row counts; pages authenticate their records/buckets. `verifyAll` verifies the entire ciphertext inventory before accepting a staged transition. It does not decode every payload's schema.
- Whole-database rollback to an authentic older copy is not detected. An external trusted freshness strategy remains open. SQLite page allocation, row counts, ciphertext sizes and update patterns remain visible. This is not forensic plausible deniability.
- Caller-owned decoded values cannot be recalled or guaranteed zeroized. Sequential path validation does not prove resistance to malicious concurrent filesystem replacement. The implementation runs on MainActor; large-library responsiveness, memory peaks and migration scheduling require measurement. Fault hooks model storage failure; actual filesystem-full and power-loss tests remain open.

## Required transition before live use

1. Finish typed adapters for every model, draft, setting, key wrapper and export reader. Route all saves/autosaves through the revocable library context. Prove independent album/top-level key domains; encrypting a shared owner index alone does not implement an independent alternative vault.
2. Quiesce writers and capture a consistent supported-schema source including WAL state. No plaintext clone, journal-mode mutation or cleanup of a live source is authorized by these tests.
3. Stage in a separate owned root; checkpoint/resume safely, verify inventory plus decoded field equality, retain originals/keys, and test interrupted creation, disk exhaustion and incompatible versions. Publish a mount pointer only after verification. Define rollback and uncertain-activation reconciliation.
4. Verify complete independent backup recovery with the correct separate album passwords and readable photos/videos, including the owner's build 40 acceptance. Prove fresh-device/cold restore and source-compatible rollback with disposable data first.
5. Review the concrete activation procedure before changing the live library. Retaining plaintext SwiftData as rollback leaves A01 open; source retirement needs an explicit later decision and verified recovery. Deleting SQLite/WAL files does not prove forensic erasure.

Cryptomator remains a proposal. This index does not change native original encryption or the independent age export format. No phone conversion, data deletion, credential reset or beta security approval occurred.
