# Live Photos

Status: implemented in source on 2026-11-10. Not compiled, run or tested on a device. Kill switch: `LivePhotoSupport.isEnabled`.

A Live Photo is a still (usually HEIC) and a short paired video (MOV) that share a content identifier: Apple maker-note key 17 in the still, and `com.apple.quicktime.content.identifier` in the video. WagLock keeps both files unchanged, each encrypted and ciphertext-bound like any other media.

## Model

A Live Photo is **one** library item: the still's `MediaItem`, plus two optional fields, `livePhotoVideoPath` (the motion's encrypted path) and `livePhotoVideoExtension`. Counts, grids and selection treat it as one photo. `MediaItem.encryptedPaths` lists every ciphertext an item owns, and every delete path removes all of them:

- the Library and Photos grids
- the viewer
- the legacy gallery
- import rollback
- uncommitted-file cleanup

The encrypted metadata codec and the backup snapshot's field inventory both list the two new fields. Records written before this change decode with no motion.

## Import

- **Photos picker:** when the picked item loads as a `PHLivePhoto`, `PHAssetResource` and `PHAssetResourceManager` write its original `.photo` and `.pairedVideo` resources into an owned, protected temporary folder, and both are encrypted. If iOS withholds either resource, WagLock imports the still alone, as before.
  - Needs a device check: whether picker-vended Live Photos release the paired video without Photos library access.
- **Files** (this also serves Private Photo Vault exports): a still and a video picked together become one Live Photo only when they have the same base name *and* the same content identifier. Anything else imports as separate items. The paired video is not imported twice, and "Delete originals…" covers both files.
- **All or nothing:** if the motion can't be saved, for example because reserved space is full, the still is removed too and the item fails like any other.

## Viewing, export and albums

- A LIVE badge appears on grid tiles and in the viewer. Tapping or pressing the viewer badge plays the motion in `PHLivePhotoView`, from decrypted temporary copies that are removed when playback ends, on swipe, on lock or background, or on session change.
- **Export and share** include both files, with the same base name.
- **Save to Photos as Live Photo** (viewer menu) rebuilds a real Live Photo with `PHAssetCreationRequest` (`.photo` + `.pairedVideo`). It asks for add-only Photos access the first time and removes its temporary copies afterwards. The saved copy is outside WagLock.
- **Moving into an album:** albums store one file per asset, so the motion moves in as its own album video beside the still. It is decrypted and verified like the still before the originals are removed, and is never dropped. Albums don't play Live Photos yet.

## Backups

No archive format change. The snapshot adds the motion as a sibling video asset in the same domain, with the same base name (`IMG_0001.HEIC` + `IMG_0001.MOV`) and a stable derived ID (`LivePhotoSupport.motionAssetID`). The recovery tool therefore writes both files side by side, which is how Files exports Live Photos and how Photos on a Mac re-pairs them on import. A missing or unreadable motion file fails the snapshot rather than being left out. That layout still needs an end-to-end recovery check.

## Not yet done

- Live Photo playback inside albums.
- A Live Photo can't be created from an album back into the Library.
- The Library's own size figure counts the still's size only.
- Device checks for picker resources, playback from temporary files, Save to Photos, and recovery of a backup containing a Live Photo.

Tests: `WagLockTests/LivePhotoSupportTests.swift` covers:

- stable, distinct motion IDs
- pairing only on matching name and identifier
- both files stored as one item
- a half pair removing the still
- older records decoding without motion
