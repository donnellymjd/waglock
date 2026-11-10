# Auto-lock delay and short passcodes

Decided by the owner on 2026-11-10 (ADR-032): "I want that as an option. I also want users to be able to have shorter passcodes. This should be options in the onboarding flow as well as in settings. Just like the fixed library size options, let's note the security risks but let the user decide."

Both choices apply to the encrypted builds (App Store and WagLock Dev Encrypted). They are app-wide and device-only (preferences), look the same in every library, and say nothing about how many libraries exist. The defaults are the most private choice: Immediately, and Standard length. Erase resets both.

## Where they appear

- **Onboarding:** a new step, "How should WagLock lock?", between Storage and Create passcode. It comes before the passcode so the length rule applies to the first one.
- **Settings › Security & access › Locking:** Auto-lock and Passcode length rows. The Auto-lock stat card shows the current choice, in amber when it isn't Immediately.

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

## Passcode length

| Option | Rule for new and changed passcodes |
| --- | --- |
| Standard (default, recommended) | 6–128 characters. |
| Short | 4–128 characters, so a 4-digit PIN is allowed. |

- `PasscodePolicy` holds the rule. `LibraryPasscodeService` checks it on first setup, add and change. A too-short proposal gets the usual generic rejection and 30-second wait.
- **Unlock never checks length**, so switching back to Standard never locks anyone out. Existing short passcodes keep working; new and changed ones must meet Standard again.
- Album passwords and backup passwords keep their own 6+ rule.
- The legacy WagLock Dev build doesn't offer the choice and keeps 6+.

**Risks stated in the app:** a 4-digit PIN has only 10,000 possibilities. On the iPhone, the shared attempt counter and 30-second wait slow guessing. Someone with a full copy of the iPhone's data, including its Keychain, could try every 4-digit PIN within minutes. Each guess costs one scrypt derivation (N = 2^16) however many libraries there are.

## Tests

- `WagLockTests/PasscodePolicyTests.swift`: length rules, the legacy build can't allow short passcodes, short passcodes need the choice, and they keep working after it's turned off.
- `EncryptedReleaseUITests` passes the new onboarding step and finds both Settings rows.
- Not compiled or run in this environment.
