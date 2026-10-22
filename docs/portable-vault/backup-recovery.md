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

Use a trusted computer with enough private disk space and Python 3.9 or newer. Obtain WagLock's matching source, keeping `tools/backup_recovery.py` and its sibling `tools/age_bootstrap.py` together. No WagLock app, Apple account, phone or Keychain is needed.

### Mac example: Desktop backup → Downloads

If the WagLock repository is in `~/repos/WagLock` and you saved `WagLock-Backup.tar.age` on your Desktop, open **Terminal**, paste this whole command and press Return. It works from any current folder:

```sh
python3 "$HOME/repos/WagLock/tools/backup_recovery.py" \
  "$HOME/Desktop/WagLock-Backup.tar.age" \
  "$HOME/Downloads/WagLock-Recovered"
```

- **First path:** the recovery helper in your downloaded/cloned WagLock repository. Change it if you keep the repository elsewhere.
- **Second path:** your encrypted backup. Change it if you saved the backup somewhere else or renamed it.
- **Third path:** the new folder for decrypted files. **Do not create it first.** If `WagLock-Recovered` already exists, choose another name, such as `WagLock-Recovered-2`; existing files will not be overwritten. Keep decrypted output in a private location.

`$HOME` means your Mac user folder. Keep the quotes, especially for paths containing spaces. The backslash at each line end continues the same command onto the next line.

If age is missing, the helper downloads and verifies it automatically. At **Enter passphrase:**, type the **backup password you chose during export**, then press Return. No characters appear while you type; that is normal. Separately protected albums prompt for their own passwords. A successful run creates `~/Downloads/WagLock-Recovered/`; the outer library is inside its `root/` folder. See the output layout below for media and notes.

### Recovery-key example

If you chose **Age recovery key** during export, supply the matching private identity file instead of an outer backup password. For example, if you keep that file on an external drive named `Recovery`:

```sh
python3 "$HOME/repos/WagLock/tools/backup_recovery.py" \
  "$HOME/Desktop/WagLock-Backup.tar.age" \
  "$HOME/Downloads/WagLock-Recovered" \
  --identity "/Volumes/Recovery/waglock-identity.txt"
```

Replace the identity path with your actual file. Keep that private identity separately from your backup; the public `age1…` recipient entered in WagLock cannot decrypt it.

### Automatic age setup and optional controls

**age sets itself up automatically.** If the official [age tool](https://github.com/FiloSottile/age#installation) is already available in your terminal, the helper uses it. Otherwise, on supported macOS/Linux/Windows Intel/ARM64 computers, it downloads the official **age 1.3.2** release over HTTPS, checks a SHA-256 checksum pinned in WagLock's source, and uses a private local copy. No Homebrew, administrator password or system-wide install is required. The first download is about 20 MB and needs internet access; your backup, passwords and keys are never uploaded. Later runs can reuse the verified cached release offline.

On macOS the release cache is `~/Library/Caches/WagLock/age/1.3.2/`. Linux uses `$XDG_CACHE_HOME/WagLock/age/1.3.2/` or `~/.cache/WagLock/age/1.3.2/`; Windows uses `%LOCALAPPDATA%/WagLock/age/1.3.2/`. Each run rechecks the archive and extracts only the expected executable into its own temporary directory, removed when finished. A download/checksum/version failure stops recovery before decrypting. This verifies pinned release bytes; it is not independent Sigsum/signature verification.

Use `--no-install-age` to prevent downloads and require an installed or verified cached copy. For another age installation, use `--age /path/to/age`; an invalid explicit path produces an error rather than downloading a replacement. Unsupported platforms and offline first runs show manual installation instructions.

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
