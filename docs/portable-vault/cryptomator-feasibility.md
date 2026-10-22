# Cryptomator feasibility — initial isolated probe

**2026-10-22 update:** macOS and iOS-simulator nested-vault writers now pass independent official-CLI recovery and manifest-based completeness checks. See [implementation, evidence and remaining adoption gates](portable-export-design.md). The initial results below are historical; native standard-reader truncation acceptance remains confirmed. No production adoption or current-library conversion.

Recorded 2026-10-17 for [D2S-107](https://linear.app/d2sci/issue/D2S-107), [D2S-109](https://linear.app/d2sci/issue/D2S-109), [D2S-110](https://linear.app/d2sci/issue/D2S-110) and D2S-106. **Status: proposal under evaluation; not adopted.** No live app dependency, encrypted-file conversion, Keychain export, File Provider integration or distribution change was made.

## Pinned candidate and executed checks

[cryptolib-swift 2.0.0](https://github.com/cryptomator/cryptolib-swift/tree/b339c9ba84f7737377ef187a78900f9cc384cb12) resolves to commit `b339c9ba84f7737377ef187a78900f9cc384cb12`. Its manifest uses Swift tools/language 6.2/6, iOS 13 and macOS 10.15. The current develop branch has different minimum platforms; this probe uses the pinned release rather than assuming the branch README describes that release. The app itself remains Swift language mode 5.

Ran the unmodified upstream library's macOS unit suite: **79 XCTest tests passed**. Separately built and ran [our isolated executable](../../spikes/cryptomator/README.md) using the same revision and Base32 0.9.0 (`c4bc0a49689999ae2c7c778f3830a6a6e694efb8`). A small generated fixture restored its original 65,573 bytes after the initial masterkey objects went out of scope, using the on-disk wrapped key and fixture password alone. Wrong passwords and payload-bit tampering were rejected. This is a library experiment, not a restore of the current Vaultito store.

The probe constructs a candidate format-8 SIV_GCM directory with a signed vault configuration, wrapped key file and two nested directories using the published [architecture](https://docs.cryptomator.org/security/architecture/) and [vault layout](https://docs.cryptomator.org/security/vault/). A separate unmodified desktop client has **not** opened it. The probe's own creation/readback cannot establish desktop compatibility. No Cryptomator application was found under this Mac's `/Applications` during the check; no desktop software was installed.

Local disposable output: `/private/tmp/vaultito-portability-fixture-01`; report copied to [cryptomator-spike-results.json](cryptomator-spike-results.json). Expected cleartext path: `Trips/2026/sample.bin`; SHA-256: `f0da11e9bdac0f5804d9d10698fa4a9d16f1030180a4154cd82083e576b0b5ac`. The published password is only for generated fixtures. Logs: `/private/tmp/vaultito-cryptolib-tests.log`, `/private/tmp/vaultito-portability-spike.log`. Sources and commands are in the spike; local logs/artifacts are ephemeral.

## Security and orchestration findings

1. **Whole-file completeness needs an additional design.** In the pinned SIV_GCM library, removing the final complete ciphertext chunk from the fixture returned the first 65,536 plaintext bytes successfully. This is an observed negative result, not a claim that payload authentication failed: the remaining chunks are individually authentic. Build 23 ZNSC v2 uses a tagged final record, so adopting the candidate without additional measures would weaken the app's current completeness check. An authenticated length/hash catalog could check app reads and recovery verification, but an unmodified desktop reader would not automatically enforce that app-specific catalog. Record and review that limitation before adoption; do not silently call it equivalent integrity.
2. **The cryptographic library does not provide the complete vault filesystem.** Vault configuration validation, directory management, long-name shortening, album/index representation, transaction staging, cleanup and recovery orchestration still belong to the integration. The library's documented failure/cancellation behavior leaves partial outputs for its caller to remove. Retain protected atomic staging around any future integration.
3. **Untrusted key/config parsing needs bounds and validation.** Source inspection found a force-unwrapped Base64 salt in MasterkeyFile.deriveKey and caller-supplied scrypt parameters. A production adapter must reject malformed salts, unsupported formats/algorithms, unsafe key locations and excessive KDF parameters before reaching these APIs. The probe reads only its own generated fixtures; malformed external-input fuzzing was not performed.
4. **Album security is not plain folder organization.** Ordinary directories in one vault share its masterkey. The current separate album-password and device-bound Face ID-only domains cannot be represented by simply encrypting directory names. A nested/separate-vault design or an explicit recovery/UX change needs its own accepted decision and tests. Existing user-authorized Face ID-only loss limitations remain.

## Dependency and licensing observations

The pinned upstream README advertises AGPLv3 for FOSS and a separate commercial route; LICENSE.txt contains AGPLv3. Base32's license is MIT, and vendored scrypt sources carry their own notices. These are source inventory observations. Terms, upstream-fork compatibility, App Store/TestFlight distribution and any commercial agreement remain review gates under D2S-106. No conclusion of legal clearance, license purchase or request to the vendor was made.

## Evidence required before integration or conversion

| Gate | Current result / next evidence |
| --- | --- |
| Native library build | Pinned library and 79 upstream macOS tests pass; iOS adapter build/runtime remains untested. |
| Desktop interoperability | Candidate generated, not opened by an unmodified client. Test macOS first, then Windows/Linux; record versions and hashes. |
| Recovery | Fixture key-file restore works without Keychain. Real vault/index/album recovery, fresh-device restore and backup coverage remain unimplemented. |
| Integrity | Payload tampering rejected; complete final-chunk removal accepted. Resolve catalog/completeness contract before adopting. |
| Scale and failures | Only small binary fixture; real originals, large videos, memory limits, cancellation, disk-full and crash behavior remain to test. |
| Migration | No live conversion. Require separate destination, verification, resume and rollback while preserving source data. |
| Distribution | Licensing path and distribution review pending; no production dependency approved. |

Continue read-only research and disposable prototypes. A storage replacement, live migration or changed security/recovery promise requires a concrete accepted architectural decision after these gates; this experiment grants none.
