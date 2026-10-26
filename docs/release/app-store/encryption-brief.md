# WagLock 1.0 encryption review brief

Updated October26,2026 for com.d2sci.waglock, candidate64, intended source candidate-1.0-build64. These are implementation facts for the account holder's Apple questionnaire; no exemption, export classification, French declaration, CCATS or compliance code has been asserted or filed.

## Purpose and delivery

WagLock is an offline encrypted personal photo/video/file/note library. No hosted vault or account service is present. The owner selected worldwide availability where permitted. User-selected Files/cloud providers receive explicitly exported encrypted backups; ordinary sharing exports decrypted copies. Encryption is a central product function.

## Implementation inventory

| Operation | Actual implementation |
| --- | --- |
| Native media and new release metadata | AES-GCM using Apple CryptoKit, SHA-256/HMAC/HKDF where used by authenticated records and inventories; PBKDF2-HMAC-SHA256 via Apple CommonCrypto for native derivation. Native envelopes and chunk/record authentication are app format code. |
| Password and key storage | Apple Security/Keychain and optional LocalAuthentication for biometrics. Modern primary/secondary release credentials wrap independent random data secrets using versioned PBKDF2-HMAC-SHA256 password wrapping (600,000 iterations for new records). Older primary/album wrappers are strengthened only after successful authentication, preserving data secrets; fast legacy SHA256 verifier slots are refused by the public release. No biometrics leave Apple's APIs. |
| Standard age-format backup | Apple CryptoKit X25519, HKDF-SHA256, HMAC-SHA256 and ChaCha20-Poly1305. Independently implemented public age v1 envelope/stream; not a proprietary cipher. Each protected domain has independent wrapping. |
| Password backup derivation outside system implementation | Original BSD-2-Clause Tarsnap scrypt C core, N=262144, r=8, p=1; Apple CommonCrypto adapter. This is bundled source and must be disclosed rather than describing the entire implementation as OS-only. |
| Recovery tools | Official age is obtained independently on the computer; not embedded in iOS. The GPL helper verifies archives and creates a readable Library directory. |

See [format/dependency details](../../portable-vault/age-backup-design.md), [source provenance](../../../WagLock/Support/Scrypt/PROVENANCE.md) and [compliance inventory](../compliance.md). Custom container/framing code does not by itself mean a proprietary encryption algorithm; classification must distinguish primitives from file formats.

## Apple process rechecked October26

Apple's [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/) distinguishes OS-only encryption, standard algorithms outside the OS, and proprietary algorithms. It identifies a French declaration for the standard/non-OS category if distributing in France. Do not silently remove France from the owner's worldwide choice; record the supported determination and any required documentation first.

In App Store Connect, select the app, then App Information > App Encryption Documentation > + and answer the current questions using this inventory. Apple's [workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/) requires any needed documents before App Review/TestFlight review. Supply the final description and intended availability so Apple can evaluate the documentation. Only enter a compliance code actually issued/approved by Apple. If documentation is not required, record the applicable basis before changing Info.plist. The candidate intentionally does not set ITSAppUsesNonExemptEncryption or an invented exemption.

## Private/account fields

The app review contact was already supplied by the owner; keep it in Apple's private fields. The public publisher/copyright field and actual account agreements remain account-holder entries. No account password, API private key or device vault password belongs in this repository or a public issue.

Public build57 rejects legacy native v1 stream reads and native .encrypted imports. Explicit legacy Dev/recovery readers remain in source; no native format conversion or migration occurs. This does not refer to age v1, the separate supported standard backup format.

Build57 authenticates native ciphertext SHA256 digests in the encrypted metadata index and uses device-only Keychain commit stamps plus encrypted recovery deltas to detect post-enrollment filesystem rollback. No new cryptographic primitive or change to the standard age backup format is introduced. These facts do not determine an export classification or exemption.

Build64 only adds date/time-stamped editable backup names and selects the already accepted webcredentials entitlement in the standard release configuration. Encryption primitives, native/age formats, independent album factors and KDF parameters are unchanged. App Store Connect questionnaire answers remain unfiled by this task. The standard/non-OS row in Apple's table currently identifies French documentation when France is selected; determine the applicable category from the complete inventory rather than assuming custom framing is a proprietary cipher. The owner requested worldwide where permitted; no territory has been silently removed.
