> October26 current review: [launch closeout](audits/launch-closeout-2026-10-26.md) and [pre-launch ledger](../release/prelaunch-status.md) supersede historical build50/53 hold statements below. D2S-178 is closed after accepted63; current64 is the dated-backup follow-up. Account/export/signing gates remain separate.

# Security review launch triage — build51 work

Submission is on hold. Build50 archives/screenshots/source freezes remain historical and must not be submitted after this review. The owner supplied a 13-item security review and authorized the easiest safe 1.0 mitigations, explicitly including turning calculator login off. Preserve owner credentials, keys and all vault data. Do not silently replace formats, raise implicit KDF parameters, migrate legacy libraries, scan-delete unknown temporary files or add destructive lockout.

## Scope

Calculator login is retired across entry points and its redundant password-copy code removed. Pure arithmetic is not an authentication mechanism. Old calculator preferences/secret accounts are narrowly cleaned; no other credentials are reset. The now-unused sessionLoginPassword String is removed. Main/album password attempt reservations are persisted before verification with a five-attempt initial budget and increasing bounded cooldowns, without erasure. Correct password completion only resets its own current reservation; biometric cancellation does not charge/reset a password budget.

Remaining release work prioritizes owned temporary plaintext cleanup, path containment and explicit release packaging boundaries. Versioned KDF/record-binding changes require compatibility evidence; the legacy Dev store remains excluded from the fresh encrypted release. Screen capture and background-memory policy require a recorded supported behavior, with no screenshot-prevention or zeroization guarantees. Findings are closed only after relevant regression evidence, with residual work explicitly retained.

[Original report](audits/2026-10-23-owner-security-review.md). Linear mapping: report items1–13 are D2S-152 through D2S-164, respectively, under WagLock; related broader audit D2S-105/116 stays open.

## Implemented launch mitigations and remaining work

| Finding | Linear | Current disposition |
| --- | --- | --- |
| 1–2 | D2S-152, D2S-153 | Calculator UI/authentication and device-derived password-copy implementation removed; scoped old-copy cleanup and forged notification tests. |
| 3–4 | D2S-154, D2S-155 | Keychain-backed reservations before verification; initial five guesses, 5/10/20/40/60-minute cooldowns; scopes independent; corrupt/unavailable state rejects unlock. Face ID does not reset password budget. Clock manipulation/extracted ciphertext is outside this online limit. |
| 5 | D2S-156 | Public release still requires fresh encrypted metadata. Package checker verifies public identity, encryption flag and signature. Legacy Dev remains separate; never distribute its default configuration as the release. |
| 6 | D2S-157 | New/password-changed owner and album wrappers use the [versioned 600,000-round envelope](password-envelope-v1.md); existing reads do not convert. Automated integration passes; device checks pending. |
| 7 | D2S-158 | New document/video/audio/album plaintext jobs use protected, marked exclusive directories; startup removes only recognized abandoned jobs. Existing close/revocation cleanup remains. Historical anonymous temporary files are not safely identifiable and are not scan-deleted. |
| 8 | D2S-159 | Legacy weak verifier readers remain for Dev compatibility. Current owner writes use authenticated wrappers. Newly required 1.0 Guest Mode must use independent modern credentials, not enable the old SHA-256 guest path. |
| 9 | D2S-160 | Fresh release flushes notes, synchronously revokes registered library keys/leases and clears the vault session on background. The same revocation runs on session-key replacement, including password changes. Timed/Never preferences cannot override this. New audio recording is deferred for release; imported audio stays available. Dev retains its old recording behavior. |
| 10 | D2S-161 | Redundant sessionLoginPassword removed. Swift String/CryptoKit copies and complete memory zeroization remain unproven; do not claim full zeroization. |
| 11 | D2S-162 | Native v2 order/length/end authentication retained. Legacy v1 reader and media-to-entry binding remain explicit work; do not silently rewrite files or claim v2 already binds entry identity. |
| 12 | D2S-163 | Stored reads/deletes/size/existence reject traversal, foreign absolute paths, NULs, directories and symlinks. Legitimate old absolute aliases within the flat owned root remain readable. Checks are not a race-proof filesystem sandbox. |
| 13 | D2S-164 | Detected recording/mirroring replaces content with an opaque privacy message, revokes the session and stops audio playback. Physical capture behavior still needs testing. Ordinary screenshots, first-frame races and external cameras are not prevented. |

