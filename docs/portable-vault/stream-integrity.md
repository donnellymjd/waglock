# Stream integrity hardening — build 23

Owner: [D2S-116](https://linear.app/d2sci/issue/D2S-116), following finding A04 in [D2S-105](audits/D2S-105.md). Recorded 2026-10-17. This is bounded hardening of the inherited store. It does not adopt Cryptomator, establish desktop recovery, or authorize automatic library conversion.

## Problem and behavior

Three regression tests first reproduced acceptance of a missing stream terminator, reordered chunks, and an empty stream with the wrong password. The old reader could publish partial or reordered plaintext because individual GCM tags did not authenticate the stream structure.

New `encryptFile(inputURL:to:password:)` writes use ZNSC version 2. Every record authenticates the complete header, its ordinal and its ciphertext length. A tagged empty final record authenticates completion, including an empty file. Decryption rejects missing, duplicated, omitted, reordered, corrupted or trailing records before publishing the destination.

Both file writers and readers now write into a protected temporary sibling directory, synchronize and close the output, then publish through one same-filesystem rename. Failure or observed cancellation removes staging and preserves an existing destination. FileHandle read/write errors propagate. Startup cleanup removes recognized abandoned stage directories in the app's temporary and encrypted-media roots; album preview cleanup separately removes its temporary tree. A cancelled asynchronous preview request removes a late-produced temporary file before returning.

Staging is still plaintext during decryption. File protection and cleanup reduce exposure; this does not prove secure erasure, protection against an already compromised process, or complete crash/backup leakage prevention. A crash can leave staging until the next successful cleanup. File synchronization plus rename is not a tested guarantee against every power-loss scenario. Low-storage faults and real-device interruption/lock behavior remain manual validation work.

## Version 2 layout

All integers are unsigned, big endian. Header size: 28 bytes.

| Header field | Bytes | Value |
| --- | --- | --- |
| Magic | 4 | ASCII `ZNSC` |
| Version | 1 | `2` |
| Reserved | 1 | `0` |
| Chunk size in KiB | 2 | Writer clamps to 256–16384 KiB; default 4096 KiB |
| Salt | 16 | Checked system randomness |
| Nonce prefix | 4 | Checked system randomness |

Password derivation remains PBKDF2-HMAC-SHA256, 100,000 iterations, 32-byte output using the file salt. KDF benchmarking and the future portable format remain separate decisions.

Each record is `length[4] || nonce[12] || tag[16] || ciphertext[length]`. Starting at ordinal zero, the nonce is `prefix[4] || ordinal[8]`. AES-256-GCM additional authenticated data is `header[28] || ordinal[8] || length[4]`. The reader verifies the expected nonce as well as the tag. The ordinal increments for each data record; overflow fails. The final record has length zero and its own nonce/tag, followed immediately by EOF. The reader bounds payload allocation by the declared chunk size, capped at 16 MiB.

This uses CryptoKit's [authenticated sealing](https://developer.apple.com/documentation/cryptokit/aes/gcm/seal(_:using:nonce:authenticating:)) and [opening](https://developer.apple.com/documentation/cryptokit/aes/gcm/open(_:using:authenticating:)) APIs. Tests are implementation evidence, not independent cryptographic review.

## Compatibility and remaining boundaries

- The buffered `salt || nonce || tag || ciphertext` format is unchanged, including buffered writes. Empty buffered payloads now decrypt correctly.
- The ZNSC v1 reader remains. It now requires complete framing, a terminator and EOF, checks I/O failures, and bounds record allocations at 64 MiB. Historical app-default 4 MiB chunks remain supported. Unusual externally generated v1 records larger than that bound are rejected.
- **V1 cannot authenticate ordering, omissions with a retained terminator, or an empty file's password.** Strict framing does not retroactively add those properties. V2 checks apply only to v2 files; preserving legacy readers also means this is not an authenticated policy requiring every stored object to be v2.
- There is no external authenticated manifest binding a file to an asset ID, nor rollback or whole-file substitution detection. These require a broader vault/index design.
- Older app versions cannot read v2. Do not downgrade build 23 after importing new streamed media without retaining originals. Existing files are not rewritten on upgrade; no bulk conversion runs.
- Secure-random failures now stop EncryptionService operations. This does not resolve every random-generation call elsewhere, plaintext main-library thumbnails/notes, password-update recovery, or decoy isolation.

## Verification

On iPhone 17 / iOS 26.5 simulator, **65 unit tests passed**: 28 XCTest and 37 Swift Testing, including 14 stream-integrity tests. The original three regression tests failed before the fix and passed afterward. Coverage includes chunk boundaries and empty files, wrong passwords, header/payload tampering, short reads, oversized lengths, record order/duplication/omission, missing/trailing terminators, preserving an existing output after late authentication failure, failed publication, same-file protection, injected RNG failures, cancellation before writing, startup cleanup and independently encoded legacy fixtures.

The generic iOS development-signed build 23 passed. Existing asset/concurrency warnings remain. This change does not alter screens; the build 22 album UI test was not repeated. Hardware Face ID, live disk-full/power-loss faults, cancellation during an active large write and the wider D2S-116 acceptance work remain unverified.

Reproduce the unit run with an installed simulator identifier:

```sh
xcodebuild test -project ZeroNet-Space.xcodeproj -scheme ZeroNet-Space \
  -destination 'platform=iOS Simulator,id=42099BD8-B583-41F9-BF53-A4CCEB71872E' \
  -derivedDataPath /private/tmp/vaultito-integrity-tests \
  -only-testing:ZeroNet-SpaceTests -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

Ephemeral local evidence: `/private/tmp/vaultito-integrity-before.log`, `/private/tmp/vaultito-integrity-before.xcresult`, `/private/tmp/vaultito-integrity-final.log`, `/private/tmp/vaultito-integrity-final.xcresult`, `/private/tmp/vaultito-integrity-device.log`. These paths are not checked-in recovery artifacts.
