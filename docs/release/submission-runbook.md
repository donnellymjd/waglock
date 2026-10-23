# Final submission handoff — WagLock 1.0

Engineering candidate: build50, separate bundle `com.d2sci.waglock`. Existing `com.d2sci.vaultito.dev` is preserved. The owner confirms the full [physical acceptance](device-acceptance.md) checklist passed October23, including independent Mac backup recovery. It is **not submitted**. Full evidence and open security limits are in [the readiness ledger](submission-plan.md).

## Account-holder decisions still needed

- Phone checklist and readable independent backup recovery: owner-confirmed passed October23. The intermittent classification report remains tracked.
- Launch preference is worldwide where permitted. Complete the corresponding territory/encryption determination; no exemption flag or compliance code has been assumed.
- Private App Review contact name/email/phone were supplied in conversation. Enter them only in the private Apple submission fields; confirm the public copyright/publisher field separately. Do not put private contact details in this public repository.
- Confirm privacy answers against the prepared [inventory](compliance.md), including actual diagnostics/support arrangements; complete Apple's age/content questions and account agreements.
- Record the distribution-compliance determination for the covered source/platform terms. GPL permits commercial binaries with matching source/recipient rights; a lawyer letter or monetization permission is not a GPL requirement. The project still requests a distribution review; no particular current incompatibility has been established. See [the packet](licensing-review.md).

## When those gates are satisfied

1. Keep the existing development app installed. Register/select the explicit release identifier and create the WagLock App Store Connect record. Do not reuse the development ID or claim a library transfer.
2. Build an archive from the frozen candidate source with `config/AppStore.xcconfig`, marketing1.0/build50 (or a new unique number if an uploaded build requires it). Use the approved account's distribution signing and correct entitlements. Preserve the source counter with `WAGLOCK_SKIP_BUILD_INCREMENT=YES` during verification. The current unsigned archive is packaging evidence, not a distribution archive.
3. Run `python3 tools/verify_release_candidate.py PATH_TO_ARCHIVED_WagLock.app`. It must verify the actual public bundle, encrypted switch, notices/source hashes and manifest. Its `readyForUpload:false` is deliberate: the script cannot attest to account/legal/hardware gates. Use Organizer's distribution validation too.
4. Publish/retain the exact matching GPL source tag/archive, build instructions, modification/dependency notices and recovery tools. No source encryption key or private credentials belong in it. The candidate tag is a source freeze, not a public binary release.
5. Enter the [listing/review walkthrough](store-listing.md), approved contacts/countries/category/age/privacy/export answers and [actual screenshots](screenshots/build50/README.md). All local features are free; no IAP/subscription is offered. Do not advertise deferred features.
6. Upload the distribution build; resolve Apple's validation/processing findings. Select the processed build for version1.0 and attach any required export documentation/compliance code.
7. Select **manual release**, submit for review, and keep it unreleased after approval until the owner chooses to publish. Approval and timing are Apple's decision. Follow-up improvements can continue in a later version.

No upload, agreement acceptance, export declaration, registration or submission was performed by engineering preparation. No automatic iOS restore, native-folder portability, independent audit certification or forensic deniability is promised.


Final local preparation is complete for build50: current archive, matching source tarball, eight refreshed screenshots and [copy-ready submission files](app-store/README.md). Local App Store export is blocked by a missing App Store provisioning profile for com.d2sci.waglock; no upload occurred. See [exact evidence](evidence/build-50/submission-preparation.json). Do not mistake development signing or a generic package-verifier gate list for actual Apple distribution clearance.
