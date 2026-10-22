# Document preview session boundary — build 33

[D2S-116](https://linear.app/d2sci/issue/D2S-116), audit A08/A11. This is a bounded legacy-owner lifecycle fix, not a replacement storage format or an independent alternative vault.

## Finding and change

Document-loading tasks retained their input password and could publish decrypted data or raw errors after background suspension, logout or a newer session. The Files pager and gallery actually use `MediaDetailView`; hardening only the separate `FilePreviewView` would not fix that route.

`DocumentPreviewService` now activates only for the authenticated owner, alongside the existing owner export capability. Background suspension, logout and data-secret replacement revoke it. Every activation/revocation changes its revision, including suspension and resumption of the same session UUID. An obsolete session cannot revoke a newer capability.

Each view's `DocumentPreviewModel` owns its data, loading state and redacted error. It snapshots path/extension/password strings on the main actor before starting asynchronous storage loading. It checks session, revision, request identity and cancellation before publishing either success or failure. Revocation synchronously clears subscribed models. Closing a view cancels only that model and clears its data; unrelated previews are not cleared by another view's dismissal. A late worker cannot reopen a closed preview or replace a newer request.

The actual Files/gallery route uses this model for PDF, plain text, Markdown, JSON, CSV and log documents. `FilePreviewView` uses it for its in-memory preview paths too. Foreground views retry loading with current authorization; an unavailable common-document preview offers the existing Retry action. No live SwiftData object is accessed by the loader after suspension. User-visible load failures do not interpolate raw filesystem/decoder errors.

## Validation

Six new tests cover inactive/wrong-session rejection before reading, real buffered encrypted-file round trip, wrong-key redacted failure, clearing already-loaded data, late success/error across background and same-session resumption, new-session publication surviving stale completion/revocation, per-view cancellation, and actual owner/background/resume/logout/Guest Mode authentication integration. Fixtures use disposable roots and an isolated Keychain namespace; no owner media/password is read or reset.

The full unit suite passed **169 tests** (58 XCTest + 111 Swift Testing), including all six new preview cases and all 12 existing export cases. Result: `/private/tmp/waglock-build33-full-units.xcresult`. Signed device compilation passed: `/private/tmp/waglock-build33-device.log`. Both simulator UI regressions passed (`/private/tmp/waglock-build33-ui.xcresult`): system sharing/cancellation/background/fresh share (44.806s), and keyboard switching with existing-library unlock (16.590s). These are regression checks, not document-rendering UI evidence. Physical PDF/text rendering and background/reopen acceptance remain pending.

The first compile required the repository's explicit `internal import Combine` convention. An initial synchronous test reproduced a malloc abort in `swift_task_deinitOnExecutorMainActorBackDeploy` while releasing the newly introduced service on iOS 18.4. Explicit nonisolated teardown avoids that runtime path for the new service/model. The unchanged synchronous test and the complete suite subsequently passed. Do not describe the initial interrupted test run as successful; targeted passing result: `/private/tmp/waglock-document-preview-deinit.xcresult`.

## Remaining limits

- This rejects late publication and releases view-owned references; it does not guarantee immediate erasure of Data/String copies, PDFKit state, OS decoder caches or filesystem blocks.
- The underlying storage queue may finish a read/decryption after cancellation. Its result is discarded. Streamed documents still use the inherited protected temporary-file read/delete path; deletion failures, crash leftovers and bounded-memory rendering need separate work.
- Generic QuickLook documents, media image/video decoding, audio, album previews and recording retain separate lifecycle findings. This change does not claim those paths are fixed. Existing metadata/thumbnails/notes encryption and recovery findings remain open.
- No source/root path restriction or new file format is added to the underlying general-purpose storage API here. A future independent vault must receive its own storage/context rather than reuse this owner capability.

Signed build 33 installed successfully on the owner phone (`/private/tmp/waglock-build33-install.log`). Physical document preview acceptance is pending; installation is not runtime evidence.

## Build 33 owner failure and build 34 correction — 2026-10-22

**Build 33 failed physical acceptance.** Owner reported Load Failed and termination when returning from background while viewing a PDF; a second launch showed login normally. Both retrieved WagLock-only phone crash reports identify version 33 and agree on a SwiftData assertion through `MediaItem.fileExtension` → `MediaDetailView.usesSessionDocumentPreview` during sheet dismissal. No user media or application-data container was copied. Raw device reports remain local, outside the repository.

The screen was still rendering while its originating ModelContainer had closed. Build 34 captures immutable presentation/read metadata while the library is mounted. Files sheet identity and pager entries are also stable values, with detail snapshots created on selection rather than recreated by reading old records during dismissal. Source model references remain only for actions gated by the originating authenticated session; video deletion rechecks after suspension before writing.

Capability revision changes now drive common-document loading after the application's lock/resume decision. Suspension no longer falls through to the Load Failed UI. Revocation still clears plaintext and rejects late results. PDFKit teardown detaches its document/delegate, cancels the overlay timer and rejects queued page notifications; page bindings are published after UIKit updates rather than during SwiftUI view construction.

A hosted real-PDF regression test exercises rendering, revocation, authorized resume and logout with the disposable library released while the preview still exists. Validation and replacement-build installation are pending below. These changes preserve app identity, credentials, schema and encrypted originals.

Validation notes: the first hosted test window was not attached to the active UIWindowScene and never rendered; attaching the test window corrected the harness. The actual rendered PDF revoke/resume/logout case then passed in `/private/tmp/waglock-build34-rendering-v3.xcresult`. The combined regression run subsequently passed that case and both UI workflows but **was not a clean full pass**: delayed SwiftUI release of its fixture AuthenticationViewModel exposed an iOS 18.4 back-deployed isolated-deinit abort in `KeychainService`. Its stack differs from the phone's SwiftData assertion. Explicit nonisolated, empty KeychainService teardown avoids the runtime release path without reading, changing or deleting credentials. The final full suite includes a second hosted case using the actual Files pager. Final results are recorded below when complete.

### Final build 34 evidence

Complete units passed **171 tests** (60 XCTest + 111 Swift Testing), including both real PDFKit hosted regressions: the detail screen and actual Files pager render, revoke access, resume, then survive logout and release of the fixture library while still hosted. No malloc abort or SwiftUI state-during-update warning was found in this final run. `/private/tmp/waglock-build34-final-units.xcresult` and `.log`. The signed device build passed: `/private/tmp/waglock-build34-signed.log`. Inherited warnings in other files remain. Phone installation/UI regression results follow separately; owner acceptance of the original PDF background path is still required.

Build 34 installed successfully as an update (`/private/tmp/waglock-build34-install.log`). No uninstall, credential reset or library conversion was performed. Owner phone PDF retest remains pending.

Final UI regressions also passed for the signed-source candidate: sharing/cancellation/background/fresh-share and keyboard switching/unlock (`/private/tmp/waglock-build34-final-ui.xcresult`). Device inventory confirms WagLock Dev 1.3.8 (34). Physical acceptance of the original PDF flow remains pending.

**Build 34 owner phone result (2026-10-22): passed.** Owner repeated the requested two PDF open/background-or-lock/foreground/unlock/reopen cycles and reported success, without the prior Load Failed/termination. This completes the functional retest, not the broader audit.
