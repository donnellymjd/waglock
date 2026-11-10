# Fixed-size storage (ADR-030)

Status: implemented in source on 2026-11-09. Not compiled, tested or reviewed. Requested by the owner after the Graphite handover, whose storage table and "Container deniability" reviewer ask this answers in part.

## What it does

The handover asks that "Fixed size" make WagLock's size on the iPhone reveal only the size that was chosen, not how much any library holds or how many libraries exist. Standard mode, the default, grows as needed and lets iOS storage settings show WagLock's real size.

In Fixed mode WagLock keeps one **reserve** file of pseudorandom bytes. It is sized so that everything in WagLock's app container adds up to the chosen size:

```
every library + metadata + settings + reserve  =  fixed size − 64 MB headroom
```

- **Writes:** every media write goes through `FileStorageService.checkStorageSpace`, which first asks `StorageReserve.claim(bytes)` to take the bytes out of the reserve, by truncating it, before writing. If the reserve can't give them up, the write fails with `FileStorageError.reservedSpaceFull` and the Reserved space full screen appears. The check runs before the device free-space check, so the truncation also frees the matching device space.
- **Deletes:** `FileStorageService.deleteFile` invalidates the cached usage and posts `wagLockStorageChanged`. `StorageReserveCoordinator` then grows the reserve back quietly.
- **Allocation:** switching to Fixed, or growing it, writes 4 MiB chunks of AES-GCM keystream under a throwaway key. The file is fully allocated and doesn't compress, so it isn't sparse or zero-filled. Allocation pauses when WagLock leaves the foreground and resumes on the next foreground. Above 512 MB, the Switching storage screen shows a percentage and the time left, never bytes.
- **Standard:** switching back deletes the reserve. Library files, stores and keys are never moved, rewritten or converted in either direction. That is why a switch is an allocation rather than the handover's "copy everything, verify, then delete".
- **Erase:** explicit erase removes the reserve and the mode file along with the other WagLock roots, so WagLock returns to Standard.

The mode file (`Application Support/WagLockStorageMode.json`) is app-wide and not secret. A malformed mode file fails closed: writes stop rather than silently leaving Fixed mode. The reserve is excluded from iCloud and device backups.

Sizes are 8 GB, 32 GB or a custom 2–180 GB. A size must exceed what WagLock already holds, and the growth it needs must leave at least 1 GB free on the iPhone.

## Screens

- Onboarding step 2 (Standard "Most people" / Fixed size 8 GB or 32 GB; the choice is applied after the first library opens).
- Settings › Storage mode card: Change size…, Switch to Standard, Switch to fixed size….
- The size sheet.
- Switching storage: percentage, time left, Pause / Resume.
- Reserved space full: Grow reserved space, Free up space here, Switch to Standard, Not now.

All of these are app-wide, render the same in every library, and never show container usage or any library's size.

## What it does not hide (reviewer items)

1. **Files on disk.** Someone with a forensic image or the app container still sees each library's directories and Keychain namespaces, and the reserve file itself; see [library slots](library-slots.md) item 1. The reserve keeps only the total size constant, which is what iOS storage settings and device-level free space reveal.
2. **Short bursts.** Temporary files for previews, exports, backups and imports in progress, plus SwiftData journals beyond the 64 MB headroom, are not claimed. While they exist, WagLock is briefly larger than the fixed size, until they're removed and the reserve regrows. An observer sampling sizes at those moments sees the deviation.
3. **Change events.** Resizing and switching modes are visible size jumps, as the handover's table says. Free space on the iPhone also changes as the reserve is allocated.
4. **Device backups.** The reserve is excluded from iCloud and device backups, so a backup's size still reflects real usage.
5. **Usage measurement** walks WagLock's whole container and sums allocated sizes. Its cost grows with file count; it is cached between writes and recomputed after deletes.

## Code and tests

- `WagLock/Services/StorageReserve.swift`: mode file, measurement, claim, allocation.
- `WagLock/Services/StorageReserveCoordinator.swift`: progress, pause/resume, regrowth.
- `WagLock/Views/Settings/StorageViews.swift`: the screens above.
- Hooks in `FileStorageService`, `MediaImportService`/`ImportViewModel` (a batch stops cleanly when space runs out and keeps what it already committed), `WagLockApp` and `VaultResetService`.

`WagLockTests/StorageReserveTests.swift` uses megabyte limits on disposable directories. It covers:

- Standard mode as a no-op
- a constant total through writes and deletes
- a full reserve rejecting a write without changing anything
- size and device bounds
- Standard releasing only the reserve
- resuming an interrupted allocation
- non-zero filler excluded from backup
- a malformed mode file failing closed
- `FileStorageService` mapping a full reserve to `reservedSpaceFull`

None of this has been compiled or run, and allocation speed and battery cost on a real iPhone are unmeasured.
