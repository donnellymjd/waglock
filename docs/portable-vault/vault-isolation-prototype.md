# Two-vault isolation prototype — 2026-10-19

[D2S-115](https://linear.app/d2sci/issue/D2S-115/design-and-implement-decoy-vault-guest-password-isolation), D2S-111/116, audit A01/A03/A05/A06/A08/A10/A11. The owner authorized an **isolated, tested prototype leaving the existing library untouched**. This is step 1 of [the secondary-vault design](secondary-vault-design.md), not delivery of the secondary login feature.

## Experiment boundary

Implementation lives in [test-bundle support](../../WagLockTests/Support/VaultIsolationPrototype.swift), exercised by [VaultIsolationPrototypeTests](../../WagLockTests/VaultIsolationPrototypeTests.swift). It is compiled only into the test target. Production authentication, Guest Mode, SwiftData, media services, Keychain, Face ID and the installed phone app are not connected to it. Tests create unique disposable simulator temporary directories, keep all inputs synthetic and remove their own fixtures afterward. The current phone build remains 27.

There is no new third-party package or production dependency. The experiment reuses `EncryptionService`'s existing buffered authenticated encryption/password KDF. Its domain-bound payload layout is an experiment, not an accepted portable storage format or Cryptomator implementation. No production ciphertext, credential, filename or database is migrated, rewritten or deleted.

## What is implemented

- Independent checked-system-random 256-bit secrets for each vault, encoded only for compatibility with the existing string-based encryption API. Secrets are wrapped under different passcodes; no primary/secondary role label is persisted.
- Opaque UUID directories, a password-encrypted key envelope and an encrypted index per vault. The index holds sample names, thumbnails, album paths, notes and settings; sample media is stored separately as encrypted bytes. No plaintext index/WAL or preview/export files are created.
- Every encrypted envelope authenticates its version, store ID, vault ID, purpose (key/index/asset) and optional asset ID inside the AEAD-protected payload. Decryption must verify these bindings before returning payload bytes; ciphertext swapping is rejected.
- One active context per store instance. Contexts belong to their creating store instance and receive a fresh session generation. Object-identity checks reject a prior context even when the same passcode logs into the same vault again. Revocation wipes the backing SecureBytes, drops its reference and clears the metadata cache.
- Authentication tries each committed credential slot for valid fixture layouts rather than returning on the first successful match. Wrong passcodes and unusable indexes return one generic authentication failure. Duplicate passcodes are rejected at provisioning. This is not constant-time authentication or a production lockout policy.
- Imports validate the originating context before and after the async source operation, check cancellation, write an encrypted asset and then atomically replace the encrypted index. A reported save failure removes a new asset only when persisted index verification shows it is uncommitted. Uncertain/actually committed outputs are preserved and caches invalidated.
- Provisioning stages credentials and the initial encrypted index in a newly owned directory, then publishes both with a directory rename. Failure cleanup touches only that staging directory. A missing store marker in a nonempty directory fails closed rather than creating a replacement identity.
- Reads/deletes require the active context, matching vault reference and index membership. UUID-only generated storage paths and resolved-path checks reject fixture symlink escapes before writes/deletes. Returned plaintext is only a caller-owned in-memory buffer in this experiment.

## Adversarial checks

The suite covers two populated vaults across fresh store reconstruction; separate metadata/settings; independent delete/export; duplicate and incorrect passcodes; foreign-store contexts; cross-vault ciphertext and index swapping; same-vault asset substitution; symlink escape; late imports after domain switch and same-vault relogin; cancellation; failed provisioning; ordinary versus uncertain save outcomes; missing-marker preservation; secondary login with a damaged primary index; oversized imports; synthetic out-of-space at index commit; and byte-preserving Unicode names/passcodes/album paths and binary media.

The persistent-file check searches all fixture files for known synthetic filenames, album names, notes, settings, thumbnail bytes, original content and passcodes. Absence of those exact byte sequences is bounded evidence about this prototype's writes, not a complete forensic inspection or proof of memory erasure.

## Limits and next design gate

- This is a single-process, MainActor-serialized, small-buffer experiment: media and thumbnail inputs are capped at 1 MiB each; encoded envelopes at 4 MiB; file reads at 5 MiB. Large-file streaming must use the existing versioned framing with equivalent domain/asset binding before production adoption. Full-index replacement is not a scalable thousands-of-assets gallery design.
- Provisioning is harness-only fixture setup, not an authenticated administration/recovery API; production management must require the correct vault authorization. No actual album key hierarchy, album Face ID, biometric routing, complete app settings, UI selector/passcode route, Keychain implementation, backup or legacy-primary adapter is included. The owner’s existing vault and its plaintext metadata/notes remain unchanged and retain their audit findings.
- No durable import journal, fsync/power-loss guarantee, multi-process locking or startup orphan cleanup. Process death may leave pending/orphaned ciphertext. Symlink checks are sequential fixture protections, not race-proof descriptor-relative I/O against a concurrently malicious filesystem.
- Context revocation cannot erase plaintext/Swift String/Data copies already returned to callers. No device memory-dump, backup extraction or cold restore after device loss has been validated. A fresh store object reusing the same synthetic directory is not full recovery certification.
- Slot count, opaque paths and storage sizes are observable outside the selected UI. Timing, corrupted-slot availability behavior, KDF cost, brute-force protection and biometric behavior need review. Authentic old snapshots can still be replayed: no trusted anti-rollback/completeness mechanism is claimed. No forensic invisibility or coercion-safety claim follows from passing tests.

Before moving this into the app, resolve the encrypted-index strategy and non-destructive legacy-primary transition. Specify how to open the existing library read-only, verify retained keys/content, stage and verify metadata migration, recover from interruption and handle rollback without data loss. Keep legacy readers, preserved originals and explicit version gates. Do not replace SwiftData/storage, introduce Cryptomator, or enable a public “duress vault” claim merely because the fixture passes.

## Reproducing validation

The initial targeted run passed 16 tests. After explicit actor annotations, a synchronous directory-enumeration helper and the Unicode fixture were added, the complete unit suite passed **120 tests**: 28 XCTest plus 92 Swift Testing (including 17 isolation cases). The wrong-key case was then strengthened to inspect only synthetic fixture key envelopes, compare independently generated 32-byte secrets and call decryption directly with the wrong key; its final targeted rerun is recorded in the root build summary.

```sh
xcodebuild test -project ZeroNet-Space.xcodeproj -scheme ZeroNet-Space \
  -destination 'platform=iOS Simulator,id=193189DC-3419-4B0B-8DC5-84FDAB25484B' \
  -derivedDataPath /private/tmp/vaultito-import-compat-tests \
  -only-testing:ZeroNet-SpaceTests/VaultIsolationPrototypeTests \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

For the full unit regression run, use `-only-testing:ZeroNet-SpaceTests`. Select an available simulator rather than assuming this disposable local ID exists elsewhere. These checks ran on iPhone 16 / iOS 18.4 simulator, not the owner's phone. UI, hardware Face ID, large-library performance and physical backup/restore were not exercised because this change adds no application integration.
