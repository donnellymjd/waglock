# Credential, storage and cache hardening — build 24

Recorded 2026-10-17. Owners: [D2S-111](https://linear.app/d2sci/issue/D2S-111) and [D2S-116](https://linear.app/d2sci/issue/D2S-116). This addresses specific A05/A08/A09/A10/A11 paths from [the initial audit](audits/D2S-105.md), without closing those issues or replacing the media store.

## Credential preservation

Startup now sets the preferences initialization marker without deleting Keychain entries. Missing preferences cannot establish that credentials are orphaned. Any owner credential fragment, corrupt record, or inaccessible Keychain routes to the existing-password screen rather than permitting setup to overwrite recovery material. Explicit fixture/reset methods remain; they are not called by startup.

Owner setup and explicit password changes write the account `vaultito.owner-credentials.v1` as one complete Keychain value. Its contents are the inherited buffered AES-GCM envelope over JSON containing `version: 1`, the Keychain service namespace and the retained data-encryption secret. Password verification authenticates and decodes this envelope, using the existing PBKDF2-HMAC-SHA256/100,000-iteration derivation. New owner records do not add a separate fast SHA-256 verifier. Namespace binding rejects copying a record into another app service.

All credential preparation finishes before the one required mutation. Existing values use [SecItemUpdate](https://developer.apple.com/documentation/security/secitemupdate(_:_:)); initial creation uses SecItemAdd, without deleting the previous item first. Failure before that commit leaves the prior verifier and wrapped data key together. This is logical atomicity at a single Keychain API boundary, not an independently tested power-loss guarantee. The retained data key does not change, so existing media and album keys do not need re-encryption. An owner password cannot be changed to an existing guest password.

**Ordinary login to an existing legacy vault does not rewrite its credentials.** The legacy reader validates the owner hash and salt before reading its wrapped data secret. Only the oldest verified legacy format may use the verified login password itself when that wrapper is absent. An arbitrary unverified password cannot create a replacement wrapper. Damaged available wrappers fail closed and remain untouched.

An explicit password change from legacy credentials commits the new complete record first, then removes obsolete owner hash/salt/marker/wrapper accounts. Failed cleanup is retried after successful login to the current record. Once a current record exists, corrupt/unavailable data never falls back to stale legacy credentials. A cleanup failure can leave old wrappers extractable until cleanup succeeds; previous backups may also retain them. Do not claim cryptographic revocation of old backups or secure erasure.

Older builds do not understand the new credential account. **Do not downgrade after setup or a password change in build 24.** Existing legacy credentials still use the old fast verifier until an explicit password change. Guest/disguise/draft formats remain inherited. Keychain is still device-bound, initial data secrets retain inherited semantics, and cold restore without Keychain remains unimplemented. This is not a recovery export feature or a new portable vault format.

## Storage preflight and diagnostics

New encrypted filenames are UUIDs plus the generic encrypted-file extension. Original names and original extensions are no longer copied into those paths. Existing named files remain readable and are not renamed; names, thumbnails and notes in the main SwiftData database still need encryption.

The free-space preflight now propagates failures instead of catching its own insufficient-storage error and continuing. It reserves 100 MiB and budgets streaming overhead conservatively (at least 128 bytes or 1% of source size). A preflight cannot reserve space against other writers; actual write errors still propagate and the build 23 atomic output rules remain essential. Synthetic capacity failures are tested; real device disk exhaustion remains outstanding.

Removed content/path/error-detail diagnostics from EncryptionService, FileStorageService and MediaImportService. This is a bounded reduction: other inherited screens/export/re-encryption/storage code still contain diagnostic logging. No whole-app log-leakage clearance is claimed.

## Image cache lifecycle

Thumbnail and preview caches now share a lock-protected generation check. Clearing increments the generation and empties the cache under the same lock. A decode started before invalidation cannot insert its result afterward. Both loaders check cancellation after awaiting decoding; cancelled requests cannot publish/cache their result. Background entry clears both caches, in addition to existing logout and password-change boundaries.

Preview cache keys also include a password-context digest, so a cached asset path does not satisfy a request using the wrong password. Thumbnail fingerprints cover the complete thumbnail data, avoiding reuse after changes limited to the middle bytes. Path-specific preview eviction conservatively invalidates the entire preview cache, including pending loads in every password context.

These checks prevent stale result publication; they do not prove zeroization of UIKit/ImageIO buffers, removal of pixels held by an already-rendered view, or cancellation of all underlying decoder/decryption work. The existing app-switcher cover remains required.

## Validation and remaining device checks

Two initial regressions reproduced destructive preferences-marker handling and an unverified legacy data-password fallback before the fix. Further tests inject failed initial writes, failed password changes, unavailable Keychain, interrupted legacy cleanup, corrupted records and namespace substitution. They verify retained media keys and reject owner/guest password collisions. Six storage tests cover opaque names, legacy reads, synthetic low-space/lookup failures and stream overhead. Six cache tests deterministically pause a background decoder across clear/cancel boundaries and exercise wrong-password cache access.

The simulator does not report the physical file-protection attribute; that assertion is compiled only for device tests. A first storage-test run failed on URL trailing-slash comparison and this simulator-only attribute absence; normalized path comparison and the device-only protection check corrected the test assumptions. These are not evidence that device file protection was exercised.

Before considering the hardware gate passed, use disposable media to open old/new files, change the vault password, relaunch and verify old-password rejection/new-password access, then test vault and album Face ID cancellation/success and background locking. Do not alter biometric enrollment or reset the real vault to test failure cases. Record exact build/device/results in the root BUILD_ERRORS_SUMMARY.md. Simulated Keychain/decoder failures are not hardware validation.

Build 24's unit phase passed **91 tests** (28 XCTest + 63 Swift Testing), and the generic iOS signed build passed. It installed/launched on the paired iPhone 17 Pro / iOS 27.0.1. The user explicitly reported the requested hardware pass as **passed**, adding P2 thumbnail-ratio and numeric-prompt follow-ups. Automated UI testing remains blocked by runner startup/stall on both the existing and fresh simulator; the combined test command did not complete successfully. The task-owned stalled jobs were stopped without restarting shared services. See BUILD_ERRORS_SUMMARY.md for evidence and the pending restart-approval boundary.

Subsequently, the user approved the shared-service restart. After restarting CoreSimulator, the album UI workflow retry passed (one test, exit 0). The startup blocker is resolved; the earlier combined command remains an unsuccessful historical attempt, not an additional pass.
