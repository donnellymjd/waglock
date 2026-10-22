# Disposable encrypted metadata crash checks

From the repository root on macOS with Xcode command-line tools:

```sh
python3 spikes/encrypted-metadata/run.py
```

Compiles the app's unused metadata candidate with the public synthetic fixture in `CrashProbe.swift`. Uses a new temporary directory, never the app library. A child exits with status 71 before commit and 72 after commit; the parent checks complete old/new revisions on reopen and removes only its temporary fixture directory. No dependencies are downloaded. This tests process termination at transaction boundaries, not hardware power failure.

See [design, validation and activation gates](../../docs/portable-vault/encrypted-metadata-candidate.md). Do not use these fixture keys or this unapproved candidate format for real data.
