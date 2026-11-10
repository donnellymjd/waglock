# Auto-lock delay and short passcodes and passwords

Decided by the owner on 2026-11-10 (ADR-032): "I want that as an option. I also want users to be able to have shorter passcodes. This should be options in the onboarding flow as well as in settings. Just like the fixed library size options, let's note the security risks but let the user decide."

Both choices apply to the encrypted builds (App Store and WagLock Dev Encrypted). They are app-wide and device-only (preferences), look the same in every library, and say nothing about how many libraries exist. The defaults are the most private choice: Immediately, and Standard length. Erase resets both.

## Where they appear

- **Onboarding:** a new step, "How should WagLock lock?", between Storage and Create passcode. It comes before the passcode so the length rule applies to the first one.
- **Settings › Security & access › Locking:** Auto-lock and Passcode length rows. The Auto-lock and Face ID status cards at the top open their settings; the Auto-lock card shows the current choice, in amber when it isn't Immediately.

Each option is a card with its risks listed, like the storage modes (`WagLockOptionCard`, `LockingOptionsViews.swift`).

## Auto-lock

| Option | Behaviour |
| --- | --- |
| Immediately (default, recommended) | Locks on background, as before: the library key leaves memory at once. |
| After 1 minute / After 5 minutes | On background, album keys, previews, exports and caches still close (`suspendAlbumAccess`), but the library session stays. On return the library reopens without the passcode if less time has passed, otherwise it locks. |
| Only when you lock it | As above with no time limit. It locks on Lock WagLock, on screen recording or mirroring, and when iOS ends the app. |

- The delay uses `ContinuousClock`, which keeps counting while the phone sleeps and can't be stretched by changing the iPhone's clock.
- The check happens when WagLock returns to the foreground. iOS suspends apps shortly after they leave, so WagLock can't lock itself while suspended; the key stays in memory until it returns or iOS ends it.
- Screen recording or mirroring always locks at once, whatever the setting.
- An unsaved audio recording still postpones the lock, as before.

**Risks stated in the app:** until the time runs out, anyone holding the unlocked iPhone can open WagLock without its passcode, and the library key stays in the iPhone's memory while WagLock is in the background. With "Only when you lock it", anyone who can unlock the iPhone can open WagLock.

## Passcode and password length

The owner extended the choice to album and backup passwords later the same day ("allow short album and backup passwords too"). One setting covers all three.

| Option | Library passcodes | Album passwords | Backup passwords (incl. Face ID-only album export passwords) |
| --- | --- | --- | --- |
| Standard (default, recommended) | 6–128 | 6–128 | 12+ |
| Short | 4–128 | 4–128 | 4+ |

- `PasscodePolicy` holds the rules (`minimumLength`, `albumPasswordMinimum`, `backupPasswordMinimum`).
  - `LibraryPasscodeService` checks the passcode rule on first setup, add and change, before anything else. A too-short or too-long passcode is reported plainly ("Too short. Use at least N characters.") with no attempt used and no wait: the rule is public and the same for every library, so this reveals nothing about other libraries. Only collisions and a full table get the generic rejection and 30-second wait.
  - Every new-passcode and password field shows the same hint while it's too short, and its button stays disabled.
  - `AlbumStore` checks the album rule on create and on a security change.
  - `PortableBackupSession` and `PortableBackupView` check the backup rule.
- **Unlocking never checks length**, so switching back to Standard never locks anyone out. Existing short passcodes and passwords keep working; new and changed ones must meet Standard again.
- This lowers the independent backup-password requirement from D2S-177 (12+), but only when the person chooses Short. The current-vault-password reuse path is unchanged.
- The legacy WagLock Dev build doesn't offer the choice and keeps its rules.

**Risks stated in the app:**
- A 4-digit PIN has only 10,000 possibilities.
- On the iPhone, the shared attempt counter allows 4 wrong tries, then waits 5, 10, 20, 40 and then 60 minutes before each further try, so trying every 4-digit PIN would take months. Someone with a full copy of the iPhone's data, including its Keychain, could try every 4-digit passcode within an hour. Each guess costs one scrypt derivation (N = 2^16) however many libraries there are.
- A backup file has no wait. Anyone who gets a copy, for example from a cloud account, could try every 4-digit backup password within hours on an ordinary computer (age scrypt, N = 2^18). When Short is on, the backup screen repeats this and recommends several random words.

## Tests

- `WagLockTests/PasscodePolicyTests.swift`: length rules for all three, the legacy build can't allow short ones, short passcodes need the choice, and they keep working after it's turned off.
- `EncryptedReleaseUITests` passes the new onboarding step and finds both Settings rows.
- Not compiled or run in this environment.
