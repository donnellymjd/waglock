> Current October26 checkpoint: accepted63; candidate64 adds dated backup names without a cryptographic format change. [Pre-launch ledger](prelaunch-status.md) supersedes historical build45/50 account status below. Data Not Collected remains the engineering recommendation, not an assertion that the account-holder has filed it. After explicit owner approval, provisioning refresh and local64 distribution export/signature/AutoFill checks pass. App Store server validation and account declarations remain.

# Privacy and encryption submission worksheet

D2S-106/118/121. Prepared October 22, 2026; final answers are **not filed or approved**.

## App privacy

The inspected source has no app analytics/advertising/custom crash-reporting SDK or vault-content backend. Local media, notes and credentials are used on device. User-selected sharing, Files/cloud providers, external links and Apple system backups/diagnostics are separate data paths described in the policy. No dynamic zero-network proof is claimed.

Prepare privacy-label answers from the final archive, not from a blanket “no data” slogan. Review external destinations/support handling, Apple diagnostics available to the developer, all SDKs and future changes. Confirm the privacy manifest's file-timestamp, disk-space and preferences reasons match actual calls. The current manifest's empty collection list is not itself a completed privacy review.

Apple's [privacy-label documentation](https://developer.apple.com/app-store/app-privacy-details/) defines collection and requires developers to account for integrated partners. Its [review guidelines](https://developer.apple.com/app-store/review/guidelines/) require an accessible privacy policy; use the current WagLock policy and in-app link, not the historical upstream policy. These references do not establish this app's final questionnaire answers.

## Encryption inventory for classification

| Use | Implementation / facts to provide |
| --- | --- |
| Native originals | Existing AES-GCM buffered/stream formats, legacy readers and authenticated ZNSC v2 framing; no native standard-format compatibility claim. |
| Credentials and album keys | Password-derived verification/wrapping, OS Keychain, optional biometric access. Review exact KDF/credential paths in the release. |
| age backup | Standard age envelope implemented over Apple CryptoKit; X25519 recipient or password/scrypt choice, nested password domains. Original BSD-2-Clause scrypt C core plus CommonCrypto adapter. No third-party age CLI is embedded in iOS. |
| Release metadata | The separate first-release configuration mounts the CryptoKit/SQLite encrypted index with password-wrapped random root keys, domain-bound record encryption and an authenticated inventory; the legacy development identity remains unchanged. |

The account holder/reviewer must determine the applicable export classification and territory-specific documentation from the actual implementation and Apple's questionnaire. Do not infer exemption solely because Apple APIs are used; scrypt and custom framing/format code must be described accurately. Do not set `ITSAppUsesNonExemptEncryption` to false as a way to bypass review. No CCATS, exemption, French filing or compliance-code outcome is asserted here.

Apple's [export-compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance) describes the determination and documentation flow. Record the supported conclusion, territories, reviewer and any required approvals/code before setting the final plist answers or uploading. No account agreement or export declaration has been accepted during this preparation.


## Candidate source/API review — October 23, 2026

The actual first-release simulator bundle is com.d2sci.waglock, marketing1.0/build45. Its explicit Info.plist template resolves WagLockEncryptedLibrary=YES. An arbitrary INFOPLIST_KEY custom setting alone was ignored by Xcode, so the switch is now in the actual template and verified in the built artifact. Normal development builds resolve it empty/false and keep their separate legacy library.

Required-reason inventory, checked against [Apple's category/reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype):

| Category | Reason | Inspected purpose |
| --- | --- | --- |
| File timestamps/metadata | C617.1 | Own-container metadata, source revision checks and protected index path validation. |
| File timestamps/metadata | 3B52.1 | Metadata/size of files selected through the system picker. |
| Disk space | E174.1 | Check capacity before imports, encryption and complete backup creation; stop with a visible failure when insufficient. |
| Disk space | 85F4.1 | Show device storage information in Settings. |
| UserDefaults | CA92.1 | App-only appearance, layout, keyboard and auto-lock preferences. |

No production systemUptime/mach_absolute_time/activeInputModes call was found in the app source scan. The manifest declares no tracking, no tracking domains and no app-collected data types. Source inspection found no URLSession/URLRequest backend, analytics/ads SDK or app-operated vault service. Optional external support links, Apple diagnostics and user-selected Files providers remain separate policy disclosures. The engineering privacy-label recommendation is Data Not Collected for this implementation; the account holder must confirm the actual App Store diagnostics/support arrangements before filing. This is not a claim that the operating system or another app never communicates.

Encryption questionnaire inventory is prepared above. The owner selected worldwide availability where permitted; any required territory/export documentation still needs the account-holder determination; no exemption/non-exempt flag, compliance code, account agreement or legal determination has been invented or filed.


## Final build50 preparation

Owner confirms the final disposable-media, notes/album, password-change/relaunch, Face ID/background and Mac backup recovery checklist passed on October23. The separate intermittent note-classification report remains documented, with no new root cause claimed. [Encryption questionnaire brief](app-store/encryption-brief.md) provides the exact implementation facts and current Apple workflow. No declaration or agreement has been filed. A local App Store export on this Mac failed because no App Store provisioning profile exists for com.d2sci.waglock; only an Apple Development signing identity is locally available. This is an account/provisioning action, not a code-signature failure in the accepted development build.
