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
