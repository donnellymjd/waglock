# Session-bound plaintext exports — build 32

Linked work: [D2S-115](https://linear.app/d2sci/issue/D2S-115), [D2S-116](https://linear.app/d2sci/issue/D2S-116), audit A08. This is an incremental legacy-owner service boundary. It does not enable an independent alternative vault, replace the storage format, convert existing media or adopt Cryptomator.

## Finding and change

The inherited exporter used one temporary directory for every operation. Starting another export deleted that directory. Cancellation and failures could leave plaintext behind. A queued worker retained live SwiftData models and could return URLs after its originating authentication session ended. Export filenames were joined directly to a filesystem path. Cancelling an old system share could clean a newer export's global folder.

`ExportService` now requires the selected authenticated session ID. Only owner authentication activates the legacy owner exporter; current Guest Mode receives no export capability. All five photo/file/video/gallery/batch entry points pass their originating session identity. Background suspension, logout and session-key replacement revoke that capability, cancel its jobs and invalidate ready output. Returning to the foreground reactivates only the still-authorized owner session. A different service/root will be required for any future independent vault.

The main actor snapshots only the necessary filename/source URL fields before background decryption. Workers never access live SwiftData models. Every operation has an opaque UUID folder under the app's known plaintext-export cache, protected with complete file protection. Source paths must refer to regular files directly inside the existing owner media root; valid historical absolute paths within that root remain supported. Sources outside the root and source/root symbolic links are rejected. Export names cannot contain path separators, controls or colon; duplicate or filesystem-equivalent names receive a suffix rather than overwrite another item. Existing ciphertext and database records are never edited or removed by export.

Cancellation is per operation. An active worker retains responsibility for its own staging folder until it stops, then removes it; no new export deletes another operation's folder. Session revocation prevents late progress, completion or delayed batch-share presentation from publishing stale results. Failed jobs clean only directories they actually created. Ready jobs are removed on revocation, share cancellation or dismissal. Successful system handoff has a short cleanup grace period. Cleanup callbacks identify their own URLs/jobs and cannot delete a newer export.

If removal fails temporarily, the exporter retains only the exact owned directory for retry when the app becomes active or the next owner session begins. It does not sweep arbitrary temporary files or infer that unknown ciphertext is orphaned. Startup removes the explicitly known current/legacy plaintext export caches. This is separate from encrypted media storage and never scans/deletes the library.

The share wrapper observes revocation and dismisses invalid managed output. Screens reset pending-share state on background, and delayed batch presentation rechecks the live job. The unsafe force-cast of arbitrary share items into URL arrays has also been removed.

## Validation

The complete unit suite passed **163 tests** (52 XCTest + 111 Swift Testing), including 12 export cases. They cover real encrypted-file round trips, duplicate names with different bytes, independent output lifetimes, partial corruption, wrong keys, rejected foreign/symlink paths, path-bearing names, metadata mutation after scheduling, late decryption after revocation, explicit per-job cancellation, cleanup retry failure, retained legacy absolute paths, and real owner/background/logout/guest authentication integration. Fault tests use disposable roots, synthetic bytes and independent test Keychain services.

An early filename assertion used `txt` instead of the model's stored `.txt` convention; the fixture was corrected. A redirected-root test exposed URL resource-value checks that were insufficient for this boundary. Fresh filesystem type and canonical-leaf checks now reject that case. Cleanup tracks actual directory ownership, including failed preparation, and preserves unrelated files. The final full result is `/private/tmp/waglock-export-cleanup-full.xcresult`, with matching `.log`.

The final focused export suite passed all 12 cases after the preview lifecycle hooks were added (`/private/tmp/waglock-build32-final-regression.xcresult`). The real simulator share workflow passed with readiness predicates (`/private/tmp/waglock-build32-share-stable.xcresult`): import synthetic app-icon media, share, cancel, share again, background, return and share afresh. Earlier selector/transition failures were test synchronization issues; the final workflow waits for actual foreground controls. Guest/keyboard UI regressions also passed during this work. A [synthetic share-sheet screenshot](evidence/build32/synthetic-photo-export.png) records the system UI.

The signed build succeeded (`/private/tmp/waglock-build32-final-device.log`) and installed on the owner’s phone; installed metadata confirms WagLock Dev 1.3.8 (32), unchanged bundle identity. Remote launch was denied because the phone was locked; no runtime success is claimed from installation. Physical export/receiver acceptance remains pending. Use disposable sample media; simulator results do not establish target-app behavior or cleanup under a physically locked phone.

## Limits and remaining work

- OS share recipients can retain copies they already received. Revoking local URLs cannot retract those copies or erase a receiver's caches. Background revocation intentionally removes local availability and can interrupt a receiver that has not finished opening a file; system-target/hardware checks remain necessary.
- An already-running synchronous decryption may finish before cancellation is observed. Its result is suppressed and its owned staging output is cleaned afterward. This does not guarantee immediate memory erasure, secure deletion of filesystem blocks, or completion of cleanup while the OS denies access. File protection and later retry reduce exposure; actual locked-device behavior still needs device evidence.
- Filesystem checks reject known traversal/symlink cases, but are not descriptor-relative protection against a concurrently malicious process replacing directories between checks.
- This covers `ExportService` and its five legacy media callers. Audio, album previews, generic decrypted-file previews, recording, settings, caches and the metadata index still need their own domain review. Existing plaintext SwiftData metadata/thumbs and recovery limitations remain open findings.
- No independent alternative-vault, forensic invisibility, complete recovery or security-audit completion claim follows from this change.

## Owner phone acceptance — 2026-10-22

Owner reported **passed** for installed build 32: disposable-media share/cancel, a fresh share with a readable received sample, background/lock during sharing followed by unlock and a fresh share, and normal password/Face ID unlock. This is functional physical-device acceptance of the requested workflow, not forensic cleanup verification or completion of the broader audit.
