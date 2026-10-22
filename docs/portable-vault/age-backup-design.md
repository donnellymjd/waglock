# Additional age backup format — build 39

D2S-114/110/106/116/141; owner authorized full export work, cryptographic choices and on-device cloud destinations on 2026-10-22. This implements an additional portable backup, preserving the native library format, legacy readers, credentials and installed identity. Cryptomator remains a separate proposal and research probe. No live conversion is authorized by this decision.

## Format and options

| User choice | Key wrapping | Recovery requirement |
| --- | --- | --- |
| Password | Fresh 16-byte salt; scrypt N=262144, r=8, p=1 | That backup password |
| Age recovery key | Fresh ephemeral X25519 key; standard age recipient stanza | Matching separately held age private identity |
| Separately protected child | Independent password age archive inside its parent's archive | Each child's current password, or explicitly chosen Face ID-only export password |

The interoperable [age v1 format](https://c2sp.org/age@v1.1.0) fixes HKDF-SHA-256, HMAC-SHA-256 header authentication and ChaCha20-Poly1305 payload encryption. A fresh 16-byte random file key and 16-byte payload nonce are generated for every domain. Payloads use 64 KiB chunks with the required final-chunk flag; exact-chunk and empty payloads are covered. The format's 128-bit file-key entropy must not be marketed as 256-bit security merely because ChaCha uses a 256-bit derived key. Parameters/cipher are fixed rather than exposing unsupported cipher combinations. Public recipient input is checksum/canonical-padding checked.

Password derivation costs approximately 256 MiB per active KDF. Calls are serialized and parameter/length bounded. Cancellation is checked before/after a derivation and between payload chunks; the reference ROMix call itself cannot be interrupted. Production phone latency/memory-pressure behavior requires owner testing. Swift values and OS cryptographic APIs do not provide a complete secret-memory-erasure guarantee.

Each domain contains a streamed uncompressed USTAR archive, bounded size-only PAX extensions for large entries, encrypted `metadata.json` and a final encrypted `manifest.json`. All filesystem names are generated ASCII UUIDs. Original Unicode values remain byte-preserved metadata. The manifest enumerates the exact entries, lengths and SHA-256 digests; its metadata identifies child domains. No root-level manifest/name/key enumerates protected child contents. Each child has a fresh file key and its own password wrapper; neither root identity nor parent password wraps that child key. Equal protected parent/child passwords are rejected; siblings are independent keys even if users reused passwords.

## Read, write and lifecycle boundaries

`PortableExportSnapshotService` inventories all supported persisted fields under the active owner mount/session/capability and album revision. Unknown fields, hierarchy errors, inaccessible records/drafts or missing sources fail closed. Face ID-only capture defaults to denial; explicit per-album export consent plus real biometric authorization and a new separate export password permit a password-readable **copy**, without altering native wrappers/policy. `BackupPlanFactory` partitions immutable value metadata and supplies source keys only to the worker, never serialized into archives.

`BackupArchiveBuilder` creates an exclusive private job directory and streams each tar directly into `AgeFileWriter`. One protected temporary plaintext media file is decrypted at a time using the existing reader, read/hashed in chunks and removed before the next. Metadata stays in bounded memory. Native buffered ciphertext above 64 MiB is rejected rather than unboundedly decrypted; native ZNSC streams can exceed it. Disk preflight includes nested ciphertext copies, one plaintext asset and overhead. Runtime errors still fail/clean the job. Stat checks plus native authentication and final recapture guard consistency; this is not a cross-process transactional snapshot or a remedy for legacy v1 prefix acceptance.

Before ready publication, revalidate the **original** authorization, supported fields, drafts and source evidence. Require the private directory to contain only the final ciphertext, then publish the named output exclusively. Lock/background/logout/remount revoke preparation, including same-session resume; stale completions cannot publish or delete newer jobs. Cleanup retries only known-owned directories. Startup cleanup targets only the backup-job root, never a media orphan scan. Crash/power loss cleanup and filesystem deletion are not forensic erasure.

Preparation uses complete iOS file protection. Only after verification, final ciphertext and its directory are changed to complete-until-first-user-authentication to allow the [native export picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:)) to copy while locked. The picker receives only immutable encrypted output, as a copy. A provider success callback is not proof of cloud upload completion; user verification is required. No provider credential, network library, sync service, cloud purchase or automatic OS-library backup policy is added.

## Dependency and distribution inventory

CryptoKit, Security, CommonCrypto, Foundation and UIKit are Apple SDK components. The app implements the documented age envelope/stream, rather than linking a third-party age implementation. Its sole added cryptographic source component is the original Tarsnap scrypt reference core at commit `cbdef576b8d4640e86b208fa3f063d4ec449110a`, **BSD-2-Clause**. Files are verbatim, with hashes and original paths in [PROVENANCE](../../WagLock/Support/Scrypt/PROVENANCE.md); the adapter supplies Apple's PBKDF2-SHA256 and bounded failure propagation. Full copyright/terms are retained in source and bundled Open Source Notices. The [upstream license](https://github.com/Tarsnap/scrypt/blob/cbdef576b8d4640e86b208fa3f063d4ec449110a/COPYRIGHT) and [GNU compatibility guidance](https://www.gnu.org/licenses/license-list.html#FreeBSD) support this dependency choice; this is an engineering license inventory, not legal clearance.

The MIT-licensed official age CLI 1.3.2 is an independently downloaded test/recovery tool, **not bundled into iOS**. Recovery-helper code is this repository's GPL-covered source. No Cryptomator/AGPL/commercial library, CryptoSwift or AgePony implementation is linked. Cryptomator dependency/distribution questions therefore do not block this additional age export, but inherited GPL corresponding-source, branding and App Store/TestFlight distribution review remains open. No beta upload is authorized by a passing export test.

## Recovery evidence and outstanding gates

[Recovery instructions](backup-recovery.md) use the unmodified official age CLI and a stdlib-only helper. A bounded strict tar parser rejects links, traversal, duplicates and oversized metadata/PAX records; authenticated manifests, hashes, domain linkage and all nested credentials are checked before exclusive publication of a new private directory. Existing output entries are preserved. Complete recovery needs every protected domain; outer-only extraction is explicitly incomplete.

Machine-readable [validation results](backup-validation-results.json) record synthetic native-writer cold recovery, seven payload hashes, nested metadata/notes/drafts/Unicode, large-file recovery and envelope tampering/final-chunk truncation rejection. Full XCTest/UI and actual phone/provider outcomes are recorded separately in [device testing](device-testing.md). No real owner media was read or exported by development tools. macOS independent recovery is tested; Linux/Windows and broad device/library-scale validation remain open. No in-app restore wizard exists.

Native metadata encryption (A01), original device-key recovery (A02), independent alternative vault integration (A03), generic previews and overall security-audit/distribution acceptance remain separate work. Successful portable backup does not close them.
