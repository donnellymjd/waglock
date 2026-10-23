# Build50 note autosave correction

Source freeze: `candidate-1.0-build50`. Public release identity: `com.d2sci.waglock`, version1.0/build50. Existing development identity/container remains separate. This source corrects delayed autosaves cancelling their own encrypted writes; it does not change encryption formats, credentials, backup formats or migration policy.

- [Unit/security summary](unit-summary.json):283 passed, zero failed/skipped. Includes a real encrypted-repository delayed-save/cold-reopen regression that fails before the correction (`/private/tmp/waglock-build50-debounce-before.xcresult`). Final full result: `/private/tmp/waglock-build50-debounce-full.xcresult`.
- [Signed phone package](package.json): identity/name, encrypted flag, source/license notices, privacy reasons and signature checks pass. Phone build: `/private/tmp/waglock-build50-debounce-phone.log`.
- Actual signed release, iPhone17Pro/iOS26.5: paused body-only draft from empty Notes survives background locking and cold relaunch (67seconds); repeated draft editing/Done removal/existing-note background edit passes (106seconds). Both cases pass in `/private/tmp/waglock-build50-final-signed-ui.xcresult`; its obsolete negative-argument no-lock case fails, so that mixed run is not an overall pass.
- Corrected no-lock check selects Never through Settings: five paused-edit/background cycles retain the open editor and exact text, with no save-error message; Resume draft remains visible after Back. `/private/tmp/waglock-build50-never-lock-ui.xcresult` passes (98seconds, zero failures/skips).

[Investigation and corrected assumptions](../../../portable-vault/draft-preservation.md) describe the invalid negative launch argument, fixture editing assertions and unsigned-simulator Keychain limitation. Only correctly signed actual release runs count as UI evidence. All fixtures contain generated public samples; earlier fixtures were preserved.

Build50 is installed over the existing WagLock release identity with its library and credentials preserved. Physical iOS27.0.1 repetition remains required. No App Store upload/submission, distribution signing approval, new App ID registration, owner library reset or data migration is implied. Prior build47 archive/screenshots are historical and need an appropriate final distribution rebuild/review.
