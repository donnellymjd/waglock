# Session-bound library writes — build 43

D2S-105 / D2S-116 / D2S-143. October 22, 2026.

## Active application changes

All 27 explicit application model-save sites now use `LibraryWriteCoordinator`: imports, albums and protected catalogs, notes, media edits, favorites and deletions. The authenticated mount registers a lease bound to its session, scope, generation and mount ID. Lock/invalidation revokes that lease; retained managed contexts cannot fall back to a normal save. Guest mounts cannot write. Main-context automatic saving is disabled so it cannot bypass the boundary. Unmanaged preview/test contexts keep ordinary SwiftData behavior; this is an internal application boundary, not a sandbox against arbitrary code calling SwiftData directly.

The installed owner library still uses the same persistent SwiftData schema, paths and credentials. This change does **not** encrypt that database or resolve A01. Native media readers, passwords and bundle/Keychain identity are unchanged.

A failed native save is conservatively uncertain for resource cleanup until remount. Imports retain potentially referenced ciphertext, and album setup/protection changes retain potentially referenced new biometric keys. No orphan scan or automatic deletion is introduced. Gallery deletion now requires an actual model context before removing ciphertext. Explicit successful saves still precede deletion of their former resources.

## Dormant encrypted repository integration

`EncryptedLibraryRepository` uses the same gateway with the encrypted metadata candidate. It requires an explicit new root, domain and key; there is no production mount factory, default-root discovery, key provisioning or existing-library conversion. It verifies/decrypts the index into a memory-only SwiftData projection with automatic saving disabled. Model mutations are encoded and committed to the authenticated encrypted index before the in-memory save completes. Exact context identity, authorization and expected revision are checked. Revocation, stale revisions, uncertain SQLite commit or a projection failure after a durable commit require reopening; cleanup must retain resources for reconciliation. Weak registry references avoid retaining the repository through its save closure. Managed-context tombstones prevent a released/revoked backend from silently succeeding with a memory-only save. Managed main contexts are recognized by weak identity before reading `context.container`, which can trap after its owner has been released.

Pending model capture uses explicit fetch descriptors with pending changes included. SwiftData batch enumeration in the first test run omitted unsaved inserts/deletes; the adapter now distinguishes clean migration snapshots from pending memory-projection commits. The clean staging contract is unchanged.

This candidate supports only the three typed model kinds. It rejects auxiliary stage/draft/settings records and is **not** a complete staged-library reader. It is bounded to 20,000 records, 64 MiB total encoded model data and 128 mutations per atomic save; these are candidate resource bounds, not newly enabled product import limits. Whole-library projection/diff costs and raw thumbnail sizes require scale work before activation. All supported production imports still use the legacy backend.

## Required before activation

Complete auxiliary records and every settings/draft writer; provision and recover a password-backed root key safely; coordinate source freeze and WAL-consistent capture; verify complete staged inventory and owned ciphertext; design crash-safe atomic activation, rollback and explicit source retirement; resolve scale/memory/transaction bounds; and validate update/recovery on disposable device libraries. Whole-copy rollback protection remains open. Never use these tests as authority to convert the owner's library.

## Regression coverage

Gateway/repository tests cover legacy authorization and retained-context revocation, replacement leases, exact model insert/edit/delete/reopen fidelity, precommit failure, uncertain commit, post-commit projection failure, wrong contexts, failed native-save cleanup, encrypted-binding downgrade rejection, stale no-op saves and repository release. The repository-release regression retains only the managed context and confirms that saves/cleanup are rejected before consulting its released container. Model access itself still requires a live container; callers must not dereference dismissed models.

The final full suite passed 260 tests (149 XCTest +111 Swift Testing). All three selected application UI flows passed. Signed development and unsigned opt-in store Release builds passed; build43 installed/launched on the owner phone. The build summary records local evidence paths. A rendered SwiftUI probe also verifies the attached environment retains the managed main context with automatic saving disabled. Phone acceptance remains separate from simulator evidence.
