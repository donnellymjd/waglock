# WagLock 1.0 submission files

Build50 passed the owner's full disposable-sample phone and independent Mac backup-recovery checklist on October23. Engineering evidence is in [build50](../evidence/build-50/README.md). The separately reported intermittent note classification remains tracked; no new root cause or independent audit certification is claimed.

Copy [description](description.txt), [review notes](review-notes.txt), [release notes](release-notes.txt) and remaining [metadata](metadata.json) into the actual App Store Connect record. [Current screenshots](../screenshots/build50/README.md) are unedited captures of the actual release. Initial price:Free. Release control:Manual.

The local archive is `/private/tmp/WagLock-1.0-build50-candidate.xcarchive`. It is development-signed and must be exported/re-signed for App Store Connect; it is not an upload-ready IPA. The local export attempt fails because no App Store provisioning profile exists for com.d2sci.waglock. [Export options](../../../config/AppStoreExport.plist) preserve version/build, select local export, and do not request provisioning updates or upload by themselves.

## Final account-side steps

1. Sign into the paid Apple Developer team in Xcode and establish App Store distribution signing/provisioning for com.d2sci.waglock. Keep WagLock Dev separate. Re-export/validate the archive in Xcode Organizer; account-managed signing may require approved portal changes.
2. Create/select WagLock in App Store Connect. Enter the already supplied private review contact only in Apple's private fields. Confirm the public publisher/copyright field and actual privacy/age/content answers. No server/demo login is required.
3. Complete encryption and territory determination using [the factual brief](encryption-brief.md), including France documentation if required for the worldwide choice. Enter only a supported exemption or an Apple-issued compliance code. Review the source/platform terms using the [licensing packet](../licensing-review.md); GPL monetization alone does not require a lawyer letter or separate upstream permission.
4. Once signing and declarations are complete, upload/select the processed build, attach assets, select manual release and submit for review. No upload/submission has occurred. Never send Apple passwords or API private keys in chat.

Exact application source:candidate-1.0-build50, commit673761c. `/private/tmp/WagLock-1.0-build50-source.tar.gz` contains matching tagged source, notices, build guidance and recovery tools. Preserve this association when distributing binaries. Artifact hashes identify local prepared files; byte-identical reproducible builds are not claimed.
