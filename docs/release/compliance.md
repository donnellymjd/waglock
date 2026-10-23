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
| Metadata candidate | Currently unused CryptoKit/SQLite store; identify whether present/active in the final release rather than assuming fixture tests equal production adoption. |

The account holder/reviewer must determine the applicable export classification and territory-specific documentation from the actual implementation and Apple's questionnaire. Do not infer exemption solely because Apple APIs are used; scrypt and custom framing/format code must be described accurately. Do not set `ITSAppUsesNonExemptEncryption` to false as a way to bypass review. No CCATS, exemption, French filing or compliance-code outcome is asserted here.

Apple's [export-compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance) describes the determination and documentation flow. Record the supported conclusion, territories, reviewer and any required approvals/code before setting the final plist answers or uploading. No account agreement or export declaration has been accepted during this preparation.
