# Linear requirements snapshot

Retrieved 2026-10-17 (America/New_York). Source updated 2026-10-17T03:18:27.984Z. This is a source snapshot, not a statement that these capabilities exist. See [requirements.md](requirements.md) for implementation guidance and [decisions.md](decisions.md) for proposal status.

Source: [Product requirements and release gates — Portable Vault](https://linear.app/d2sci/document/product-requirements-and-release-gates-portable-vault-20b0d84aa2c2). Project: [Portable Vault — SealedPocket Fork](https://linear.app/d2sci/project/portable-vault-sealedpocket-fork-10d5618162e3).

# Portable Vault — product specification (draft)

## Audience and promise

Users with sensitive, long-lived photo/video libraries who want a true encrypted media gallery without subscriptions or platform lock-in. Users retain the right and practical ability to decrypt their files with independent desktop software.

## MVP user stories

1. As a user, I create a password-protected Cryptomator-compatible vault on iPhone and can import unlimited local media subject only to free disk space.
2. I can view thumbnails, photos, albums and videos without any mandatory account or network connection.
3. I can copy the **encrypted vault directory** to a computer and open it using an unmodified Cryptomator desktop app, entering my vault password.
4. If I lose my iPhone, I can restore the copied vault without the original phone or iOS Keychain.
5. I can follow a Private Photo Vault migration wizard to export/import large batches, preserve available source metadata and albums, resume interrupted imports and review a detailed verification report.
6. I can maintain distinct real and decoy vaults, protected by different passwords. No claim that a decoy provides guaranteed forensic deniability.
7. I can optionally back up encrypted vault files. The backup mechanism, iCloud coverage and account recovery must be validated rather than presumed.

## Nonfunctional requirements

* Local first; no telemetry or mandatory servers; no unencrypted whole-library staging.
* Stream large files. Avoid plaintext thumbnails, cached previews and logs persisting beyond controlled lifecycles.
* Password-based encryption with compatibility-preserving KDF and secure key management; Face ID optional convenience only.
* File integrity checking, disk-full handling and crash-safe writes.
* Published source for entire distributed app and documented recovery operations.
* One-time price preference \~$5–$10; no subscription needed for core offline function.

## Exclusions for initial MVP

Two-way multi-device synchronization; automatic plaintext clean-up in Private Photo Vault; forensic deniability guarantees; server-hosted photo backup; photo AI search.

## Open technical questions

* Upstream SealedPocket reuse feasibility and decoy architecture.
* Cryptomator Swift licensing and iOS File Provider integration; whether a separate gallery index is necessary and how to secure it.
* Album representation compatible with third-party desktop access.
* Private Photo Vault Wi-Fi/Photos export fidelity, limitations and whether direct share-sheet handoff exists.
* Large-library iCloud backup quotas and practical restore semantics.
* TestFlight/App Store terms and GPL/AGPL compatibility.

## Validation gates

**Gate A: feasibility.** Repository build, source audit, licensing pathway, Private Photo Vault export test.
**Gate B: compatibility.** iOS-encrypted media opened by unmodified desktop Cryptomator.
**Gate C: recoverability.** Cold restore to new phone without original Keychain; integrity and metadata verified.
**Gate D: migration.** Sample 1,000+ source assets with restart/resume, duplicate handling, album/metadata verification.
**Gate E: security.** Threat model, decoy separation tests, storage and cache leakage review.
**Gate F: distribution.** Beta/TestFlight, license notices, build instructions, recovery documentation and paid-store eligibility.

## Notes

This is a planning hypothesis, not a completed code audit or assurance of Cryptomator integration. Fail feasibility gates early before committing to a storage rewrite.

## Open-source transparency and self-build promise

* Encourage users to inspect, fork and independently build the full app from tagged public source. Clearly document Mac/Xcode/Apple signing requirements, potential developer fees, dependency pinning, and how personal builds differ from TestFlight/App Store builds.
* Publish beginner-friendly install-from-source instructions, tagged release sources, security architecture, limitations and verifiable test results. Validate build reproducibility before making exact-binary claims.
* Product positioning goal: unusually secure, transparent, affordable and private photo vault; avoid stating 'most secure/private on the App Store' as a fact without substantiating comparative evidence and audit.
* Make trust features visible: local-only by default, portable standard vault, separate password, desktop recovery, no mandatory account or subscription, open code and independent user choice.
* Marketing flow: early free adopters retain access after later one-time paid pricing; lightweight privacy-respecting referral sharing, without contact uploads or incentivized App Store reviews.

## Project issue inventory

Descriptions below are discovery summaries and may be truncated by Linear; consult each linked issue for full acceptance criteria.

### [D2S-121: Develop transparent privacy-first messaging and evidence-backed trust center](https://linear.app/d2sci/issue/D2S-121/develop-transparent-privacy-first-messaging-and-evidence-backed-trust)

Position the app as exceptionally secure, transparent, affordable and private—without unsubstantiated superlatives. Publish plain-language security model: open-source entire app, encryption format + independent desktop recovery, local-only operation, no required account, separate password, what metadata is exposed, known limitations and threat model, audits and dependency inventory. Publish transparent monetization rationale (initial free launch… (truncated, use `get_issue` for full description)

### [D2S-120: Publish reproducible self-build instructions and build verification](https://linear.app/d2sci/issue/D2S-120/publish-reproducible-self-build-instructions-and-build-verification)

Make compiling the exact App Store release from public source a first-class product feature. Publish beginner-friendly README and website guide for macOS + Xcode: clone/tag release, pin dependencies, set unique bundle ID and signing team, replace branding if necessary, compile, install on iPhone, and optionally run personal TestFlight (paid Apple Developer account required). Include expected tool versions, build scripts, privacy/config differenc… (truncated, use `get_issue` for full description)

### [D2S-119: Plan free launch, paid conversion and referral incentives](https://linear.app/d2sci/issue/D2S-119/plan-free-launch-paid-conversion-and-referral-incentives)

Decision: launch Portable Vault free on App Store to build initial adoption, then change to one-time paid upfront (\~$5–$10) after validation. Early users retain access after pricing change. Design a privacy-first invite/referral program during free period using shareable links and time-limited 'free before launch price' messaging. Investigate whether precise referral attribution is necessary, given no-account/no-tracking promise; default to sha… (truncated, use `get_issue` for full description)

### [D2S-118: Publish open-source fork and prepare one-time paid release](https://linear.app/d2sci/issue/D2S-118/publish-open-source-fork-and-prepare-one-time-paid-release)

Rebrand; upstream attribution/license notices; reproducible build docs; desktop recovery instructions; third-party license compliance; privacy policy; one-time paid entitlement design without limiting offline owned vault access; App Store/TestFlight review.

Acceptance: public source and recovery docs matching shipped binary, compliance checklist, release candidate.

### [D2S-117: Performance, reliability and TestFlight beta](https://linear.app/d2sci/issue/D2S-117/performance-reliability-and-testflight-beta)

Measure imports, random-access media and scrolling for large libraries; simulate low storage, app interruption and power loss; create signed personal TestFlight builds and feedback checklist.

Acceptance: corruption-free interruptions, repeatable tests, beta readiness.

### [D2S-116: Security review: encryption, metadata and plaintext leakage](https://linear.app/d2sci/issue/D2S-116/security-review-encryption-metadata-and-plaintext-leakage)

Assess KDF, AEAD nonce requirements, third-party dependencies, thumbnails, QuickLook, image/video decoder caches, EXIF indexes, temporary copies, crash logs and secure deletion limits on iOS. Add regression tests and arrange independent review if feasible.

Acceptance: documented threat model, severity-rated findings and fixed release blockers.

### [D2S-115: Design and implement decoy vault / guest password isolation](https://linear.app/d2sci/issue/D2S-115/design-and-implement-decoy-vault-guest-password-isolation)

Determine whether upstream Guest Mode actually creates separate encrypted data. Implement independent decoy/main Cryptomator vaults and password routing. Audit metadata, logs, manifests and backups for cross-vault leaks. Avoid promise of forensic plausible deniability.

Acceptance: separate ciphertext/key domains; automated access/isolation tests.

### [D2S-114: Implement encrypted vault copy, export, backup and restore](https://linear.app/d2sci/issue/D2S-114/implement-encrypted-vault-copy-export-backup-and-restore)

Move/share encrypted **vault as a whole** through Files/external storage; explore iCloud Drive and iCloud Backup behavior with Advanced Data Protection without claiming automatic inclusion. Avoid plaintext snapshots. Test safe atomic copy and restore.

Acceptance: documented backup/restore procedure tested on another device.

### [D2S-113: Implement resumable Private Photo Vault migration wizard](https://linear.app/d2sci/issue/D2S-113/implement-resumable-private-photo-vault-migration-wizard)

Guide users through supported exports and import; optional computer-assisted transfer. Stream media into encrypted vault, preserve supported albums/metadata, deduplicate, recover interrupted jobs, and provide mismatch report. Never automatically delete originals or plaintext exports.

Acceptance: batch migration test >1k files with verifiable counts/hashes; clear source limitations and safe retry.

### [D2S-112: Build Photos-like encrypted gallery and unlimited local import](https://linear.app/d2sci/issue/D2S-112/build-photos-like-encrypted-gallery-and-unlimited-local-import)

Grid, albums, favorites, search/basic metadata, large video playback, selection and bulk Photos/Files import. Index and cache privacy-preservingly. No arbitrary item limits; device storage is the only bound.

Acceptance: smooth browsing of thousands of items, original-quality retention, no cloud requirement.

### [D2S-111: Implement independent vault password and secure key lifecycle](https://linear.app/d2sci/issue/D2S-111/implement-independent-vault-password-and-secure-key-lifecycle)

Require a vault-specific password, KDF analysis (Argon2id vs supported Cryptomator parameters), optional Face ID unlock, lock timeout, secure memory and key handling. Ensure no downgrade of Cryptomator compatibility.

Acceptance: threat model and wrong-password, lockout and key recovery tests.

### [D2S-110: Test cold recovery without original device or Keychain](https://linear.app/d2sci/issue/D2S-110/test-cold-recovery-without-original-device-or-keychain)

Copy encrypted file set to a fresh device; unlock using only required password/recovery materials; verify metadata, files and corruption detection. Document backups and recovery keys.

Acceptance: no dependency on original iPhone Keychain; automated restore fixture.

### [D2S-109: Build cross-platform portable vault proof of concept](https://linear.app/d2sci/issue/D2S-109/build-cross-platform-portable-vault-proof-of-concept)

Import sample photos/videos encrypted on iOS; copy **encrypted** file set intact to macOS/Windows; unlock and read using unmodified Cryptomator desktop. Test changes both ways if safely supported.

Acceptance: repeatable desktop interoperability test and documented encrypted directory layout.

### [D2S-108: Investigate Private Photo Vault export fidelity and migration paths](https://linear.app/d2sci/issue/D2S-108/investigate-private-photo-vault-export-fidelity-and-migration-paths)

Test current source app export via Photos, Files and Wi-Fi Transfer with disposable samples. Measure batch limits; album structure, original files, EXIF, timestamps, names, Live Photos and video preservation. Document source app limitations.

Acceptance: reproducible export matrix and recommended phone-only and desktop-assisted paths.

### [D2S-107: Spike Cryptomator vault on iOS with Swift libraries](https://linear.app/d2sci/issue/D2S-107/spike-cryptomator-vault-on-ios-with-swift-libraries)

Test local vault creation, password-based unlock, streaming reads/writes, file/filename encryption, large videos, performance and OS Files-provider constraints. Validate chosen libraries/versions; measure complexity.

Acceptance: demonstrable iOS vault and decision record with fallback if incompatible.

### [D2S-106: Confirm fork, Cryptomator library and App Store licensing feasibility](https://linear.app/d2sci/issue/D2S-106/confirm-fork-cryptomator-library-and-app-store-licensing-feasibility)

Verify actual LICENSE files, copyright owners and GPLv3/AGPLv3 obligations; document options for Cryptomator Swift integration, App Store/TestFlight distribution, original branding and paid distribution. Obtain legal review before shipping.

Acceptance: documented compliant licensing/distribution route and blockers.

### [D2S-105: Audit SealedPocket source, build system, Guest Mode and storage paths](https://linear.app/d2sci/issue/D2S-105/audit-sealedpocket-source-build-system-guest-mode-and-storage-paths)

Clone and build upstream. Map gallery, import, authentication, purchase limits, storage, keys, temporary files and dependencies. Verify full source availability and current Guest Mode behavior.

Acceptance: architecture diagram; build on device; prioritized reuse/rewrite inventory; findings recorded.
