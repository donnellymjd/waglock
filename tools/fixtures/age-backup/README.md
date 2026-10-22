# Public synthetic age backup fixture

**All content and credentials here are intentionally public disposable test data. Never use these passwords for real content.** No owner media, phone credentials or Keychain entries were exported. The 248 KiB encrypted fixture was produced by `PortableExportSnapshotTests.testCompleteNativeBackupFixtureForIndependentRecovery()` using the actual iOS backup writer on the disposable simulator. It includes seven generated payloads, notes/drafts, Unicode metadata and two independently password-protected nested domains. Original plaintext source files are not required for verification; expected hashes and values are recorded separately.

`provenance.json` pins the encrypted fixture SHA-256. `expected.public.json` contains public-only fixture credentials and expected values. Recover using Python and the **unmodified official age CLI** (this fixture checker takes an explicit installed age path; the user-facing recovery helper also supports automatic setup):

```sh
python3 tools/check_backup_interop.py --age /path/to/age
```

This POSIX-terminal test was validated on macOS with age 1.3.2. It invokes the same independent recovery helper documented for users, verifies all payload/metadata values, rejects parent-only access to both protected children, and verifies tampering/truncation failure and staging cleanup. It creates/removes only its own temporary extraction directory. It never connects to a phone, provider or live library. The terminal-driving helper is for this fixed public fixture only; real passwords belong in age's interactive prompt.

To regenerate, run the named XCTest on a disposable simulator, then export its `public-native-backup.tar.age` and `public-native-backup-expected.json` attachments with Xcode's test-result attachment exporter. Update the fixture, expected values and pinned provenance together, and repeat independent CLI verification. Public fixture password randomness does not make these credentials private.
