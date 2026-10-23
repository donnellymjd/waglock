# Owner-supplied security review — October23

This is the supplied report, preserved as review input. Its read-only statements describe that reviewer’s activity, not instructions for this implementation task. Findings/severity are claims to validate against the actual release and tests. It is not independent security certification. The owner authorizes the smallest safe 1.0 mitigations, including disabling calculator login.

I'll review the WagLock repo on your computer read-only and report security risks.

Now the core crypto.

I found two high-severity issues in WagLock and several medium/low ones. Both high-severity issues come from the optional Calculator login, which is still turned on in the 1.0 release build. I made no changes; I read the main encryption, sign-in, keychain, storage, export/backup and recovery-tool code.

## High

**1. Calculator login keeps a recoverable copy of the vault password.** When Calculator login is on, the real vault password is saved in the keychain. It is "encrypted" with a key built from `"ZNS_DISGUISE_" + identifierForVendor` (`KeychainService.saveDisguisePassword`). That device ID isn't secret, so anyone who can read the app's keychain items gets the password directly, with no guessing needed. Changing your password copies the new one there automatically. Nothing reads this copy any more (unlock checks the real credential), so it could simply be removed.

**2. The calculator has no limit on guesses.** Every press of "=" checks the typed digits against the vault password (`CalculatorViewModel.checkPasswordSequence`). That path never counts failures, so the 5-attempt lockout doesn't apply. The feature also requires a password made only of digits and ".", with a minimum of 6. Anyone holding an unlocked phone can keep guessing a short PIN without limit.

## Medium

3. **The lockout on the normal login screen resets on relaunch.** The failure count and lockout time are only held in memory, so force-quitting the app clears them. There's also no growing delay between attempts.
4. **Album passwords have no attempt limit.** `AlbumStore.unlock` doesn't count failures. Once someone is inside the vault, they can guess a separate album password without limit (minimum length 6).
5. **The dev app's metadata isn't encrypted (it's the default build scheme).** This is documented, but worth stressing:
   - The SwiftData store holds file names, notes and 300px thumbnails of your photos and videos as plain JPEGs.
   - It sits in Application Support with iOS's default file protection, so it can end up in iCloud or computer backups.
   - On the oldest credential format, your login password is itself the file key. Files copied out in a backup can then be guessed offline.
6. **The key-derivation setting is low.** It uses PBKDF2-SHA256 at 100,000 rounds; current guidance for this algorithm is about 600,000. With a random data key (the 1.0 library) it hardly matters. It does matter for the stored login record, album passwords and old libraries where the password is the key.
7. **Decrypted copies can be left in temporary storage.** The video player, document preview, audio sharing and album export write full decrypted copies to the temp folder under random names. These are deleted on normal close, but at startup the app only cleans up its own named folders. If the app crashes or is killed while something is open, the decrypted copy stays until iOS clears it. They do use the strongest file protection.

## Low

8. **Old weak password hashes.** The legacy owner and Guest Mode passwords are stored as a single salted SHA-256, which is fast to guess if extracted. This is dev app only; 1.0 turns Guest Mode off.
9. **The vault key stays in memory while backgrounded.** Auto-lock is only checked when you come back to the app. It's skipped entirely while a recording exists, and "Never" is an option. The default ("Immediately") is good.
10. **Password-wiping is partial.** `SecureBytes` is undermined by frequent `.string` copies, and `sessionLoginPassword` is a plain String.
11. **Old encrypted-file format can be tampered with.** The legacy ZNSC v1 format, still accepted when reading, doesn't tie each chunk to its position. Someone with write access could reorder or cut it off without detection. Separately, a stored file isn't tied to its library entry, so encrypted files could be swapped between entries.
12. **Stored file paths aren't checked.** `FileStorageService.getFileURL` accepts absolute paths and `..` without confirming they stay inside the storage folder. This is only exploitable if the stored metadata has been tampered with.
13. **No screen-recording or AirPlay detection while showing content.** The app-switcher snapshot is covered.

## Things that looked solid

- **File and metadata encryption:** new files use AES-GCM chunks tied to their position and length, with a proper end marker. The 1.0 library index is well designed: a random 32-byte data key, an HKDF-derived encrypted SQLite index, and checks against symlink tricks.
- **Biometrics and keychain:** Face ID secrets are protected by the keychain's own Face ID requirement (`.biometryCurrentSet`). Keychain items are this-device-only.
- **Backups:** age backups use scrypt at N=2^18 and require 12+ character passwords. The recovery tool pins age's checksum and rejects links and unsafe paths when unpacking.
- **Secrets in the repo:** none committed; the team ID in the project file isn't sensitive.

The top two can be fixed together: delete the stored calculator password copy, and route calculator unlocks through the same failure counter as the login screen, saved so it survives relaunch. Item 3 needs that same counter.
