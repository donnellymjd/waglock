# Draft preservation and source conflicts — build 41

D2S-116/143, 2026-10-22. Build 41 tightens an existing production migration; the encrypted draft adapter remains unused groundwork. No live metadata conversion or identifier change.

## Production correction

`SecretNoteDraftManager` previously removed `secretSpace.draft` from preferences whenever a Keychain draft existed, even when the two drafts differed. A Keychain read failure could also be mistaken for absence by the old unchecked read. Both outcomes risked losing a source or replacing an inaccessible entry.

The manager now requires a checked read. Different drafts are both preserved; the editor continues to use the Keychain draft, and the legacy source remains available to the existing backup collector. There is no merge or conflict-choice UI yet. A legacy draft is promoted only when its three known JSON fields decode and Keychain is genuinely absent. The original serialized bytes must read back identically before the legacy duplicate is removed. The preferences value is checked again before removal so a newer source value is retained. Failed reads/writes, mismatched read-back, corrupt data and future fields preserve the source. Ordinary explicit note save/load/clear behavior is retained.

This tightens the existing duplicate-cleanup path; it is not permission to delete model stores, originals, unrelated preferences or migration rollback data. It is not a cross-store atomic transaction or secure-erasure guarantee. Preserved legacy conflicts may still contain plaintext in preferences: the metadata audit remains open.

## Unused encrypted draft adapter

`MetadataDraftCodec` accepts explicit Keychain/preferences instances or a supplied reader; it has no default global capture and never writes/clears either source. It preserves the exact original serialized JSON, rather than re-encoding draft text/dates. Unknown fields, bad types, invalid JSON, inaccessible sources and oversized drafts fail closed. The raw-draft limit is just below 8 MiB to fit the encrypted index's encoded-record budget; exceeding it blocks staging rather than omitting content.

Each origin receives a fixed logical ID, opaque after domain-bound indexing. Both origins have authenticated records, including explicit absence markers. `MetadataTransitionStage.Scope.modelsAndDrafts` requires both records; the older `.models` scope refuses draft records. Resume compares the declared scope and exact source fingerprint, so adding/removing/changing a draft or silently upgrading a model-only stage is rejected. Model projections refuse drafts; consumers must deliberately decode the draft records separately. No active UI consumer or draft writer has been switched to this candidate.

Preferences/settings, active credentials/biometric registration, coordinated source freeze, live write adapters and reviewed activation/rollback still remain. Capture is not a coordinated snapshot against external writers. See [metadata candidate and gates](encrypted-metadata-candidate.md).

## Validation

- Eight draft-codec tests cover both origins and original bytes, explicit absence, inaccessible sources, malformed/unknown/oversized input, revocation/cancellation, interrupted resume, changed drafts and incompatible scopes.
- Eight production migration tests cover conflicting/identical drafts, successful verified promotion, inaccessible reads, failed writes, mismatched/inaccessible read-back, a changed preferences source, malformed/future fields and ordinary explicit save/load/clear.
- Full unit regression: **247 passed** (136 XCTest + 111 Swift Testing). Signed build 41 compiled successfully. Tests use isolated preferences and injected in-memory Keychain storage; they do not read or mutate owner data.
- Existing simulator note UI regression passed: explicit Save clears its draft; Back preserves the latest edit.
- Physical installation/acceptance is separate. The metadata index/draft stage remains disconnected from phone mounting.

Build 41 subsequently installed and launched on the owner iPhone. Device inventory confirms version 1.3.8/build 41 under the existing identity. Physical workflow acceptance remains pending; installation does not validate the source-conflict fix on owner data. No tools inspected owner drafts/media.

Owner phone workflow acceptance passed: disposable note Back/reopen/save, existing sample access and normal password/Face ID unlock after backgrounding. Synthetic tests remain the evidence for conflicting legacy drafts and failure injection; no owner draft contents were inspected.


## Build49 — visible unfinished notes and background flush

The owner clarified that the build48 note was absent only from the Notes list; it was still recoverable through New. This was a discoverability defect, not confirmed loss of that note. Notes now displays **Unfinished note → Resume draft**, including the draft title (or Untitled note), even when no saved notes exist. Opening it uses the existing draft reader; Done still saves a normal note and clears its draft. New continues to resume the single existing unfinished new-note draft. This does not add multiple simultaneous drafts or change the persisted format. Existing release drafts stay encrypted in the native index; legacy Dev drafts keep their existing Keychain path.

A separate deterministic test confirmed a lifecycle timing gap: a scheduled latest edit could be cancelled when the app revoked document/note authority at background, before the editor's scene callback flushed it. Authentication now requests a synchronous note flush **before** that authority is revoked. Only the currently active matching session is eligible; the coordinator rechecks session, revision and owner authorization at commit. Revocation still cancels timers, and a late completion cannot write after background, logout, guest entry or a later resume. No new session/key lifetime, background access grant, plaintext file or preferences fallback is introduced. Storage failures still report failure and cannot claim a successful save.

Text-field bindings register the latest immutable title/body with autosave synchronously, avoiding reliance on a later SwiftUI change callback. The draft list refreshes when the Notes root appears or returns active; it does not replace an originating navigation link during an editor autosave. The editor describes new-note saving as draft saving. Final build49 regression and physical acceptance evidence is tracked in BUILD_ERRORS_SUMMARY.md and the submission ledger. No owner note contents, passwords or media were accessed.


Build49 verification: all282 unit/security tests pass with no failures/skips. The new controlled-delay test fails on the old implementation (the pending edit is dropped) and passes after the pre-revocation flush; an unrelated session cannot trigger it and a late cancelled timer cannot duplicate it. The actual encrypted release on iOS26.5 passes an88-second UI workflow: background without Done, unlock, see Resume draft, recover exact title/body, cold relaunch, edit/background again, save with Done and verify the draft card disappears, then edit an existing saved note and background/reopen without Done. Evidence: `/private/tmp/waglock-build49-full-regression.xcresult` and `/private/tmp/waglock-build49-note-background-ui.xcresult`. Signed phone build and release package verification pass. Physical installation/owner repetition are recorded separately.
