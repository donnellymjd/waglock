# Libraries and passcodes: 16-slot model (ADR-029)

Status: **implemented in source on 2026-11-09, not yet compiled, tested or reviewed.** The owner chose to implement the whole handover, key slots included, before the crypto review the handover asked for. Everything below is a design sketch that still needs the reviewer's sign-off. It is not a vetted construction.

Source: the "WagLock Redesign — Handover & Privacy Spec" document (2026-11-08) and the "WagLock Redesign" canvas. [Graphite redesign](graphite-redesign.md) covers the UI half.

## Goal and rule

Deniability of count: someone holding the unlocked phone and one passcode must not be able to tell from the app whether any other library exists. WagLock is open source, so the feature itself is public. Only the number of libraries on this phone is secret.

The rule: nothing in the UI, timing or notifications may differ based on whether other passcodes exist. Storage-level indistinguishability is **only partly met**; see [Known gaps](#known-gaps-and-reviewer-items).

## Where it applies

- **Slot mode** is on when `AuthenticationViewModel.usesLibrarySlots` is true. That means the release encrypted identity (`independentVaultsEnabled`) running with managed installation state. Tests opt in with `librarySlotsEnabled: true`.
- The Dev identity (`com.d2sci.vaultito.dev`) keeps the inherited legacy flows, including its presentation-only Guest Mode. Its credentials and data are untouched.
- In slot mode this ADR supersedes ADR-027 (D2S-178 primary-only password management). Every library is a peer: there is no main or alternative library, and no "verify both passwords" flow.

## Construction

| Piece | Implementation |
|---|---|
| Table | One Keychain item `waglock.library-slots.v1` in the app's service namespace (so explicit erase covers it). Layout: 41-byte header plus 16 slots of 412 bytes, 6,633 bytes in total. |
| Header | `WLKS`, format 1, KDF id 1 (scrypt), log2 N, r, p, 32-byte random app-wide salt. The whole header is AEAD associated data, so a changed parameter makes every slot fail. |
| Slot | AES-256-GCM over a 384-byte padded plaintext (2-byte length, sorted JSON payload, random padding): 12-byte nonce, ciphertext, 16-byte tag. AAD = header, slot index, namespace, so a slot moved to another index fails. |
| Unused slot | 412 random bytes, the same length and position as a used slot. |
| Payload | `{version: 1, library, secret, timeLockUntil?}`. `library` is `.independent(UUID)` for every library made by slots, or `.legacyOwner` for an upgraded install's pre-slot library. `secret` is that library's existing data password, unchanged. |
| KDF | One scrypt derivation (N = 2^16, r = 8, p = 1, 64 MiB) via the bundled Tarsnap reference core, then HKDF-SHA256 with the header as salt and the namespace in `info`. |
| Unlock | One derivation, then a trial unwrap of all 16 slots every time. The first slot that authenticates wins. No match means a wrong passcode. |
| Allocation map | `waglock.library-slot-allocation.v1`: a version byte and a 16-bit used mask, so "Add another passcode" never overwrites an unknown library. Written before the slot (a crash leaves a wasted random slot, never an unallocated live one). |
| High-water clock | `waglock.library-clock.v1`: the latest wall time observed. Time locks compare against `max(now, highWater)`. |

Code: `WagLock/Services/LibrarySlotTable.swift` (crypto and storage), `WagLock/Services/LibraryPasscodeService.swift` (operations, shared counter, timing), `WagLock/Services/LibraryContentRemover.swift` (scoped deletion), and the slot branches in `AuthenticationViewModel`.

## Operations

All of them go through `LibraryPasscodeService`, share the existing durable `PasswordAttemptLimiter` ("vault" scope), and are padded to a 1.5-second minimum duration.

- **Create (onboarding):** 6–128 characters and a confirmation, plus a required "There is no passcode reset" acknowledgment. This makes the table and the first `.independent` library.
- **Add another passcode:** the collision check is the unlock path itself. A weak passcode, a collision with any slot or pre-slot credential, or a full table all get one generic message ("This passcode can't be used… try again in 30 seconds"), a 30-second wait (`PasswordAttemptLimiter.imposeWait`) and a spent attempt. The new library opens on the next unlock with that passcode.
- **Change this passcode:** verifies only this library's current passcode, runs the same collision check, then rewrites this slot in place under the new key. The data secret is unchanged and the result is read back.
- **Time lock:** confirmed with this library's passcode; 1 hour, 24 hours, 3 days or custom. Nothing can end it early. While it is active, the passcode behaves exactly like a wrong one and counts as an attempt. Face ID is removed if it opened this library. On the first unlock after expiry the field is rewritten away, leaving no trace.
- **Delete this library:** a confirmation toggle plus this library's passcode. The slot is overwritten with fresh random bytes (crypto-erase) and its allocation is freed. Its Face ID grant, if any, is removed. WagLock locks, then removes only that library's exact roots and Keychain services. Backups, Photos and Files are untouched.
- **Face ID:** opens at most one library and always that one. It is assigned from inside a library with that library's passcode, and assigning it moves it. Unassigned libraries show "Off for this library" and cannot turn off another library's Face ID.
- **Wrong passcode:** "Wrong passcode. N tries left before a 5-minute wait." The text is the same whichever library was targeted. The 5-minute value is the existing limiter schedule; the canvas shows 1 minute.

## Pre-slot installs (no reset, no migration of data)

On the first successful legacy unlock in slot mode, the library's existing data secret is enrolled into a new slot: `.legacyOwner`, or `.independent(id)` for the pre-slot alternative library. The slot is read back. Only then is that library's old Keychain wrapper retired, after a source-equality check. Library files, keys, identities and stores are not moved or rewritten. Any slot-verified session also retires its own library's leftover wrapper, so an old passcode cannot outlive a change. Enrollment is best effort: on failure the old wrapper stays and login still works. The inherited presentation-only guest hash is retired once slots exist.

## Known gaps and reviewer items

These are honest limits of this build, not claims of deniability:

1. **Storage reveals count to anyone who can read app files or the Keychain.** Each `.independent` library still has its own directories (`Documents/WagLockSecondaryMedia/<id>`, `Application Support/WagLockSecondaryLibraries/<id>`) and Keychain services (`<ns>.vault.<id>`). The allocation map also records how many slots are used. All of this is device-only (`WhenUnlockedThisDeviceOnly` Keychain; app sandbox), but forensic extraction sees it. Hiding it needs the fixed-size container (item 4).
2. **Fixed-size storage is not implemented.** Only Standard exists. The onboarding storage step, Settings › Storage mode switching, "Reserved space full" and "Switching storage" are not built. In Standard mode, iOS storage settings show WagLock's total size.
3. **KDF:** scrypt was chosen because it is memory-hard and already vetted in-app for age backups. Argon2id would need a new dependency. On-device duration and memory at N = 2^16 with the reference core are unmeasured, and the Secure Enclave plays no part.
4. **Constant time** is approximated with "always try 16 slots" plus a 1.5-second floor. The pre-slot enrollment path, Face ID and setup are not padded. A real Keychain write happens only on success or time-lock expiry, which a careful observer could time.
5. **Time lock** has no trusted clock. Rolling the clock back cannot shorten a lock, but rolling it forward can end one early. A clock set far ahead pins the high-water mark there.
6. **Delete** relies on crypto-erase. File removal is best effort with no resume journal, so leftovers are unreadable but take up space. For an upgraded `.legacyOwner` library, its identity and commit anchors stay in the Keychain. Whether overwriting one Keychain item is enough on flash storage is for the reviewer.
7. **Backups** keep the existing per-library age format. No size-padding policy exists yet.
8. **Biometric marker:** the pre-slot spelling `primary` is still the internal device-only owner marker for `.legacyOwner`. It is never shown.

The handover's crypto-reviewer asks (slot format, KDF, constant time, container deniability, time lock, delete/erase, backups, Face ID, threat model) all remain open. The proposed threat model is an adversary with the unlocked phone, one passcode, compelled Face ID and full knowledge of the source. Forensic imaging is out of scope pending review, which this build does not meet anyway (item 1).

## Tests written (not run here)

`WagLockTests/LibrarySlotTableTests.swift` covers:

- uniform slots
- tamper, truncation and slot-move rejection
- generic collision, weak and full-table rejection with the 30-second wait
- a 16-library cap
- change isolation
- time lock as a wrong passcode, with rollback resistance and trace removal
- crypto-erase delete
- pre-slot enrollment and wrapper retirement
- an unavailable Keychain treated as neither a wrong passcode nor a setup prompt

`WagLockTests/LibrarySlotAuthenticationTests.swift` covers:

- peer libraries with identical controls
- each library changing its own passcode
- identical wrong and time-locked messages
- Face ID moving between libraries, with only its holder able to turn it off
- delete removing only that library's passcode and Face ID

The release UI tests in `WagLockUITests/EncryptedReleaseUITests.swift` were rewritten for the Passcodes flow. They replace the ADR-027 primary-only tests.

This environment had no Swift toolchain, so none of the code above has been compiled. Build with Xcode and run `xcodebuild test` before relying on any of it.
