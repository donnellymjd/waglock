# Encrypted backup and independent recovery

Build 39 development feature; D2S-114/110/141. Keep independent originals and test recovery before relying on a backup. The original phone and its Keychain are not required to decrypt a successfully created export. This is an additional export format; the installed library has not been converted.

## Create and save a backup on iPhone

1. Finish editing notes/importing/recording, unlock the owner library, then open **Settings → Encrypted backup**. Guest Mode cannot export the owner library.
2. Choose **Password** or **Age recovery key**. Password mode needs a new matching password of at least 12 characters; prefer several random words. It does not change the app password. Recovery-key mode takes an existing age X25519 public recipient beginning `age1`; keep its matching private identity separately, outside the backup. WagLock does not generate or store that private identity.
3. Enter the current password of every separately protected album. Each remains independently encrypted, including nested albums. Protected parent and child passwords must differ. Short existing album PINs remain susceptible to guessing.
4. A Face ID-only album needs explicit consent, successful Face ID authorization and a new, confirmed export password of at least 12 characters. This creates a password-readable copy of that album. It does not change the phone's album policy or add a native password fallback. Cancel if you do not want that copy.
5. Keep WagLock open while preparing the backup. Locking, backgrounding, cancellation or a changed library invalidates preparation; start again. All supported persisted content must be available; inaccessible albums or missing files stop the complete export rather than being omitted.
6. When ready, select **Save to Files or cloud storage**. The iOS destination picker offers **On My iPhone**, **iCloud Drive**, or installed providers enabled in Files. Save `WagLock-Backup.tar.age` to your chosen location. No provider account or SDK is connected to WagLock. This is optional, manual backup, with no automatic upload or two-way sync.
7. Verify that the provider finished uploading and that the file is available on another device. A successful Files callback confirms the provider accepted the copy, not that a remote upload completed. Only finished ciphertext is handed to the picker; the system copy can continue after WagLock locks. Copies already handed off cannot be retracted.

Store the root backup password/private identity **and every separate album export password** safely, apart from the ciphertext. Losing one prevents recovery of that domain. The root credential is deliberately insufficient to open protected children. Backups are immutable copies; later phone changes do not update them.

## Recover with open-source tools

Use a trusted computer with enough private disk space, Python 3.9 or newer and the official [age tool](https://github.com/FiloSottile/age#installation). Official **age 1.3.2** was used in the recorded macOS recovery checks. Obtain WagLock's matching source and `tools/backup_recovery.py` from this repository. No WagLock app, Apple account, phone or Keychain is needed.

Run from the checked-out repository, using a **new destination directory** under a trusted private parent:

```sh
python3 tools/backup_recovery.py /path/WagLock-Backup.tar.age /private/path/recovered --age /path/to/age
```

For recovery-key mode, also supply your separately stored identity file:

```sh
python3 tools/backup_recovery.py /path/WagLock-Backup.tar.age /private/path/recovered --age /path/to/age --identity /offline/recovery-key.txt
```

Enter passwords into age's terminal prompts. Do not put passwords in commands, scripts, environment variables or issue reports. The helper announces each protected album's opaque domain UUID before requesting its password. Encrypted private identity files may also cause an age prompt. Child domains always require their separate passwords, even when the outer archive uses a recovery key.

The helper calls the unmodified age executable, then checks authenticated archive completeness, byte counts, SHA-256 hashes, record references and nested album hierarchy. It rejects missing/extra/duplicate files, unsafe paths/links and incomplete or tampered input. A new private destination is published only after every required domain verifies. Existing destinations are not replaced. On failure, it removes only its own staging directory; interruption/power loss can leave sensitive `.partial` output requiring manual cleanup. Local deletion does not guarantee forensic erasure.

Recovered files have stable UUID names under `media/`; `metadata.json` records original names/extensions, dates, types, album membership and supported media properties. Add the recorded extension to a **copy** to open it in ordinary applications. Notes, tags and saved drafts are JSON text in that file. The outer domain is under `root/`; nested output lives under its parent’s `recovered-<domain UUID>/`; each domain has its own metadata and manifest. Original names and Unicode spelling are retained inside encrypted metadata, rather than used as filesystem paths. This is independent extraction, **not an in-app restore/import wizard** or automatic reconstruction of human-readable directory names.

`--outer-only` explicitly recovers only the outer domain and retains unopened child ciphertext. Its report states that full nested recovery is false. It is not a complete-library recovery result. For manual inspection, standard `age --decrypt` followed by a tar tool can open a domain, but that bypasses WagLock's additional manifest/hierarchy checks; use the helper for verified recovery.

## Included content and limits

- Includes current supported persisted media/file/audio records and payloads, thumbnails, album hierarchy, separately protected album catalogs, notes, tags and both saved draft stores. Uncommitted editor keystrokes, recordings and unfinished imports are not snapshots.
- Device settings, Face ID registrations, native wrapped keys and Keychain credentials are intentionally excluded. These are declared in encrypted metadata. Trash is declared not implemented; future schema additions must be explicitly supported before export.
- Large authenticated native streams are processed in chunks. An older **buffered** native ciphertext above **64 MiB** blocks complete export until a streaming adapter is implemented; it is never silently skipped. The test evidence includes a 64 MiB + 3-byte streamed file, not a whole-library hardware-scale benchmark.
- Aggregate encoded domain metadata is limited to 64 MiB. Export passwords are limited to 16 KiB of UTF-8. The helper defaults to 1 TiB total extracted bytes, 200,000 entries and 64 nested levels; its documented `--max-bytes` and `--max-entries` options can raise the first two for trusted backups with sufficient resources. Metadata/depth limits remain fixed.
- Independent recovery has been exercised on **macOS**. Linux/Windows publication paths are implemented but not yet validated in this work. Actual iPhone/iCloud/third-party-provider acceptance is separate from simulator checks.
- This does not encrypt the native SwiftData metadata or remedy inherited stream-v1 weaknesses. It cannot restore source information never recorded by the app. It is not an independent security audit, recovery guarantee for every library, or approval for public/TestFlight distribution.

See [format and cryptographic decisions](age-backup-design.md), [validation evidence](backup-validation-results.json) and [the open architecture/security audit](audits/D2S-105.md).
