# WagLock development docs

*We Always Guard*

WagLock is an independent fork of [SealedPocket / ZeroNet Space](https://github.com/materialofair/zeroNet_Space). This project is based on ZeroNet Space but is not the official version.

- [Portable export implementation experiment](portable-export-design.md): iOS-simulator/macOS writer, independent CLI recovery, nested passwords and integrity gates; not linked to the app.
- [Prioritized backlog](backlog-priorities.md): security/recovery, alternative vault, encrypted Trash, beta preparation and later sharing work.
- [Document preview boundary](document-preview-boundary.md): build 33 revocation and rejection of late PDF/text results.
- [Shared-album discovery](shared-albums.md): two-person E2E sharing, mutual consent, revocation limits, transport options and prototype gates (D2S-139).
- [Session-bound exports](export-session-boundary.md): build 32 operation-owned plaintext output, revocation, safe filenames and cleanup isolation.
- [Password entry and strength](password-entry.md): builds 30–31 shared main/guest rules, switchable login keyboards and advisory scoring only when setting/changing passwords.
- [Authenticated library boundary](authenticated-library-boundary.md): build 29 session-bound database mounting, stale-login rejection and disposable metadata-transition rehearsal.
- [WagLock branding and video thumbnails](waglock-branding-and-thumbnails.md): build 28 rename, stable installed identity, persisted-model compatibility and proportional previews.
- [English-only friend beta priorities](beta-readiness.md): language strategy, free-feature status, audit risks and distribution gates.
- [Secondary passcode / separate alternative vault](secondary-vault-design.md): prioritized D2S-115 requirements, proposed context/key boundaries and tests; current Guest Mode is insufficient.
- [Two-vault isolation prototype](vault-isolation-prototype.md): test-only encrypted context/key/index/storage experiment and production boundaries.
- [Requirements and release gates](requirements.md): product direction, exclusions, issue ownership and evidence needed.
- [Linear requirements snapshot](linear-requirements-snapshot.md): linked source requirements and project issue inventory retrieved 2026-10-17.
- [Architectural decisions](decisions.md): accepted development constraints and proposals awaiting validation.
- [D2S-105 architecture and security audit](audits/D2S-105.md): current implementation, risks, reuse inventory, baseline checks and remaining work.
- [Development build and phone testing](device-testing.md): isolated installation identity, signing, sample-media checklist and automated checks.
- [Nested albums and biometrics](albums-and-biometrics.md): album security modes, key boundaries, Face ID setup and device-bound recovery limitations.
- [Stream integrity hardening](stream-integrity.md): build 23 authenticated stream framing, legacy compatibility, atomic publication and regression evidence.
- [Credential, storage and cache hardening](credential-and-cache-hardening.md): build 24 failure-safe password updates, credential preservation, opaque filenames, low-space handling and cache invalidation.
- [Cryptomator feasibility probe](cryptomator-feasibility.md): pinned isolated experiment, negative completeness result and gates still required before adoption.
- [Import lifecycle hardening](import-lifecycle.md): build 25 commit/session checks, cancellation cleanup and older-runtime compatibility evidence.
- [Migration fidelity test preparation](migration-fidelity.md): disposable fixtures, read-only export comparison and the source-app validation matrix.

Start with these docs and the root [AGENTS.md](../../AGENTS.md). Historical upstream docs remain for provenance and must not be read as audited WagLock promises. The working name is WagLock; the original Linear project is titled Portable Vault. The `docs/portable-vault/` path and source snapshot are retained for continuity. The development build has separate WagLock branding and app/Keychain identity. Build 23 extends the inherited stream format for new writes while retaining legacy readers; it performs no automatic conversion.
