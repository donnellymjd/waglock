# WagLock privacy policy

Updated October 22, 2026. This describes the current WagLock development build. The first App Store release is still being prepared; this policy will be checked against the exact release before submission.

WagLock is an independent open-source fork of SealedPocket / ZeroNet Space. It is not the official upstream app. [Source and notices](https://github.com/donnellymjd/waglock).

## Your content and credentials

WagLock uses photos, videos, files, audio recordings, notes and the information you enter to provide its local library. No WagLock account is required. The app does not operate a backend that receives your vault content, passwords or keys, and the inspected app source does not include advertising, analytics or a custom crash-reporting SDK.

Imported media and file contents are encrypted on your device. Password verification and key material use local credentials and Apple's Keychain; optional Face ID uses Apple's authentication interfaces. WagLock does not receive your Face ID biometric template.

**Current development limitation:** names, thumbnails, note text and other library metadata are still stored in the legacy local database without vault-level encryption. Some legacy draft conflicts may also remain in preferences. Device protection is not the same as encrypting these fields with your vault password. The replacement storage is not active yet. Do not use this development build as the only copy of sensitive or irreplaceable content.

## When data can leave your device

- **Ordinary sharing/export:** destinations you choose receive decrypted copies. Recipient apps and people control those copies afterward.
- **Encrypted backups:** you can explicitly create a password- or recipient-key-encrypted backup and save it through the iOS Files interface, including a cloud provider you have configured. Separately protected albums retain their required export passwords. Keep passwords/recovery keys separately; WagLock cannot reset them for you. There is no automatic two-way vault sync.
- **System services:** Photos, Files and installed providers may download selected content or upload saved copies. iOS device backups and diagnostics depend on Apple's settings and services. App-wide backup inclusion and cold restore are not yet fully validated.
- **External links:** opening source, support or recovery links contacts the external website through iOS. That site applies its own privacy practices.

These actions do not send your library to a WagLock-operated service. Apple and the providers or recipients you choose may process information under their own terms. A provider accepting a file does not prove a remote upload has finished.

## Permissions

Photos access is used to choose media for import. The system Files picker grants access to selected files or destinations. Microphone access is requested for audio recording. Face ID is optional for the app or albums you configure. You can change permissions in iOS Settings. Denying an optional permission prevents its related function; it does not give someone a password bypass.

Importing does not automatically delete the original in Photos or Files. Content may retain embedded information such as capture dates or location metadata; this is not an automatic metadata-removal tool.

## Retention and deletion

Your local library remains until you delete content or remove the app. The current build has no Trash/undo retention feature. Deletion is not a guarantee of forensic erasure. Temporary decrypted previews/shares are managed by the app and iOS; crash and cache-cleanup limitations remain under review.

Copies saved to Photos, Files, cloud providers, backups or recipients are independent of the vault. Delete those copies using their owning app/provider. Removing WagLock does not retract shared copies, and Keychain entries can outlive an app installation. Reinstallation is not a recovery method. Device-bound Face ID-only albums have additional loss risks; review their warnings before using them.

Because we do not hold a server-side library or account, we cannot retrieve or remotely delete your vault, reset its passwords, or remove copies held by recipients/providers.

## Support and updates

For questions, use [WagLock support](https://github.com/donnellymjd/waglock/blob/main/docs/release/support.md) or [GitHub Issues](https://github.com/donnellymjd/waglock/issues). GitHub issues are public: do not post passwords, recovery keys, private media, backups or identifying logs. Information you voluntarily post there is processed by GitHub and visible to others.

Changes will be recorded here with an updated date. This policy does not claim an independent security audit or certification. The preserved [upstream policy](docs/portable-vault/provenance/upstream-privacy-policy-2025-11-18.md) is historical attribution, not this fork's current policy.
