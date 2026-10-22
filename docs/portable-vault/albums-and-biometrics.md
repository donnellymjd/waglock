# Nested albums and biometric unlock

Requested 2026-10-17: albums and nested subalbums like Private Photo Vault, independently selectable album security, optional biometric unlock of Vaultito and its albums. The user explicitly requested **Face ID-only albums**, in addition to inherited/password/password-with-biometric-convenience choices.

## User flow

- In Photos, open **Albums**. Create an album, open it, and create subalbums inside it. There is no fixed nesting depth; malformed/cyclic ancestry fails closed.
- Each album can inherit parent protection, use its own password, use its own password **or** Face ID, or use Face ID only. Every ancestor must be unlocked before opening a descendant, even when the descendant has its own password or biometric permission.
- New albums open after creation. Unlocks last for the active vault session until manually locked. Locking a parent locks all descendants; backgrounding or logging out locks all albums, including when the inherited recording exception keeps the vault session alive.
- The album menu offers imports, moving items from the main library, security changes, rename, manual lock and deletion of empty albums. A verified move commits encrypted destination content before deleting its original record/ciphertext. Files and Photos imports write directly into the chosen album and do not enter the global gallery index. Media can be previewed with QuickLook and deleted using swipe actions.
- Under Settings → **Face ID Unlock**, enter the current vault password and enable biometric convenience. The login screen then offers **Unlock with Face ID**. The vault password always remains available. Existing calculator disguise login remains password-based; to use the normal biometric login screen, turn off calculator disguise.

## Key and data boundaries

`VaultAlbum` adds an entity to SwiftData without changing or replacing legacy MediaItem/SecretNote entities or their ciphertext readers. Public fields include album ID, parent ID, name, security mode, creation time and biometric-account ID. **Album names and hierarchy are not encrypted in this iteration.**

Every album has a checked-random 32-byte secret. Its encrypted key material includes the album ID to reject swapped key envelopes. Inherited albums wrap that material under their immediate parent secret (or the vault data secret for top-level albums). Other modes first wrap it under the album password or a random biometric-only factor, then wrap that envelope under the parent secret. Changing a parent's policy rewraps its existing secret and preserves descendant keys. Changing protection requires the album and ancestors unlocked, locks the subtree after commit, and does not automatically weaken a child's selected mode.

Catalogs encrypt media names, opaque ciphertext paths, thumbnails, media types, byte counts and import times using the album secret. Album media has no MediaItem rows; legacy Photos/Media/Files/search/export queries therefore cannot enumerate it or display its thumbnails. Album operations validate the unlocked ancestry and membership before reading, importing, moving, deleting or previewing. The vault data secret alone cannot decrypt album media. New ciphertext filenames omit the source filename.

Biometric factors are stored in a separate bundle-scoped Keychain service with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and **`.biometryCurrentSet`** access control. Fresh `LAContext` instances use **`.deviceOwnerAuthenticationWithBiometrics`**, with no device-passcode fallback. No authenticated Boolean substitutes for Keychain secret release. Password-plus-Face-ID mode keeps a password path if biometry is unavailable or invalidated. New biometric enrollment is committed before policy changes; failed/cancelled enrollment preserves the old policy and credentials. Pending authentication/import/preview results carry a session generation and cannot regrant access after a lock/logout.

Apple references: [biometric Keychain access](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id), [current-enrollment ACL](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset), [biometrics-only authentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics), [Face ID privacy description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription). Face ID permission text is included in the built plist and localized plist resources. Touch ID can satisfy the same biometric policy on devices that provide it.

## Face ID-only recovery exception

Face ID-only albums have **no album-password fallback**. Their random additional factor exists only in the device-bound biometric Keychain entry. Resetting biometric enrollment, removing the device passcode, losing the entry or losing the device can permanently prevent access. The creation/security UI requires acknowledgement of this device dependency before saving this mode. The root vault password does not bypass that factor. This is a user-authorized exception to the general preference for password-recoverable biometric convenience, not a claim that these albums support desktop or fresh-device recovery.

To retain a password path, choose **Album password or Face ID**. Cryptomator compatibility and portable album-key recovery remain unvalidated proposals. No current mode should be advertised as independently recoverable until the relevant recovery implementation and tests exist.

## Limits and further hardening

- Existing main-library metadata/thumbnails and notes remain subject to the D2S-105 findings. Moving into an album removes the current global row/cache, but old database/WAL pages or existing backups may retain earlier metadata. The move UI discloses this; no forensic erasure claim is made.
- The inherited streaming file format, KDF and known integrity/transaction limitations remain. Album imports preserve selected file bytes, but picker representation, Live Photo pairing, EXIF extraction, albums from other apps and large-library resumable migration are not fully validated.
- Catalog commits are saved after ciphertext writes. Failed writes/cancelled imports clean known outputs; crash interruption can still leave orphaned ciphertext or biometric entries. Journal/reconciliation and low-storage/power-loss testing remain release work. A failed verified move may leave a duplicate destination while retaining the original, favoring preservation over destructive rollback.
- Preview/import plaintext uses scoped protected temporary locations and is cleaned on completion, dismissal, background and next process startup. QuickLook/decoder/system share caches and external recipients still require device-level leakage review. Crash-time and flash-level erasure cannot be guaranteed.
- Swift String/Data copies of keys and decoded catalogs are not proven to be fully zeroized. Album names/structure remain observable. Password guessing policy, independent audit, backup/restore and comprehensive localization/performance work remain outstanding.
- Actual biometric success, cancellation, lockout, denied permission, changed enrollment and device-passcode removal must be tested on disposable device data; injected biometric test doubles validate application control flow, not Secure Enclave behavior.

See BUILD_ERRORS_SUMMARY.md for actual validation outcomes. Installation/launch alone does not close the architecture/security audit.

## Validation — build 22

51 unit tests (28 XCTest + 23 Swift Testing) and one complete album UI workflow test passed on iPhone 17 / iOS 26.5 simulator. The tests include persistent-schema migration from the pre-album models, nested access, verified moves and the Guest Mode key boundary. Signed iOS build 22 installed and launched on the paired iPhone 17 Pro running iOS 27.0.1. Real Face ID enrollment/sensor/ACL behavior remains for manual device testing. Existing user media was not moved automatically and no test password or biometric enrollment was added on the phone.

## Renewed priority — 2026-10-22

Owner emphasized **a vault within a vault**, with distinct passwords/passcodes for albums/subdirectories. Track completion under [D2S-141](https://linear.app/d2sci/issue/D2S-141), High. Existing nested independent-password UI is the starting point; metadata encryption, lifecycle/recovery and export-boundary gaps above remain open. Whole-vault export (D2S-114) must preserve independently protected children and document their unlock path with the selected open-source tool. Parent-password-only recovery must not bypass a separately protected child. Face ID-only portability requires explicit handling before a complete recoverable-export claim. This is distinct from D2S-115 alternative top-level login and D2S-139 shared albums.
