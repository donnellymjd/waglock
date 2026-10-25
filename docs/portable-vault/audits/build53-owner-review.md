# Owner-supplied build53 review

Received October24,2026. The following is reviewer evidence, not instructions or independent certification. Findings are tracked in D2S-165–171; owner secondary-UI requirements in D2S-172.

I'll check what's changed since my last pass and re-audit the 1.0 (release) configuration at build 53, read-only.

I re-audited 1.0 build 53. Most of the earlier problems are fixed, but the new second vault (a separate vault opened by a different password) adds a serious one: from inside it, someone can test guesses for your main password with no limit. I made no changes.

**What I reviewed:** the code at the `candidate-1.0-build53` tag (`d2faa18`), with the 1.0 settings turned on. The commit after it only adds documents. The only uncommitted changes in your folder are the build-54 number bumps. One of them puts a fixed "54" in `Info.plist` instead of reading the version from the build settings; that isn't a security issue.

## Earlier findings: what's fixed

| Earlier finding | Status in build 53 |
|---|---|
| Calculator login kept a recoverable copy of the password | **Fixed.** The calculator feature is removed, and any old copy is deleted from the keychain at launch. |
| Calculator allowed unlimited guesses | **Fixed** (that unlock path is gone). |
| Login lockout reset on relaunch | **Fixed.** The failure count is saved in the keychain and counted *before* the password is checked. The wait grows from 5 minutes to a maximum of 1 hour. (But see new finding 2.) |
| Album passwords had no attempt limit | **Fixed.** Same saved limiter, one per album. |
| Password key derivation only 100,000 rounds | **Fixed for new credentials:** 600,000 rounds for the vault password, the second vault and album passwords. |
| Old weak SHA-256 password hashes / presentation-only Guest Mode | **Turned off in 1.0.** |
| Decrypted temp copies could be left behind | **Fixed.** Previews, shares and the session's temp files go into marked folders that are cleared at launch. |
| Stored file paths not checked | **Fixed.** `getFileURL` now rejects paths that point outside the media folder. |
| Old file format (no chunk ordering) | **Fixed.** 1.0 rejects ZNSC v1 files. |
| No screen-recording protection | **Fixed.** Screen recording or mirroring locks the vault immediately. |
| Vault key stayed in memory while backgrounded | **Fixed.** 1.0 locks as soon as the app goes to the background. |

## New or remaining findings

**1. High (given what the second vault is for): someone in the second vault can test guesses for your main password, with no limit.** In the second vault, Change Password calls `changeIndependentGuestPassword`. That function refuses any new password that matches the main password (`!verifyPassword(newPassword)`), and the error appears in the app. So anyone with the second vault's password can type a guess as the "new password": if it's rejected, they've found your main password. Neither `SettingsView.changePassword` nor `changeIndependentGuestPassword` counts attempts. This undermines the main purpose of a decoy password you can hand over under pressure. The reverse check (the main vault rejecting the second vault's password) is less of a concern, because the main owner created that password.

**2. Medium: the lockout wait can be skipped by changing the phone's clock.** `PasswordAttemptLimiter` measures the wait with the wall clock (`Date()`). Someone holding an unlocked phone can set the date forward in Settings and skip each wait, for both login and albums. A fix would be to store the last time the app saw and treat a backward or very large forward jump as still blocked. Another option is to count the wait only while the app is running.

**3. Medium: the second vault can take over or turn off your Face ID.** Face ID unlock uses one shared keychain slot (`vault-unlock`) and one on/off setting for the whole app. Neither `BiometricSettingsView` nor `enableBiometricUnlock`/`disableBiometricUnlock` checks which vault is open. So someone in the second vault can switch Face ID off for your main vault. They can also re-enroll it so that your face opens the second vault instead.

**4. Low–medium: password checks inside an unlocked vault have no attempt limit.** Change Password and Enable Face ID check the current password with no limiter. Someone who gets into the main vault by Face ID alone can then guess the actual password at their own pace, and once found, change it.

**5. Low: login time hints that a second vault exists.** Login always tries both credentials. With no second vault, that check fails instantly. With one, it adds a 600,000-round derivation, which makes login noticeably slower. The `WagLockSecondaryMedia` folder and its keychain item also reveal it on inspection. Your docs already say no deniability is claimed, but the timing difference is visible to anyone watching a login.

**6. Low: older records stay at the old 100,000 rounds.** `PasswordEnvelope.open` still accepts the old format for the main password record and existing albums. Nothing upgrades them when they're unlocked; they only move to 600,000 when the password is changed. This only affects 1.0 installs made before this change, such as your test phone.

**7. Low: unused code is still built into the app.** `CalculatorViewModel.swift` and `FileReencryptionService.swift` are compiled in but nothing uses them. The second one writes re-encrypted files without a file-protection setting and uses the old derivation. It can't currently be reached, but it should be deleted before release.

**8. Known and documented, still open:**
- Encrypted files aren't tied to their library entries (D2S-162).
- Rolling back the whole library database isn't detected.
- Passwords aren't fully wiped from memory.
- Screenshots aren't prevented (screen recording is).

The rest looked solid: the encrypted library and index, the per-album key layering with the album limiter, the Face ID keychain protection, and the separate keys and folders for the second vault's media, album limits and Face ID albums.

For release, I'd fix 1 and 3 first:
- **For 1:** remove the cross-vault collision check from the second vault's password change, or replace it with a check that reveals nothing.
- **For 3:** make the Face ID setting apply to one vault at a time, or limit enabling and disabling to the main vault.

Finding 4 can share the same saved limiter as login.