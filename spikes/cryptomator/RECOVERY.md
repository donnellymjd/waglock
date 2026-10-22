# Reproduce independent recovery of the public export experiment

**Generated samples only. This cannot recover the existing WagLock phone library.** The experiment publishes its passwords because it contains no private data. Do not reuse them. No iOS application dependency, format migration, production backup or complete restore UI is enabled.

Prerequisites: macOS arm64, Xcode/Swift 6.2+, Python 3 and an independently downloaded official Cryptomator CLI. The tested CLI archive is [0.6.1 mac-arm64](https://github.com/cryptomator/cli/releases/download/0.6.1/cryptomator-cli-0.6.1-mac-arm64.zip), SHA-256 `9252f8765db5068931d78f1ee74f7fe4d653605bf691d30e05c119eb5fa5d0d3`. Its signature verified as Skymatic GmbH (`YZQJQUHA3L`). This is a pinned research version, not a recommendation to use an old client for real private libraries. Review current releases/dependencies before production use. No FUSE installation is needed for this experiment.

From the repository root, choose **new, nonexistent** fixture and recovery directories:

```sh
swift run --package-path spikes/cryptomator \
  --scratch-path /private/tmp/waglock-portability-build \
  WagLockPortableExportFixture /private/tmp/waglock-export-fixture-NEW

python3 tools/verify_portable_export.py \
  --cli /path/to/cryptomator-cli.app/Contents/MacOS/cryptomator-cli \
  --fixture /private/tmp/waglock-export-fixture-NEW \
  --output /private/tmp/waglock-export-recovery-NEW

python3 -m unittest discover -s tools -p 'test_*.py' -v
```

The recovery helper is currently macOS-only: exclusive directory publication uses `renamex_np(RENAME_EXCL)` and fails closed on unsupported platforms. Use a trusted, private parent directory and a new destination. It will preserve a destination that appears during recovery, including an empty directory or dangling symlink; it does not offer crash-durable recovery or isolation from other processes running as the same user. Case/Unicode-normalization path collisions are rejected rather than renamed. See [hardening evidence and remaining limits](../../docs/portable-vault/portable-export-design.md#recovery-verifier-hardening--2026-10-22).

The harness starts the official client on an ephemeral loopback WebDAV port, reads the outer vault, verifies its encrypted manifest/inventory/hashes, and publishes `recovered/` only after verification. It closes its own client process on success or error. It recovers `Protected/` as ciphertext, rejects opening it with the outer password, opens it with its separate inner password, and verifies/publishes `inner-recovered/`. This demonstrates independent opening and password separation; no original app/Keychain is consulted.

It also creates damaged **copies** of the generated vault and checks that missing-manifest, payload-tampering and whole-final-chunk truncation cases cannot publish recovered directories. Logs and `report.json` remain in the newly owned output directory. All plaintext is public synthetic content, but treat future real recovery destinations as sensitive plaintext. The local WebDAV channel is plaintext on loopback and is not a production recovery security recommendation.

For manual inspection of these public fixtures, the underlying command is:

```sh
/path/to/cryptomator-cli.app/Contents/MacOS/cryptomator-cli unlock \
  --password:stdin \
  --mounter=org.cryptomator.frontend.webdav.mount.FallbackMounter \
  --loopbackPort=49183 \
  /private/tmp/waglock-export-fixture-NEW/candidate-vault
```

Enter the public outer fixture password `WagLock outer disposable fixture` when prompted. The client logs a local URL for browsing/reading the outer content. After recovering `Protected/`, it is a separate vault whose public test password is `WagLock inner disposable fixture`. Stop the process with Control-C when finished. The harness is the tested route; manual opening alone does **not** perform completeness verification. Do not place a real password in shell history or command arguments.

The iOS-simulator writer was compiled separately with SwiftPM's `--triple arm64-apple-ios17.6-simulator` and the installed simulator SDK, then run with `simctl spawn` on the disposable QA simulator. Its output passed the same desktop recovery harness. See [recorded results and exact limitations](../../docs/portable-vault/portable-export-design.md). This is not physical-device or GUI/Windows/Linux validation.
