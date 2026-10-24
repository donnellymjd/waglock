# Secondary passcode / independent alternative vault

Owner priority: **2026-10-18**, [D2S-115](https://linear.app/d2sci/issue/D2S-115/design-and-implement-decoy-vault-guest-password-isolation), tied to D2S-111/116 and audit A01/A03/A08/A11. **Current status (October24): build52 implements independent Guest Mode in the public encrypted release configuration; automated isolation/UI checks and the requested physical/recovery checklist pass. D2S-115 is Done; broader audit/release gates remain.** Linear's existing High-priority issue was updated with this scope. The original source snapshot remains unchanged.

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

## October23 launch scope and pre-release compatibility

The owner explicitly reinstates Guest Mode for1.0 and confirms that current test vaults are disposable and there are no external users. Do not spend the launch cycle building an installed-user migration system for a nonexistent user base. Preserve existing test material when straightforward; do not silently erase or fall back to an empty replacement when a store fails authentication. After1.0, released-user compatibility, recoverable upgrades and migration evidence are mandatory.

The fresh encrypted metadata repository and atomic credential boundary now exist in production, so the old global plaintext-index blocker is removed for the public identity. Integration still requires explicit per-vault media/import/album/document/export/biometric contexts: the October23 inventory finds26 direct FileStorageService.shared references,46 owner/content predicates, and additional shared caches/export services. A global preference flip or a mutable shared storage root would let late work target another vault and is not an acceptable shortcut.

Immediate implementation sequence: finish and physically check the security-hardening batch; introduce immutable selected-vault service handles and independent modern guest credentials; mount only the selected encrypted index; thread those handles through the identified operations; then enable ordinary passcode routing and perform populated two-vault isolation/recovery tests. Both vaults must retain independent normal use; do not substitute the inherited ephemeral empty view.

## October24 — storage dependency preparation

Owner accepted all requested build51 phone checks. The next development change makes AlbumStore's media storage explicit, and similarly passes an immutable storage handle into AudioImportService and AudioSessionController. Album import, preview, move and deletion and audio import, rollback and playback no longer need to discover a global media root inside their operation. Existing app defaults remain unchanged; no routing flag, credential account, metadata mount, biometric target or phone library changes.

Tests create two separate real storage roots and independent album/data passwords, import same-named samples, preview both, reject cross-root/catalog access and prove deleting one domain's content preserves the other's ciphertext. Audio import has independent encrypted round trips and root containment checks. This is necessary dependency preparation, not a completed authenticated VaultContext: shared UI, caches, album-attempt/biometric namespaces, credentials, index selection, settings and export/backup routing still need explicit selected-vault integration. The inherited release Guest Mode guards remain in place.

Validation for this dependency preparation:22 targeted tests and300 full unit/security tests pass on iOS18.4; see BUILD_ERRORS_SUMMARY.md. No new phone installation was made and Guest Mode remains disabled until the complete selected-vault boundary is wired and tested.


## October24 — independent credential and mount boundary

D2S-115 now has production credential primitives for a secondary domain, deliberately not connected to the ordinary login or setup UI yet. `waglock.secondary-credentials.v1` is a single create-only Keychain record holding an opaque UUID and a WLPEv1 envelope. The authenticated payload repeats the UUID and service and contains its own independently generated random data secret. The envelope context binds both service and UUID. The outer UUID is only an unauthenticated routing hint: it never authorizes a mount. This slot rejects legacy-envelope fallback.

Provisioning requires an existing readable modern primary record and refuses replacement. Explicit secondary password changes preserve its UUID/data secret and atomically replace only its own record after verifying the old secondary password. Primary and secondary password changes reject collisions. Checked absence distinguishes an unavailable/malformed item from an unconfigured slot; structural corruption cannot silently become a new setup. Invalid authentication and damaged ciphertext remain indistinguishable. No modern secondary credential deletion/reset API is enabled. The existing legacy Guest APIs, release guards, biometric enrollment and owner identity remain unchanged.

`LibraryMountCoordinator.Scope.independentVault(UUID)` adds an explicit, fixed selected-domain mount. A coordinator bound to one domain rejects a request for another before opening an index; an unconfigured coordinator cannot fall back to a legacy store for an independent request. The encrypted mount also receives its immutable media-storage dependency for the existing legacy-source check. Independent draft export reads only its encrypted repository and never falls back to primary Keychain/preferences drafts. Session revocation remains synchronous and scoped by originating session ID.

Disposable tests cover cold credential reopen, independent media decryption, password-change key retention, duplicate/colliding passwords, failed writes, unavailable/corrupt records, tampered UUID/ciphertext, cross-service credentials, separate populated encrypted note/draft indexes, scoped revocation, cold remount and wrong-domain mount rejection. This does not establish completed UI/service isolation, equal-cost credential routing or physical two-vault acceptance. Provisioning the credential and first encrypted index is not yet one completed application workflow; interrupted index creation still uses FreshEncryptedLibrary's existing recoverable publication/anchor mechanism. App-level Face ID assignment, scoped album/cache/preview/import/export/settings services and ordinary login wiring remain required before enabling Guest Mode for1.0. No phone build or submission was produced by this groundwork.


The same groundwork adds `VaultSessionContext`: immutable vault/session IDs, media storage, import/preview services, album store, per-instance thumbnail/image caches, per-session export paths and document capability. Album biometrics and online-attempt storage use vault-specific namespaces; AlbumStore cache invalidation is now injected too. Revocation flushes notes before closing model leases, then revokes only the matching session's mounts/exports/documents/album keys and cached results. A revoked context cannot be reactivated. A context-created document preview captures its storage handle and never defaults to the primary singleton. This constructor is for explicitly selected domains; adopting it for an existing primary session still needs a deliberate choice for its existing biometric/attempt namespaces, not silent credential migration.

A real encrypted-document test creates two contexts, opens both samples, rejects foreign-root access, revokes one while preserving the other preview, and rejects new preview requests through the revoked context. Audio playback/controller lifetime and app-wide/view consumption remain integration work; this context is not yet constructed by production authentication. Access to raw service handles alone is not a substitute for the originating write lease or document/export capability, and knowledge of an already released plaintext key cannot be revoked cryptographically.


Final validation for this checkpoint:307 unit/security tests pass with zero failures/skips on the owned iOS18.4 simulator (`/private/tmp/waglock-vault-context-full.xcresult`). See BUILD_ERRORS_SUMMARY.md for targeted evidence and limits. Build51 remains the last installed/physically accepted phone build; independent Guest Mode is still gated pending consumer integration and real two-vault acceptance.


## Build52 — production integration and pending owner acceptance

Ordinary passcode login in the public encrypted release now tries both modern credential slots under the same durable online reservation. Configured primary/secondary wrappers each receive bounded verification work; this is not a constant-time claim. A match installs only that vault's random secret, opaque selected ID and immutable service graph. The primary retains its existing media/index root and album biometric/attempt namespaces. The secondary uses `Documents/WagLockSecondaryMedia/<opaque-ID>` for ciphertext, a separate `Application Support/WagLockSecondaryLibraries/<opaque-ID>` encrypted repository, and its own Keychain anchor, album biometric service and attempt budget namespaces. Only the chosen index mounts. No existing owner data is converted or deleted; Cryptomator remains a proposal.

The authenticated root injects the selected graph into media, video, audio, files, albums, notes, import, preview, sharing, storage settings and backup views. Stateful imports/gallery models capture their storage at construction; document models bind once to the originating session; note autosave listens to that session's flush/revocation authority. Share-sheet cleanup uses its originating export instance. Storage statistics read the selected media root instead of combined Documents/cache usage. Recording remains disabled in the public release. Session exports/audio directories now live in marked protected jobs; startup cleanup traverses only the corresponding owned job root. Late operations retain the original immutable handles and still require their existing write/document/export capabilities.

Primary Settings → Security & access allows create-only alternative-passcode setup. After setup, no primary control overwrites or deletes the secondary credential. In the secondary session, normal libraries, notes, nested album protection, password changes and backups are available, but primary/alternative-passcode management is absent. Changing the secondary password verifies its existing password and preserves its independent data key/identity. There is no in-session vault selector, Guest badge or primary count. Backups capture only the selected mounted index and scoped album/media services, including its encrypted drafts; a forged reference to primary ciphertext fails snapshot capture rather than exporting it.

Face ID remains explicitly assigned to one vault at a time through its own password and the existing disclosure warning. New hardware-protected grants use a versioned `WLBG1:` payload binding the selected secondary ID (or primary) and its data secret. A secondary grant must still match the current provisioned opaque ID; malformed/stale targets fail closed. Existing untagged grants remain primary-only, preserving enrollment. Either unlocked vault can explicitly assign Face ID to itself; the login button never names its target. Cancellation leaves the app locked. No device-passcode fallback is added. Stored grants remain device-bound and outside portable backups.

Background/logout flush drafts while their originating lease is valid, revoke the selected graph and invalidate its mount synchronously. A nonlocking Dev resume creates a new session generation instead of reviving old capabilities. Scoped biometric/album/export/audio services use explicit nonisolated teardown, correcting an iOS18/Xcode back-deployment crash demonstrated by real rendering tests. The inherited Dev guest credential path remains distinct from the modern release feature and is not evidence of independent vault security.

Automated evidence:309 unit/security tests (185 XCTest +124 Swift Testing) pass, `/private/tmp/waglock-build52-full.xcresult`;24 targeted authentication/document/photo/video/export checks pass, `/private/tmp/waglock-guest-routing-fixed.xcresult`; actual release UI independently provisions and opens both passcodes, persists each note across cold relaunch, rejects cross-vault note visibility and checks secondary settings omit primary controls (`/private/tmp/waglock-build52-independent-release-ui.xcresult`). Additional snapshot assertions verify selected-only notes/drafts and foreign primary-source rejection (`/private/tmp/waglock-build52-secondary-backup-snapshot.xcresult`). Real hardware Face ID/Files sharing and two populated vaults still require the owner checklist. No independent security certification, forensic invisibility, live migration or App Store submission is claimed.

Build52 was signed with the existing development provisioning and installed over `com.d2sci.waglock` on the authorized iPhone, preserving the existing primary library. WagLock Dev remains untouched. The owner has been asked to test two populated disposable vaults, explicit Face ID assignment/cancellation, background note/PDF behavior and a secondary-only independently recovered backup. Do not mark D2S-115 accepted or clear submission gates before that response and the remaining review/account-side work.


Additional release UI regression evidence: repeated note-draft/background cycles and primary password-change/cold reopening both pass (`/private/tmp/waglock-build52-release-regressions.xcresult`), bringing this candidate's selected release workflows to3 passing checks. This does not replace the requested hardware acceptance.


## October24 — build52 owner acceptance passed

The owner replied “passed” to the complete requested build52 phone checklist: the existing main library opens; an alternative passcode creates/opens its own photo, note and protected-album library with cold-relaunch persistence and separation in both directions; Face ID can be explicitly assigned to each vault, shows the disclosure warning, opens only the assigned vault and remains locked on cancellation; backgrounded note/PDF behavior works; and a backup made from the secondary vault independently recovers only that vault. No passwords or private media were requested or retained.

D2S-115 is Done for the requested1.0 feature. This is owner-reported physical functional/recovery acceptance paired with309 unit/security tests and3 actual-release UI workflows, not independent audit, forensic-deniability or full security certification. D2S-105 and remaining review findings/distribution gates stay open. Installed candidate remains WagLock1.0(52), implementation cd9741f; no new binary, migration, reset, archive/upload or submission was made for this acceptance record.
