# WagLock Dev Encrypted and the WagLock Dev deprecation

Decided by the owner on 2026-11-10. See [ADR-031](decisions.md#adr-031--waglock-dev-encrypted-replaces-the-legacy-dev-build).

## Three builds

| Build | Scheme / configuration | App ID | Home-screen name | Library |
| --- | --- | --- | --- | --- |
| WagLock Dev (**deprecated**) | `WagLock` / Debug, Release | `com.d2sci.vaultito.dev` | WagLock Dev | Legacy store: encrypted media, plaintext SQLite index and thumbnails |
| WagLock Dev Encrypted (new) | `WagLock Dev Encrypted` / DevEncrypted | `com.d2sci.waglock.dev` | WagLock Dev+ | Encrypted library, 16-slot passcodes |
| WagLock (App Store candidate) | `WagLock App Store` / AppStore | `com.d2sci.waglock` | WagLock | Encrypted library, 16-slot passcodes |

`config/DevEncrypted.xcconfig` sets the identity and `WAGLOCK_ENCRYPTED_LIBRARY = YES`. Each app has its own container, Keychain namespace, preferences and media. Installing one never reads, moves or deletes another's data. The new build starts empty: nothing is migrated from WagLock Dev or from the App Store candidate.

## Why the legacy Dev build is being retired

WagLock Dev encrypts every media file, but its SwiftData index is plain SQLite protected only by iOS file protection. File names, sizes, dates, dimensions, album structure and thumbnails sit outside the vault password (audit A01). It also runs the older login, Guest Mode and password-management flows rather than the library slots, Graphite onboarding and erase flow that ship in 1.0. Testing on it no longer tells us much about the release.

WagLock Dev Encrypted runs the release code paths under a separate, debuggable identity, so new features can be tested on the phone without touching the App Store candidate's libraries.

## Deletion goal: December 15, 2026

Goal: delete the WagLock Dev app (`com.d2sci.vaultito.dev`) from the owner's phone and remove its configuration from the project by **2026-12-15**. This is a target, not an automated action. Nothing in WagLock deletes another app or its data.

Before deleting it from the phone:

1. Copy out anything worth keeping. WagLock Dev cannot make an age backup of the encrypted-library kind, so export the media you want (Export or Save to Photos/Files), then import it into WagLock Dev+ or the release app and check it opens.
2. Keep independent originals until the new copies are checked.
3. Deleting the app removes its container. Its Keychain items may persist on the device; they are inert without the app.

Project clean-up after that date (separate commit, after the owner confirms the phone copy is gone or no longer needed):

- Retarget the `WagLock` scheme and Debug/Release configurations to the encrypted identity, or remove them.
- Update tests that assert the legacy identity (for example `LocalizationCoverageTests` expects `com.d2sci.vaultito.dev` and "WagLock Dev"), and decide which legacy reader tests still guard release behavior.
- Keep historical Keychain service strings and cleanup aliases where release code still references them; removing the build is not a licence to rename namespaces.

## Signing and installation

The new App ID needs an Apple Development profile. Xcode creates it with automatic signing when the owner selects the team and runs the `WagLock Dev Encrypted` scheme on the phone. This repository change does not register the App ID or touch provisioning. No upload or distribution is implied.

The DevEncrypted configuration has no `CODE_SIGN_ENTITLEMENTS`: the webcredentials association lists only the release App ID, so Password AutoFill domain pairing is not expected in this build. Password managers may still offer manual fill.

Explicit erase (forgotten passcode → start over) is enabled for both encrypted identities. Its Keychain scope is the exact namespace of the running app, so the release and Dev Encrypted builds never erase each other's services, and the legacy Dev build never gets an erase factory.

## Status

Written without a compiler or Xcode in this environment. The project file and scheme were edited by hand; open the project once in Xcode to confirm the new configuration and scheme appear and that the DevEncrypted build signs and runs.
