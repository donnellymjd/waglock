# App Review Information — Graphite redesign build

Draft answers to Apple's Guideline 2.1 "Information Needed" request (received 2026-10-31 for the build submitted then). It describes the **redesign build**: Graphite UI, up to 16 passcodes (ADR-029), fixed-size storage (ADR-030), Live Photos, Select All import and the locking choices (ADR-032).

The earlier walkthrough in [review-notes.txt](review-notes.txt) describes the build-64/65 candidate. It is kept unchanged for that candidate. Before submitting, replace the build number below and check every path against the exact build you upload.

Apple asks for this information both as a reply in App Store Connect and in **App Review Information → Notes**. The Notes field has a character limit; if the full text doesn't fit, put sections 2–6 there and send the recording and the full text as the reply.

---

## 1. Screen recording (script)

Record on a physical iPhone running the latest iOS. Start from the Home Screen and launch WagLock. Use disposable sample photos, a video, a Live Photo and a PDF.

1. **First run.** Launch WagLock. Welcome → Get started.
2. **Storage.** Show both options, keep Standard, Continue.
3. **Locking.** Show the Auto-lock and Passcode & password length options with their warnings. Keep Immediately and Standard, Continue.
4. **Passcode.** Create a passcode, confirm it, turn on "There is no passcode reset", Continue. Show "Your way back" (backup reminder) and choose Not now.
5. **Import.** Tap + →
   - Photos & videos (iOS picker): add a photo and a video.
   - Select all from Photos: allow access, pick an album, tap Select All, Add. On "Originals are still in Photos", tap Keep.
   - Files: add a PDF.
   - Take photo or video: take one photo.
6. **Use.** Open a photo, then the Live Photo (tap LIVE), play the video, open the PDF.
7. **Albums.** Albums → New album with its own password → Add to album → Move from Library. Lock the album and unlock it again.
8. **Notes.** Notes → New note, type, Done.
9. **Lock and unlock.** Go to the Home Screen and return: WagLock is locked. Unlock with the passcode. Settings → Security & access → Face ID → Use Face ID here, then lock and unlock with Face ID.
10. **Additional passcodes.** Settings → Security & access → Passcodes → Add another passcode → Create library. Lock WagLock, enter the new passcode: an empty, separate library opens. Lock, enter the first passcode: the original library opens.
11. **Backup.** Settings → Encrypted backup: create a password-protected backup and save it to Files.
12. **Forgotten passcode and erase.** Lock. On the unlock screen tap "Can't unlock?" → show the help, then Erase WagLock: acknowledge, type ERASE, confirm. WagLock returns to Welcome. (Do this last.)

There are no accounts, no user-generated content shared with others, and no paid content, so account deletion, content reporting/blocking and purchase flows don't apply. Erase WagLock (step 12) deletes everything WagLock stores on the device.

---

## 2. Purpose and target audience

WagLock is a private, encrypted vault for photos, videos, Live Photos, documents, audio files and notes, stored only on the user's iPhone or iPad.

It is for anyone who keeps sensitive personal material on their phone, such as ID documents, medical or financial records, or private photos, and wants it protected by a passcode separate from the device passcode. Items in the Photos app are visible to anyone who unlocks the phone, appear in shared and synced libraries, and are easy to show by accident. WagLock keeps them in a separate, encrypted space.

Everything is encrypted on the device before it is saved, including file names, thumbnails and notes. There is no account, server, tracking or advertising, and WagLock works fully offline. Users can export items, or a complete encrypted backup readable with the open-source `age` tool, at any time. All features are free.

---

## 3. Setup and access

No account or login credentials are needed.

1. **First launch:** choose a storage mode and the locking options (the defaults are the most private), then create a passcode of your choice. Keep it for the review; there is no passcode reset.
2. **Adding content:** tap +.
   - Photos & videos (iOS picker; no Photos access needed)
   - Select all from Photos (asks for Photos access; adds whole albums at once)
   - Files, Audio, Paste and Take photo or video
   Any photos, videos or PDFs work as sample files. After an import, WagLock offers to remove the originals from Photos or Files; that needs an explicit tap and, for Photos, the iOS confirmation.
3. **Main features:**
   - Library and Albums: albums can have their own password or Face ID.
   - Notes, Files.
   - Viewers for photos, Live Photos, video, PDFs and audio.
   - Settings → Encrypted backup (an age-format backup with a separate password or a recovery key).
   - Settings → Storage (Standard or Fixed size).
   - Settings → Security & access: Face ID, Passcodes, Time lock, Auto-lock, Passcode & password length.
4. **Additional passcodes (please review):** Settings → Security & access → Passcodes → Add another passcode. Each passcode opens its own separate library with its own encryption key, up to 16 on one device. There is no library list or switcher: to open another library, lock WagLock and enter that library's passcode on the normal unlock screen. Wrong passcodes all get the same message whichever library they were meant for. After 4 wrong tries in a row, WagLock waits 5 minutes before the next try, doubling up to an hour. A passcode that can't be added (too short, already in use, or no room) gets one generic message and a 30-second wait. This is a disclosed privacy feature with no review-only bypass. WagLock makes no forensic-deniability claim.
5. **Time lock:** Settings → Security & access → Time lock closes the current library for a chosen time; its passcode doesn't open it until the time ends.
6. **Locking:** by default WagLock locks as soon as it leaves the screen. Users can choose a delay in Settings → Security & access → Auto-lock. Screen recording or mirroring locks WagLock at once; stop the recording before unlocking.
7. **Forgotten passcode:** "Can't unlock?" on the unlock screen explains the options and offers Erase WagLock, which deletes everything WagLock stores on the device after an acknowledgement and typing ERASE. Exported backups and originals outside WagLock are not affected.

Not available in this version: recording new audio in the app, and restoring a backup inside the app. Backups are recovered on a computer with the open-source tool documented at https://github.com/donnellymjd/waglock/blob/main/docs/portable-vault/backup-recovery.md.

---

## 4. External services

None. WagLock's core functions run entirely on the device. It uses no data provider, authentication service, payment processor, analytics, advertising or AI service, and has no server of its own.

- When the user chooses, exports and backups are saved through the standard iOS Files picker to a location the user picks, which may be iCloud Drive or another provider.
- Photos access is used only to import items, save a Live Photo back to Photos, or remove originals, each on the user's request.
- Password AutoFill uses an Apple associated-domains file hosted at waglock.d2sci.co. No user data is sent there.

---

## 5. Regional differences

None. WagLock works the same in every region. The app is in English.

---

## 6. Regulated industry or protected third-party material

Not applicable. WagLock is not in a regulated industry and includes no protected third-party content. It is an open-source fork of SealedPocket; upstream attribution and license notices are included in the app (Settings → About WagLock → Open source notices). The bundled Poppins font is under the SIL Open Font License 1.1.

---

## Before sending

- **License status:** the submission package still lists the GPL source/platform/artwork determination (D2S-106) as an open gate. Make sure the answer to section 6 matches where that stands.
- **Encryption:** Apple's encryption questionnaire is separate. Use [the encryption facts](encryption-brief.md); don't claim an exemption in this reply.
- **Screenshots:** they must show this build's actual UI (Guideline 2.3.3). The build-65 screenshots show the earlier design.
- **Build check:** the redesign was written without a compiler in a Linux environment. It needs an Xcode build, `xcodebuild test` and the recording on a physical device before upload.
