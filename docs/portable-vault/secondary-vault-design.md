# Secondary passcode / independent alternative vault

Owner priority: **2026-10-18**, [D2S-115](https://linear.app/d2sci/issue/D2S-115/design-and-implement-decoy-vault-guest-password-isolation), tied to D2S-111/116 and audit A01/A03/A08/A11. **Status: requirements accepted; architecture proposed; not implemented in build 27.** Linear's existing High-priority issue was updated with this scope. The original source snapshot remains unchanged.

## Requested experience

One ordinary login screen accepts either of two different passcodes. Each opens a distinct, usable vault. The secondary vault is not an empty Guest Mode: its user can populate photos/videos, create nested albums, import/export, relaunch and use normal local settings. No vault selector, Guest/Decoy banner, primary counts, lock-screen hint or management action in the secondary session reveals the primary vault. Entering the primary passcode should open the primary vault after a full lock/login transition; there is no in-session switch button.

“Hidden” means non-disclosure through the ordinary selected-vault UI and service results. The implementation must not promise forensic invisibility or safety under coercion: application binaries, backups, disk usage, device settings, crash evidence and timing can reveal implementation details or the possibility of another vault. An observer who knows the feature exists can still ask for another passcode. There is no automatic emergency deletion, alert, camera capture or external notification attached to this request.

## Why current Guest Mode cannot be reused as the security boundary

Direct source observations:

- `GuestModeManager.shouldShowContent` is a presentation predicate (`currentMode == .owner`).
- `AuthenticationViewModel.login` checks owner and guest passwords but uses the guest input as a session secret, not a separately provisioned random vault key.
- `Private_AlbumApp.sharedModelContainer` constructs one MediaItem/SecretNote/VaultAlbum persistent schema before authentication and mounts it at the app scene.
- `FileStorageService.shared` points at one Documents/EncryptedMedia root; AlbumStore and other shared services assume a single owner domain.
- MediaItem thumbnails/names and SecretNote content persist without vault-level encryption; album names/hierarchy also remain exposed.

Changing visibility filters or adding `vaultID` predicates to the existing shared table alone would not satisfy independent encrypted vaults. Existing owner keys, media, albums and credentials must remain intact while this boundary is redesigned.

## Proposed architecture

### Authenticated context, not a global mode flag

A successful credential match constructs an immutable `VaultContext` containing an opaque vault ID, scoped storage/index/service handles, and a fresh session generation. Key material lives in the authenticated session, not in an enum or UserDefaults entitlement. All services require that context explicitly; the UI can only query the mounted context. Imports, thumbnail decoders, playback, audio recording, notes, exports, album access and settings must not retain a global fallback.

Mount only the selected index after authentication. The secondary session must not construct/query the primary index or receive its key. Separate database files are necessary for isolation but insufficient for metadata confidentiality; encrypt metadata/thumbs or use an approved protected index design. This decision belongs with the A01 remediation and requires failure/recovery tests before using real data.

### Key and storage separation

Provision an independent random data key for the new alternative vault, with a versioned authenticated wrapper under its passcode. Use separate opaque ciphertext roots, metadata indexes, Keychain accounts and biometric records. Neither key can decrypt or unwrap the other domain. Do not derive the secondary key from the primary key or reuse a single media password.

Preserve the existing primary key and its legacy readers. Do not mass re-encrypt existing primary media as a side effect of enabling an alternative passcode. Any required index/storage migration needs a staged, verifiable, resumable design, preserved originals and explicit recovery behavior; failures must leave the existing primary login and data usable.

Provision secondary credentials, initial index and files as a transaction with a recoverable commit marker. Inject failures at each step. Never turn a partial setup into a primary reset, and never remove unknown files on startup. Reject identical primary/secondary passcodes and credential changes that create ambiguity. Password reset/change/delete within the selected vault affects only that vault; primary-vault management is unavailable to a secondary session.

Credential routing should perform equivalent bounded work for configured credential slots and return one generic failure, without vault enumeration or selective “primary password incorrect” errors. This is a side-channel review requirement, not a claim that Swift/UI/Keychain timing is constant time.

### Session and lifecycle isolation

Keys, indexes, caches, temporary filenames/directories, album biometric identifiers, selections, navigation state and background work are scoped by opaque vault ID and session generation. Lock/logout revokes the context, cancels pending operations, clears cached results and closes the index. Results completing late cannot commit, display, reset progress or delete files in a new vault/session. A full authenticated transition is required when changing domains, including after relaunch.

Settings must be scoped too: storage counts/usage, exports, recovery, backups, notifications, album names, search/favorites/recent items, errors and UI restoration cannot aggregate or reveal another vault. Review all global singleton/SwiftData-query paths rather than relying on the visible tabs. OS-reported total app storage is outside selected-vault UI isolation.

### Face ID and album policies

**Owner decision, 2026-10-21:** retain optional vault-level Face ID that the user may assign to either independent vault. Face ID cannot distinguish which passcode-intended domain the person wants; one explicitly assigned vault is its app-level target at a time, while passcodes select their corresponding vaults. Enabling or reassigning it requires a popup warning that biometric unlock can reveal the assigned vault regardless of the user's intended choice. Do not silently disable existing enrollment or infer a target from the last opened vault. Assignment must require authorization for its destination vault and use an opaque, authenticated target binding. Secondary settings must not enumerate the primary vault or its biometric management; a generic login button must not label the assigned domain. Build 29 adds the warning to the existing vault's enrollment path; assignment to an independent alternative vault remains unimplemented until context/key routing exists.

Existing inherited, album-password, password-or-Face-ID and Face-ID-only album options stay within the authenticated vault's parent/key domain. Namespace all album biometrics by vault ID plus album ID. A secondary album cannot unwrap a primary album key even if names/IDs/album passwords happen to match.

## Implementation sequence and acceptance

1. Build an isolated two-vault test fixture and context-bound credential/storage/index interfaces. Prove cross-key decryption fails and wrong-domain paths/indexes are rejected. Do not wire the owner's existing store into a prototype or add a UI switcher as a substitute for separation.
2. Resolve the encrypted metadata/index and legacy-primary transition design with A01/recovery work. Add injected failure, cold reopen and retained-primary-key tests before enabling real-library conversion. Cryptomator remains a proposal; this feature does not approve its production adoption.
3. Thread context through every media/notes/album/settings/import/export/cache/biometric boundary; replace global primary lookups. Wire the single passcode router only when service-level isolation exists.
4. Add independent automated read/write/delete/export/album/search/count/settings/credential tests; verify primary content stays inaccessible under a secondary context, not just hidden by UI. Cover identical passcodes, collisions, wrong keys, traversal, paused imports/decodes, logout/relogin, restart, disk-full and interrupted provisioning.
5. Test two populated disposable vaults on a signed physical device: both passcodes persist across relaunch, secondary UI has no primary disclosures, primary data remains readable, keys do not cross, background/privacy behavior works, and Face ID cannot accidentally choose/open the primary domain. Inspect disposable persistent/temp files and backups under the documented threat model.

No duress/decoy feature claim, sensitive-library beta acceptance, or replacement of Guest Mode as a true independent vault until those checks pass. Build 27 remains a single primary vault with presentation-only Guest Mode. The safe immediate friend-beta scope remains disposable functional samples; [beta-readiness](beta-readiness.md) records the other artwork/license/distribution gates.

## Prototype work — 2026-10-19

The owner authorized step 1: an isolated two-vault prototype with synthetic fixtures, outside production authentication/storage. [Implementation and limits](vault-isolation-prototype.md) record the test-only context, random-key, encrypted-index, path and lifecycle boundaries. This does not enable a second usable vault in build 27, remediate existing primary metadata, authorize migration or close D2S-115.


## Integration preparation — 2026-10-21

Build 29 adds the [authenticated library boundary and legacy transition rehearsal](authenticated-library-boundary.md). The owner database is mounted only after owner authentication; presentation-only Guest Mode receives an empty in-memory schema. Pending authentication/mount results are generation-checked across logout/background/domain changes. A test-only encrypted metadata snapshot preserves all current legacy fields and the synthetic legacy data key without touching originals. The WAL/read-only snapshot finding, mutable-index/journaling gaps and Face ID routing decision remain explicit gates. This is not the shipped independent alternative vault; D2S-115 remains In Progress.
