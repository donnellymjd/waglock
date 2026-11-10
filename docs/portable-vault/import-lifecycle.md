# Import lifecycle hardening — build 25

Recorded 2026-10-17 for D2S-116/117 and audit A06/A08. No media format replacement, automatic conversion or existing-library cleanup is introduced.

## Reproduced problem

Two paused-operation tests demonstrated that a cancelled import or an import completing after logout could still insert MediaItem records and emit success callbacks. Both tests failed before the fix, with six failed assertions in total. The encrypted-file import path also reported success after a database-save error, separate from the ordinary import path's error handling.

## Commit and ownership rules

- Photos, Files and encrypted-file re-imports now share one commit path. Require a database context and an authenticated owner before starting. Guest Mode cannot write owner-library records through this view model; it remains a presentation-only feature pending independent decoy storage.
- Capture the operation generation and the actual session-secret object. Check cancellation, generation, owner state and session identity again after awaiting the import. Logging out and back in with the same password does not revive a previous operation.
- Cancel invalidates the operation generation immediately. A stale completion cannot clear a newer run's progress/task state. Queued progress updates are also generation/owner checked.
- Cancelling the encrypted-file password prompt uses the same revocation path; swiping the prompt away before confirmation clears pending state instead of leaving imports stuck.
- Save records before invoking success callbacks. Database-save failures roll back pending inserts and do not report a successful imported count.
- Import operations return freshly created ciphertext paths. On cancellation/session rejection/save failure, a separate context checks committed database state before removing those outputs. A file referenced by an actually committed record is preserved even if the caller observed a subsequent error. A failed verification query conservatively preserves the file. Source assets are never deleted by this cleanup.
- The service owns newly created outputs until a complete batch is returned. Cancellation, including cancellation after the final output, discards that uncommitted batch. Ordinary per-item failures keep successful siblings, preserving existing partial-success behavior. Security-scoped Files access spans the async read.

These are observed-operation failure guarantees, not a durable transaction journal. Process termination between file creation and database save can still leave orphaned ciphertext. Cleanup may fail while storage is inaccessible. No startup scan deletes unknown media, and this does not establish power-loss recovery, exact-once resume, complete Photos-provider cancellation or a cold-restore scheme.

## Older-runtime compatibility finding

