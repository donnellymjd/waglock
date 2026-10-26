# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version format: `major.minor.patch`; the `[Unreleased]` section records changes not yet submitted to the App Store.

The entries below record the development-app history inherited from the upstream ZeroNet Space project (translated to English). WagLock 1.0 release work is tracked in [BUILD_ERRORS_SUMMARY.md](BUILD_ERRORS_SUMMARY.md) and `docs/release/`.

## [Unreleased] - 1.3.8

### Fixed

- Calculator disguise login now verifies the main password hash directly, fixing cases where a changed device vendor ID or an outdated password copy stopped the correct password from unlocking

## [1.3.6] - 2026-09-22

### Added

- App icon selection added to the existing VIP benefits, with four exclusive icons (Paper, Calculator, Pebble, Ruler; five including the default) and a free way to restore the default
- Redesigned the default teal-ring icon and its in-app preview

### Improved

- Icon picker is now a compact list with smaller previews and a trimmed VIP section
- Launch and login screens share the teal-ring look; the launch screen adapts to light and dark appearance

- Removed swipe-to-share on the recordings list but kept the share button; swiping is disabled during playback, and the row with an expanded player stays non-swipeable after pausing
- Audio shows a loading state while loading and blocks repeated play taps
- Recording sharing now decrypts in the background, can be cancelled while preparing, and cleans up temporary files
- When saving a recording fails, the app clearly says the content was kept and offers retry and discard

## [1.3.5] - 2026-09-06

### Added

- **Voice memos and recording**: recording and audio playback management, with keep-alive for long background and lock-screen recording
- **Unified import entry**: photos, files and audio are imported from one sheet for a simpler flow
- **Recording share controls**: sharing and export protections tied to VIP membership

### Improved

- **Leaner tab bar**: videos and audio merged into one tab; Notes and Settings are separate tabs
- **Import sheet**: simplified layout with a prominent encryption notice

## [1.3.0] - 2026-08-16

### Added

- **Double-tap to seek**: double-tap the left or right half of the video to jump ±10 seconds, with an animated direction indicator in the center
- **Volume slider**: a volume slider in the player's bottom bar (icon changes with volume); the mute toggle remains
- **Buffering indicator**: a spinner in the center while video buffers or loads
- **Auto-hiding controls**: controls hide after 3.5 seconds of inactivity during playback and reappear on tap; they stay visible while paused or scrubbing
- **No auto-lock during playback**: the system idle timer is disabled while video plays and restored on pause or exit

### Improved

- **Video sound with the silent switch on** (core fix): activates the `.playback` audio session so video sound ignores the silent switch; playback pauses in the background, and the audio session is reference-counted across players
- **End of playback**: returns to the start and shows a replay button instead of getting stuck in "paused"
- **Continuous scrubbing**: removed the 1-second step; loose tolerance while dragging, precise seek on release
- **Uniform speed buttons**: the 0.5x/1x/1.5x/2x capsule buttons have a fixed size
- **Call/alarm interruptions**: playback pauses on interruption and resumes when the system allows
- **Downsampled photo decoding in Photos/Files**: detail previews decode on a background thread with a pixel cap, so large images no longer stall the main thread

### Fixed

- Plaintext temporary file leak caused by non-cancellable player decryption tasks (when leaving the player mid-way)
- Reading decrypted data to sniff the format magic loaded the whole encrypted file into memory (peak memory for large files roughly halved)
- Decrypted images stayed in the memory cache after logout or a password change
- Thumbnail cache keys lacked a content fingerprint, and failed decodes were retried repeatedly
- The inline preview and full-screen player deactivated each other's shared audio session, cutting off sound

### Security

- Plaintext temporary files produced by decryption (video/documents) use `.completeFileProtection`
- Temporary file extensions are sanitized to prevent path injection
- Unified the photo decryption pipeline to be ZNSC-streaming aware, removing the dual-pipeline risk
- The archive build-number script now requires a successful archive, so failed archives no longer bump the build number
- Removed the source backup file `MediaDetailView.swift.backup` that had been bundled into the app by mistake

