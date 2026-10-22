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
