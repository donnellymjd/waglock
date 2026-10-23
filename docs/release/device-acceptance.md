# Fresh encrypted candidate physical acceptance

Open **WagLock**, version1.0/build49, bundle `com.d2sci.waglock`. It is a separate fresh encrypted app. **Keep WagLock Dev installed**; no library has been migrated or deleted. Only disposable test samples are needed. The phone was locked when remote launch was attempted; open the new app manually.

1. Create a new password; switch Number pad/Full keyboard as needed. Quality feedback belongs only to setup/change forms. Import a photo and short video from Photos/Files. Open them and check standard native video controls and proportions.
2. Create a note and a draft. Without tapping Done, background/lock, unlock and return to Notes. Confirm Unfinished note → Resume draft is visible and reopens the exact draft; then save it. Also try backgrounding an edit to an existing saved note. Create a nested album with a distinct password, put a sample inside and verify parent/album protection.
3. Change the main password. Relaunch; verify the old password fails and the new one opens the **same** media, notes and albums. A main-password change must not replace a separate album password.
4. Enable optional Face ID. Check success and cancellation; background/lock during photo/video/PDF viewing, then reopen/unlock. No closure, stale private content or silent record deletion should occur.
5. Create an encrypted backup with a new export password. Clear/edit its filename, save using Files (optionally your configured cloud provider), and check the saved file exists. Provider acceptance alone does not guarantee a completed remote upload.
6. Recover that file on the Mac with the checked-in helper into a **new** destination. Enter the export password, then each distinct protected-domain password when requested. Open a recovered photo/video and note from **Library**; check nested folders. Do not send passwords or private media.

```sh
python3 ~/repos/WagLock/tools/backup_recovery.py \
  ~/Downloads/My-WagLock-Backup.tar.age \
  ~/Downloads/WagLock-Recovered-Build47
```

Substitute the actual saved filename. Keep all originals and the old app. This validates explicit portable export, not raw native-folder recovery, automatic iOS restore or an in-app restore wizard. Report “passed” or the failing step; acceptance is pending until the owner responds.

Build47 specific acceptance: the owner confirms the same password opens the app and two lock/unlock cycles pass after the verified Apple-directory alias correction. Complete the remaining media/notes/album/FaceID/backup checks above before release.
