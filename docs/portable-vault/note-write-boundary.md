# Note write boundary — build 38

D2S-116 / D2S-105 security follow-up, 2026-10-22.

## Finding and correction

The editor previously ignored cancellation of its delayed autosave. An older callback could overwrite newer content, recreate a Keychain draft after explicit Save cleared it, or update a SwiftData note after the originating owner session ended.

`NoteAutosaveCoordinator` serializes writes on the main actor under the existing revocable owner capability. Each delayed write captures both the owner session and authority revision, plus a generation token. Cancellation drops the pending write; a delay that ignores cancellation still cannot commit. Authorization is checked again immediately before the storage callback. Background/logout/key changes revoke pending work, including background/resume that retains the same session UUID. Guest construction no longer initializes the draft manager and its legacy migration.

Explicit Save invalidates pending autosave before committing the latest editor text. New-note drafts are cleared only after the database save succeeds. A new editor reloads its authorized draft when shown, rather than retaining a destination snapshot constructed before the prior editor saved. Storage failure keeps the editor open and shows a generic error instead of dismissing or claiming success. Normal Back flushes the latest pending edit only while its original capability remains valid. A new explicit edit/save after an authorized resume uses the current revision.

## Validation

Eight deterministic security tests cover out-of-order completion, canceled delays, real isolated Keychain draft clearing, actual authentication/background/logout/Guest/new-owner transitions, same-session revocation, failed storage commits/retry and single Back flush. The UI integration check creates only disposable notes and verifies explicit Save followed by an empty New editor, plus Back/reopen preserving the latest draft.

Full unit/security run: 181 passed (70 XCTest and 111 Swift Testing). Result: `/private/tmp/waglock-notes-boundary-units.xcresult`. The first combined run passed the units but exposed a stale draft snapshot on Back/reopen. That failure prompted the presentation-time reload; corrected final evidence is recorded in device-testing.

## Remaining boundaries

This does not encrypt persisted SwiftData note fields, add Markdown or implement independent vaults. A01 and D2S-143 remain open. Drafts remain device-only Keychain data with no portable recovery. Capability revocation cancels pending edits; the last unsaved keystrokes may not persist if locking wins the lifecycle race. Failed Back/background flush cannot keep an already-dismissed editor open. Keychain deletion and platform caches do not establish secure erasure. Physical-device acceptance remains separate from simulator validation.