The full unit/security suite passed **292 tests** before the additional password-envelope integration. Result: `/private/tmp/waglock-build51-full-security-final.xcresult`. Earlier runs included an old-iOS isolated-deinit crash (corrected with the repository's existing nonisolated-deinit workaround), one bootstrap SIGTERM, and a superseded full run stopped after obsolete calculator expectations and out-of-root PDF fixtures failed. These are recorded limitations, not hidden successful runs. Final post-envelope suite supersedes this count: **297 passed, zero failures/skips**, `/private/tmp/waglock-build51-post-envelope-full.xcresult`; independent vector plus initial credential/album integration passed32 tests. Release simulator/physical builds succeed, and the simulator package checker verifies encrypted release activation and signing. UI/device acceptance remains pending.

## Updated 1.0 scope

Owner now explicitly requires **Guest Mode for 1.0**, D2S-115 Urgent. The existing guest branch is an empty in-memory view with a fast legacy verifier and blocked writes; removing the current release guards would not create the requested usable independent vault. Implement independent credentials, keys, encrypted indexes, media roots and scoped service capabilities. No blanket preference flip or presentation-only mode is accepted as its security boundary. No submission until those tests and physical acceptance pass.

## Final session-boundary follow-up

All298 unit/security tests pass in `/private/tmp/waglock-build51-session-boundary-full.xcresult`. A retained mounted library is synchronously revoked at the session-key replacement boundary, without relying on SwiftUI disposal; drafts/writes/export fail immediately, and committed drafts reopen after both background lock and password change. Earlier direct-logout implementation also passed298 tests, but the central boundary covers every key replacement.

Release UI evidence: the stale-calculator preference/attempt-count relaunch check and password-change persistence pass in the initial combined run; its draft assertion counted virtualized screen cells and failed (8 versus9). The corrected check uses an accessible saved-note count and passes both immediate and old600-second preference cycles in `/private/tmp/waglock-build51-draft-count-ui.xcresult`. Repeated lock and unfinished-draft/background/cold-relaunch checks pass in `/private/tmp/waglock-build51-synchronous-lock-ui.xcresult`. Final password-change/cold-relaunch check after centralized revocation passes in `/private/tmp/waglock-build51-final-password-ui.xcresult`. Captured-screen behavior and physical-device acceptance remain manual gates.

Linear items D2S-152,153,154,155,156 and163 are Done for their verified implementation scopes. The other findings retain the residual/physical/format work described above. No claim of all13 findings resolved is made.

## October24 installation

Build51 is installed over the existing public-identity WagLock app, preserving its library/credentials; filtered phone metadata confirms1.0(51). Remote launch was denied because the phone locked after installation. The owner is asked to open manually and check password changes, retained media, unfinished drafts, Face ID/background locking and capture detection. These checks are pending, not passed. No reset or media/credential inspection occurred. [Device record](device-testing.md).

**October24 owner acceptance:** all four requested build51 phone checks passed. D2S-157 and D2S-160 are now Done, bringing the verified completed findings to8 of13. Already-active screen recording protection passed on the phone; D2S-164 remains open for direct AirPlay/in-app transition coverage. D2S-105 and submission remain open because the broader audit, other findings, independent Guest Mode and account-side gates are incomplete. This result is limited to the requested checks and does not certify the subsequent Guest Mode code.


## October24 — build52 integration checkpoint

Independent Guest Mode is implemented in the public encrypted release and installed for owner acceptance.309 unit/security checks and actual release UI prove normal passcode routing, independent persistent notes/settings and cold reopening; additional snapshot checks reject primary ciphertext referenced by the secondary index. Physical Face ID/backup acceptance is still pending. See [secondary-vault implementation](secondary-vault-design.md). D2S-115, D2S-105 and submission remain open; the remaining findings/review limitations above are not automatically closed by this feature.


## October24 — build52 owner acceptance passed

The owner replied “passed” to the complete requested build52 phone checklist: the existing main library opens; an alternative passcode creates/opens its own photo, note and protected-album library with cold-relaunch persistence and separation in both directions; Face ID can be explicitly assigned to each vault, shows the disclosure warning, opens only the assigned vault and remains locked on cancellation; backgrounded note/PDF behavior works; and a backup made from the secondary vault independently recovers only that vault. No passwords or private media were requested or retained.

D2S-115 is Done for the requested1.0 feature. This is owner-reported physical functional/recovery acceptance paired with309 unit/security tests and3 actual-release UI workflows, not independent audit, forensic-deniability or full security certification. D2S-105 and remaining review findings/distribution gates stay open. Installed candidate remains WagLock1.0(52), implementation cd9741f; no new binary, migration, reset, archive/upload or submission was made for this acceptance record.


## October24 — final build53 acceptance and handoff

The owner passed the final build53 phone checklist: both existing passcodes and assigned Face ID open the expected vault/samples; disposable video/PDF background/resume has no crash, unexpected playback or preview; recording started through Control Center while unlocked blocks viewing until stopped and then requires unlock. Build52 populated-vault persistence and selected-only independent backup recovery acceptance remains recorded. Both vaults and the separate WagLock Dev app were preserved.

Build53 refuses old fast owner/guest verifier slots, native ZNSC v1 reads and native .encrypted imports in the public encrypted release while preserving explicit Dev/recovery readers and modern credentials. No migration/reset/format conversion occurs. Password inputs clear on background/disappearance; logged-out password changes fail closed. Generic media results must still belong to the active originating context after awaits, and late owned plaintext is removed. A deterministic paused video completion/logout regression verifies this boundary.

Verification:314 unit/security tests (186 XCTest +128 Swift Testing),57 focused credential/import/stream tests,7 final media-lifecycle tests,2 actual-release regression UI workflows, both native iPhone/iPad screenshot workflows and16 Python backup-tool tests pass. Official age1.3.2 independently recovers both checked-in public fixture sets; actual encrypted-library MOV/PDF/PNG/WAV payloads, notes/drafts/Unicode, nested passwords and tamper/truncation rejection pass without phone/Keychain. Full suite: `/private/tmp/waglock-build53-full.xcresult`; release UI: `/private/tmp/waglock-build53-release-regressions.xcresult`. An initial lifecycle-test compile failure attempted an unsupported Swift extension override; the corrected injectable loader seam and final runs supersede it.

D2S-158/159/161/164 launch mitigations are Done, bringing completed report findings to12 of13; D2S-115 independent Guest Mode remains Done. D2S-162 stays open for ciphertext-to-record identity binding: a filesystem writer may substitute valid same-vault ciphertext. v2 authenticates framing/order/length/end, not metadata-entry identity. Whole database rollback, legacy Dev metadata, complete memory zeroization and direct AirPlay hardware validation remain limitations. No screenshot/external-camera prevention, secure physical erasure, forensic deniability or independent audit certification is claimed. D2S-105 remains open for broader audit work.

The final development-signed build53 archive/package/signature checks pass. Eight native unedited public-fixture screenshots and copy-ready store metadata/review instructions are prepared. App Store export fails exit70: missing App Store distribution provisioning profile for com.d2sci.waglock. Only a development identity is available; no App Store Connect API credential is configured. Account distribution signing, source/platform distribution review and privacy/encryption/territory/publisher declarations remain external gates. No automatic provisioning update, upload or submission occurred. See [current handoff](../release/app-store/README.md).


## October25 — build57 supersedes prior engineering status

The owner requested completing remaining security engineering before UAT. D2S-162/169/170/173 are implemented with scoped protections and limitations in [build57 evidence](../release/evidence/build-57/README.md) and [the accepted design](security-completion-design.md). Prior build53/55 statements above are historical. Physical acceptance of the new candidate remains pending; no submission/upload is authorized by test success alone.