---

## [1.2.0] - 2026-08-03

### Added

- **Swipe between photos**: after opening a photo, swipe left/right to the previous/next one without closing it; a page counter (e.g. `3 / 12`) and gesture hint appear at the bottom
- **Photo search**: search Photos by file name or extension
- **Batch photo delete**: a new "Select" toolbar action lets you pick or select all, then delete in bulk
- **Swipe between file previews**: after opening a PDF/document from the file list, swipe left/right to switch files
- **Direct purchase for "Unlock unlimited imports"**: when the free import limit is reached, the in-app purchase can be started from the import screen; it takes effect immediately and closes the import screen
- **One-tap retry on load failure**: when decrypting or loading an image, video or file fails, the error screen offers a "Retry" button

### Improved

- **No duplicate video controls**: removed the overlap between the system controls and the custom control bar, keeping one set (play, ±15 seconds, progress bar, speed, mute)
- **Pan limits when zoomed**: panning a zoomed image stays within the frame, so it can't be dragged off screen and lost; zooming back to 1x re-centers it
- **Import success feedback**: after importing, the app shows "Import successful, N files imported" instead of closing silently
- **Consistent purchase state**: purchases, restores and transaction updates all sync to the persisted unlock state, so "purchased but still limited" no longer happens
- **Adaptive calculator login screen**: button sizes are computed from the available area, fitting landscape, split view and different devices
- **Hardened deletion**: a failed video delete now shows a clear error instead of failing silently; when the database delete fails, the player stays usable

### Fixed

- Photo preview couldn't swipe between images (the drag gesture stole the paging gesture)
- "Unlock unlimited imports" reported "product not found" if Settings had never been opened
- Cancelling a purchase wrongly showed an "Error" alert

---

## [1.1.0] - 2026-07-09

### Added

- **Auto-lock after leaving**: Settings → Security, with Immediately / 1 minute / 5 minutes / Never (default Immediately)
- **Background privacy cover**: when switching apps, the app switcher shows only the launch screen instead of photos, videos or notes

### Improved

- Deleting photos, videos or files now asks for confirmation and makes sure encrypted data is removed from the device
- Secret note drafts are now stored encrypted in the Keychain
- The photo viewer no longer carries the previous photo's zoom when paging

### Fixed

- "Unlock unlimited imports" reported that the product was not found (product ID regression)
- Deleted items occasionally reappeared in lists
- Password credentials for users upgrading from older versions are migrated automatically (Keychain service migration)

> Note: 1.1.1 (build 8) was an internal build that was never released publicly; its changes are included in 1.2.0.

---

## [1.0.0] - 2025-11-05

### Added

- Zero-network offline private space: encrypted storage and browsing of photos, videos and files (AES-256, local encryption, no network requests)
- Calculator disguise login mode
- Private notes
- Unlimited imports in-app purchase (`com.zeronetspace.unlimited_imports`)
- Guest mode
- Demo mode (App Review demo code `0.00000` automatically unlocks premium features)
- 100% open source

[Unreleased]: https://github.com/materialofair/zeroNet_Space
[1.3.6]: https://github.com/materialofair/zeroNet_Space/releases/tag/v1.3.6
[1.3.5]: https://github.com/materialofair/zeroNet_Space/releases/tag/v1.3.5
[1.3.0]: https://github.com/materialofair/zeroNet_Space/releases/tag/v1.3.0
[1.2.0]: https://github.com/materialofair/zeroNet_Space/releases/tag/v1.2.0
[1.1.0]: https://github.com/materialofair/zeroNet_Space/releases/tag/v1.1.0
[1.0.0]: https://github.com/materialofair/zeroNet_Space/releases/tag/v1.0.0