The full iOS 18.4 suite exposed a calculator-model deinitialization crash. Its symbolicated stack contained `swift::TaskLocal::StopLookupScope`, `swift_task_deinitOnExecutorMainActorBackDeploy` and CalculatorViewModel destruction. It matches the reported [Swift default-MainActor back-deployment issue](https://github.com/swiftlang/swift/issues/88036). The calculator now has an explicit empty nonisolated deinitializer, appropriate because it performs no actor-bound cleanup. Both existing synchronous calculator localization tests and the full unit suite passed after this change. This is a scoped workaround, not clearance of every older-OS concurrency path.

## Verification

**103 unit tests passed** (28 XCTest + 75 Swift Testing) on a disposable iPhone 16 / iOS 18.4 simulator, including 12 import lifecycle tests. Coverage includes failed/uncertain database commits, stale cancelled completions during a newer run, logout/relogin with the same password, missing context/owner permission, callbacks after durable save, encrypted-prompt cancellation, service-level cancellation cleanup and partial success. The final combined command also passed one album UI workflow with the calculator workaround and prompt-dismissal handling included. The development-signed generic iOS build passed.

The earlier iOS 26.5 attempt failed before execution with a Mach server-died launch error. Build 24's UI workflow had already passed after the user-approved shared simulator-service restart. The initial build 25 full run recorded the older-runtime allocator crash and was not counted as a complete pass.

Final combined results/log: `/private/tmp/vaultito-build25-complete-tests.xcresult`, `/private/tmp/vaultito-build25-complete-tests.log`. Signed build: `/private/tmp/vaultito-build25-complete-device.log`. Reproduction: `/private/tmp/vaultito-import-before.log`. Evidence is local/ephemeral. Device installation and manual results are recorded separately in BUILD_ERRORS_SUMMARY.md; no phone pass is inferred from compilation.

## Paste (2026-11-09)

The Add to WagLock sheet has a **Paste** row backed by the system `PasteButton`. iOS releases the clipboard only to that tap, so no "Allow Paste" prompt appears, and WagLock never reads the clipboard on its own (no background or launch-time access, no polling).

- **Accepted items:** images and movies take the same paths as Photos imports. Other items, such as audio, PDFs, documents, archives and plain text, are copied through `MediaImportService.importPasted` into an owned protected temporary folder, encrypted through `importSingleFile`, and the copy is removed.
- **Skipped items:** links and other references (`public.url`, `public.file-url`) are not files and are skipped. If nothing on the clipboard can be added, the sheet says so instead of closing.
- **Commit and storage:** pasted batches use the same commit-after-save boundary, session checks, stop-on-lock behavior and fixed-size reserve claims as other imports.
- **Clearing the clipboard:** the completion screen warns that what was copied is still on the clipboard and can sync to the person's other devices (Universal Clipboard), and offers **Clear clipboard**, which empties `UIPasteboard.general`. Clearing is never automatic. The source the item was copied from is not changed.
- **Albums:** album menus do not offer Paste yet; pasted items land in the Library and can be moved into an album from there.

Tests: `WagLockTests/PasteImportTests.swift` (content preferred over references, image and text items encrypted, links skipped, temporary copies removed). Not compiled or run in this environment.

## Deleting originals after import (2026-11-09)

After an import, the completion screen offers to delete the originals:

- **Photos:** **Remove from Photos…** appears only when every selected item committed. iOS shows its own confirmation, and the items go to Recently Deleted in Photos.
- **Files and audio:** **Delete originals…** applies to the files picked in Files whose encrypted copies were committed by that import. The picker opens originals in place (not copies), so WagLock can delete them. After the person confirms in WagLock's dialog, `ImportedOriginalsRemover` handles each original in turn:
  1. Decrypts the stored copy to a temporary file and compares its SHA-256 with the original, streamed in 1 MiB chunks. Every import path stores original bytes unchanged.
  2. Deletes the original with a coordinated delete only if the hashes match. It tries the provider's Recently Deleted (trash) first and falls back to permanent removal, as the dialog warns.
  3. Keeps any original whose copy can't be decrypted, doesn't match, or sits in a location that refuses deletion. The result says how many were deleted and how many kept.
  4. Removes the decrypted temporary copy every time.
- **Locking** WagLock or changing session stops the run at once; everything not yet deleted is kept.
- **Pasted items** have no original to delete. The completion screen offers Clear clipboard instead.

Nothing is ever deleted without the explicit tap and confirmation, and Keep is always offered. Tests: `WagLockTests/ImportedOriginalsRemoverTests.swift` (only verified originals deleted, mismatched or unreadable copies keep their originals, plaintext copies removed, lock stops before deletion). Not compiled or run in this environment.

## Camera capture (2026-11-10)

**Take photo or video** in the Add to WagLock sheet opens the system camera (`UIImagePickerController`). It is hidden where no camera exists, such as the Simulator.

- **Never in the camera roll:** captures are not saved to Photos.
- **Photos:** encoded once to HEIC (JPEG where HEIC isn't available) with the camera's metadata dictionary and EXIF orientation.
- **Videos:** the camera's temporary movie is moved into an owned folder.
- **Owned temporary folder:** each capture is written into a protected folder with the same `waglock-media-import-` prefix as other import copies, so launch cleanup also removes abandoned ones. It is imported through `MediaImportService.importOwnedFiles`, the usual commit, session, lock and reserve path, and the folder is removed afterwards whatever the outcome.
- **Permissions:** the camera permission string is added; video reuses the existing microphone string.
- **Live Photos and location:** the system camera can't capture Live Photos and doesn't add location.

Tests: `WagLockTests/CameraCaptureTests.swift` (camera metadata kept, the import leaves no plaintext folder, a captured movie moves into an owned folder). Not compiled or run in this environment.

## Select all from Photos (2026-11-10)

The iOS photo picker has no Select All, so Add to WagLock now has a second Photos row, **Select all from Photos**, that opens WagLock's own browser (`PhotoLibraryBrowserView`). "Photos & videos" still opens the system picker, which needs no Photos access.

- **Access:** the browser asks for Photos read access only when opened. With limited access it shows only the allowed items and says so. If access is off, it explains that the system picker still works and offers Settings.
- **Selecting:** album chips (All, Videos, Favorites, your albums), tap to toggle, and **Select All / Deselect All** for the album shown. **Drag to select** works as in Photos: a drag that starts sideways selects or deselects the run of tiles from where it started to the finger (the start tile decides which), moving back restores the tiles left behind, and a drag that starts vertically scrolls. The grid has fixed columns so the tile under the finger can be found (`PhotoGridGeometry`). There's no automatic scrolling at the screen edge; scroll with the drag instead. Picks from other albums stay selected. Import follows the order items were selected.
- **Thumbnails:** requested from Photos' image manager and held in memory only. Nothing is written until **Add** is tapped.
- **Import:** for each asset, `PhotoLibraryAssetExport` writes the current photo or video (the same version the system picker's `.current` mode gives) into an owned `waglock-media-import-` folder. Live Photos keep the still and paired video together. `MediaImportService.importLibraryAssets` then encrypts them through the byte-preserving Files path or `importLivePhoto`, inside the usual batch, commit, session, lock and reserve rules. The folder is removed afterwards whatever the outcome. iCloud originals download through iOS.
- **Originals:** the selected identifiers feed the existing "Remove from Photos…" offer, which still needs an explicit tap and the iOS prompt.
- **Albums:** an album's Add menu and actions menu also offer **Select All from Photos**. `AlbumStore.importPhotoLibraryAsset` encrypts each asset into the album's own key domain. Live Photos keep their motion, on this path and on the album's iOS-picker path (via `LivePhotoSupport.resources`): `importPair` imports the still and motion and links them, or keeps neither. Items no longer in Photos are skipped and counted. When the batch finishes without error, a completion sheet offers the same explicit, iOS-confirmed **Remove from Photos…** (`PhotosOriginalsCard`, shared with the main import) for exactly the items added. The album's iOS-picker import ("Import Photos & Videos") shows the same sheet for the items iOS identified, once the whole batch is added. A failed or cancelled batch, or the album locking, offers nothing.
- The Files picker is unchanged.

Tests: `WagLockTests/PhotoLibrarySelectionTests.swift` (Select All and Deselect All per album, drag-to-select ranges and grid hit-testing, order, Live and edited resource choice, unsafe names, owned folder) and `AlbumLivePhotoTests.photoBrowserPairsAreLinkedOrNotKeptAtAll`. Not compiled or run in this environment.
