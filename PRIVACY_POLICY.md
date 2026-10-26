# WagLock privacy policy

Updated October 26, 2026. This describes the first-release candidate and distinguishes older development storage. The App Store package is still being validated; no submission or independent security certification is implied.

WagLock is an independent open-source fork of SealedPocket / ZeroNet Space. It is not the official upstream app. [Source and notices](https://github.com/donnellymjd/waglock).

## Your content and credentials

WagLock uses photos, videos, files, audio recordings, notes and the information you enter to provide its local library. No WagLock account is required. The app does not operate a backend that receives your vault content, passwords or keys, and the inspected app source does not include advertising, analytics or a custom crash-reporting SDK.

Imported media and file contents are encrypted on your device. Password verification and key material use local credentials and Apple's Keychain; optional Face ID uses Apple's authentication interfaces. WagLock does not receive your Face ID biometric template.

**First-release storage:** new libraries in the separate WagLock release configuration encrypt names, thumbnails, note text, saved drafts and other content metadata. The unlocked interface uses an in-memory projection. General device preferences, such as appearance, grid layout and auto-lock choices, remain in system preferences. Stored content is decrypted as needed for viewing and sharing.

**Older development builds:** the WagLock Dev library retains its legacy database, where names, thumbnails and notes are not protected by vault-level encryption; conflicting legacy drafts may also remain in preferences. The release configuration does not silently convert, delete or move that development library. Keep independent originals and verified encrypted backups.

Backup reminders are enabled monthly by default and appear only after unlock. Their frequency and dates stay device-only in the selected library’s Keychain namespace. You can change the frequency or turn reminders off in Settings. Reminders do not send notifications to the lock screen, create backups, contact a server or upload data.

## When data can leave your device

- **Ordinary sharing/export:** destinations you choose receive decrypted copies. Recipient apps and people control those copies afterward.
- **Encrypted backups:** you can explicitly create a password- or recipient-key-encrypted backup and save it through the iOS Files interface, including a cloud provider you have configured. You can choose an independent password, an age recovery key, or explicitly reuse and verify the selected vault password. Short PINs offer weaker protection against offline guessing. Changing a vault password does not update earlier exported backups. Separately protected albums retain their required export passwords. Keep passwords/recovery keys separately; WagLock cannot reset them for you. There is no automatic two-way vault sync.
- **System services:** Photos, Files and installed providers may download selected content or upload saved copies. iOS device backups and diagnostics depend on Apple's settings and services. The independent recovery method described here is the explicit encrypted-backup export. Device-only Keychain credentials and Face ID registrations must not be assumed to transfer with an iOS device backup or reinstallation.
- **Password AutoFill:** iOS may fetch a public app-association file through Apple’s services from the dedicated `waglock.d2sci.co` domain. Hosting/Apple may receive ordinary request metadata. The static site has no password form, telemetry or vault API and receives no vault content, credentials or keys. Your selected password manager handles credential storage, suggestions and authentication under its own settings and privacy terms. Enabling AutoFill does not create a WagLock online account. A password manager can suggest multiple saved entries; WagLock does not control provider-owned entry labels or promise to hide them.
- **External links:** opening source, support or recovery links contacts the external website through iOS. That site applies its own privacy practices.

These actions do not send your library to a WagLock-operated service. Apple and the providers or recipients you choose may process information under their own terms. A provider accepting a file does not prove a remote upload has finished.

## Permissions

Photos access is used to choose media for import. The system Files picker grants access to selected files or destinations. Microphone access is requested for audio recording. Face ID is optional for the app or albums you configure. You can change permissions in iOS Settings. Denying an optional permission prevents its related function; it does not give someone a password bypass.

Importing does not automatically delete the original in Photos or Files. WagLock preserves the encoded file representation supplied by Photos or Files, which may retain capture dates or location metadata. Photos edit history and Live Photo motion are not imported; keep the original assets. This is not an automatic metadata-removal tool.

## Retention and deletion

Your local library remains until you delete content, explicitly erase WagLock, or remove the app. The current build has no Trash/undo retention feature. Deletion is not a guarantee of forensic erasure. Temporary decrypted previews/shares are managed by the app and iOS; crash and cache-cleanup limitations remain under review.

The locked-screen “Can’t unlock?” help offers saved-access guidance and desktop backup recovery instructions. “Erase WagLock and start over” requires acknowledgement and typing ERASE. It deletes all local vault content and saved app unlock/Face ID credentials; it does not decrypt or recover forgotten content. Once confirmed, interrupted erasure resumes on reopening. Exported backups, Photos originals, password-manager entries and other apps are outside this deletion. Native vault recovery keys and in-app backup restore are not available.

Copies saved to Photos, Files, cloud providers, backups or recipients are independent of the vault. Delete those copies using their owning app/provider. Removing WagLock does not retract shared copies, and Keychain entries can outlive an app installation. Reinstallation is not a recovery method. Device-bound Face ID-only albums have additional loss risks; review their warnings before using them.

Because we do not hold a server-side library or account, we cannot retrieve or remotely delete your vault, reset its passwords, or remove copies held by recipients/providers.

## Support and updates

For questions, use [WagLock support](https://github.com/donnellymjd/waglock/blob/main/docs/release/support.md) or [GitHub Issues](https://github.com/donnellymjd/waglock/issues). GitHub issues are public: do not post passwords, recovery keys, private media, backups or identifying logs. Information you voluntarily post there is processed by GitHub and visible to others.

Changes will be recorded here with an updated date. This policy does not claim an independent security audit or certification. The preserved [upstream policy](docs/portable-vault/provenance/upstream-privacy-policy-2025-11-18.md) is historical attribution, not this fork's current policy.
