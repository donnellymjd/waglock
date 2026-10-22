# Isolated Cryptomator feasibility probe

Research for D2S-107/109/110; **not an iOS app dependency or an accepted storage replacement**. Uses cryptolib-swift 2.0.0 at revision `b339c9ba84f7737377ef187a78900f9cc384cb12`. Requires Swift 6.2+ on macOS. Package.resolved pins Base32 as well. Read [the findings and gates](../../docs/portable-vault/cryptomator-feasibility.md).

Run from the repository root with a **new, nonexistent disposable output directory**:

```sh
swift run --package-path spikes/cryptomator \
  --scratch-path /private/tmp/vaultito-portability-spike-build \
  VaultitoCryptomatorSpike /private/tmp/vaultito-portability-fixture-NEW
```

The command refuses an existing output directory. It generates its own sample data and never reads Vaultito containers, Keychain or real media. The published fixture password is `Vaultito disposable fixture only`; it protects no private content. Outputs include a candidate format-8 SIV_GCM vault with `Trips/2026/sample.bin`, independent expected/recovered bytes, tampered/truncated copies and report.json. Plaintext fixtures intentionally remain outside the candidate-vault directory for comparison; this is not a production backup/export tool.

It checks library-level filename/content round-trips, unlocking from the on-disk wrapped key without Keychain, wrong-password rejection and payload corruption. It also records the negative result that removing a complete final content chunk is accepted as a valid prefix. A successful process exit does **not** mean the full security/compatibility gate passed.

Still required: independent desktop-client opening and hash comparison, iOS creation, long names, real photo/video fixtures, large-file memory/performance, failure/cancellation/disk-full staging, hardened untrusted key/config parsing and the broader platform matrix. It does not implement symlinks, long-name shortening, album-specific passwords/Face ID, authenticated library manifests, recovery UI or live-data migration. Do not use it on real vaults.

The upstream library is offered under AGPLv3 and an advertised commercial licensing route. This probe does not resolve the fork's distribution/license obligations or add the library to the app. Preserve upstream notices in fetched sources; see the pinned dependency's README and LICENSE.txt. No license purchase, outreach or distribution was performed.

## Nested export implementation experiment — 2026-10-22

`WagLockPortableExportFixture` now generates a separate nested password domain plus encrypted completeness manifests. macOS and iOS-simulator outputs both passed independent recovery with the unmodified official CLI. See [tested recovery commands](RECOVERY.md), [design/readiness gates](../../docs/portable-vault/portable-export-design.md) and [results](../../docs/portable-vault/portable-export-experiment-results.json). The older probe above still records the native whole-chunk-truncation limitation; the new verifier detects it through the manifest. Neither executable is linked to the phone app.
