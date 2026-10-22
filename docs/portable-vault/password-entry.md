# Shared password entry and local strength estimate — builds 30–31

The owner passed build 29 on the physical iPhone, including retained media/albums, lock and relaunch, password unlock and Face ID success/cancellation. The next requested improvement is identical main/guest password options, number-pad/full-keyboard switching and a live strength score.

Main and current Guest Mode password creation/change now accept 6–128 Swift characters (including Unicode and whitespace). PINs and text passwords are both allowed. Existing numeric guest credentials and existing main credentials keep their encoding and verification paths. Credentials are never trimmed, case-folded, normalized or filtered based on keyboard choice. Main and guest passwords must differ. The guest legacy salted hash and multi-write record format have not been upgraded by this UI work.

Login defaults to a number pad until the user chooses otherwise. A single app preference remembers Number pad or Full keyboard for both app and album login; it does not reveal or depend on which credential matches. Changing the keyboard reloads the active field without replacing it or changing its bytes. A number-pad accessory provides an Unlock action. Password creation/change screens offer the same two keyboard choices; these screens initially use the full keyboard. Existing text passwords remain usable regardless of the selected pad.

As of build 31, a local 0–100 estimate appears only when setting or changing a password (main/guest setup and main password change). It is hidden during app and album unlock, including guest login. The owner confirmed build 30 on the phone and requested this narrower display policy. It considers length and character variety and penalizes short PINs, simple sequences, repeated patterns and a small set of common passwords. It samples at most 129 characters, does not contact a service, and never persists or logs the input. This is a deliberately limited advisory heuristic, not measured entropy, a crack-time prediction or a breach lookup. The score cannot block a valid password or establish that it is secure. The UI labels it an estimate.

Calculator disguise retains numeric/decimal entry. Long-press the display and choose **Use Password** to access the shared login for either text credential. The same action is available to accessibility users. Ordinary calculator entry must wait for authenticated data-key verification: the old view-level notification handler that prematurely set authenticated state has been removed. Only AuthenticationViewModel can publish that verified session.

Current Guest Mode still opens an empty, in-memory presentation. This change does not implement the independent encrypted alternative vault, its recovery or an invisible/forensic-resistant duress mechanism. D2S-115 remains in progress; D2S-127 tracks the input work. Existing Face ID enrollment and the assigned-vault warning are preserved.

## Validation

The final complete unit suite passed **151 tests** (40 XCTest + 111 Swift Testing), including new shared-policy boundaries, numeric compatibility, exact Unicode/space verification, duplicate-password rejection, score behavior and calculator notification/data-key ordering. The signed build compiled, installed and launched on the existing iPhone; the app inventory confirms build 30 under `com.d2sci.vaultito.dev`. Owner subsequently confirmed build 30; see the build 31 follow-up below.

Eight distinct simulator UI workflows pass across populated and fresh fixtures: nested albums, Face ID warning cancellation, retained owner library after relaunch/failed login/logout, live keyboard switching, text/numeric guest passwords (including keypad Unlock), fresh-install branding/limitations, open-source branding/notices, and numeric setup/calculator fallback. Early attempts exposed test fixture assumptions: a launch-argument preference prevented keyboard changes, large lists hid newly created album rows offscreen, and the fresh-install check was mistakenly run on an existing installation. Those assumptions were corrected; no fixture or user media was deleted. The extra calculator test initially terminated before confirming enablement and then tapped the switch label rather than its control. After targeting the actual switch and using a normal background/relaunch transition, the complete fallback workflow passed. This fixture is restricted to its disposable numeric-credential simulator.

Evidence: [password controls](evidence/build30/password-keyboard-strength.png), [retained owner library](evidence/build30/owner-library-remount.png). Logs/results are local temporary artifacts under `/private/tmp/waglock-build30-final-unit`, `-final-workflows`, `-input-workflows`, `-fresh`, `-calculator-controls` and `-regression2`; signed compile/install/launch logs use `-final-device`, `-install`, `-launch` and `-installed-version`. The original failed mixed regression job hung while collecting diagnostics and was interrupted after its test cases had completed; the clean final unit/workflow results are the acceptance evidence.

Use disposable credentials/media for phone acceptance; never send passwords to the development chat.

The final score review additionally penalizes longer repeated words, including repetitions with a missing final separator; focused policy/score tests are recorded in `/private/tmp/waglock-build30-strength-verified`.

The score follow-up passed all four focused policy/score tests after adding those repeated-phrase regressions. Final signed rebuild/install logs use `/private/tmp/waglock-build30-verified-device.log` and `-verified-install.log`.

Final corrected build 30 was installed and launched successfully; `/private/tmp/waglock-build30-verified-version.log` confirms its identity and version. The extra fresh simulator was deleted after testing; it contained synthetic credentials only. Recreate a disposable simulator named `WagLock Build30 Fresh QA` for the numeric calculator fixture. Owner subsequently confirmed build 30; see the build 31 follow-up below.

## Build 31 follow-up

Owner confirmed build 30 keyboard switching, input preservation, scoring and existing unlock behavior. Build 31 removes the score, quality label, progress bar and explanatory text from all login/unlock prompts. Creation and password-change feedback is retained. Keyboard preferences, credential validation, saved passwords and Face ID are unchanged. Both focused UI workflows passed: text/numeric guest password setup retains strength feedback while login hides it; keyboard switching preserves input and unlocks the existing owner library without a score. Results: `/private/tmp/waglock-build31-password-ui.log` and `.xcresult`. Signed build passed (`/private/tmp/waglock-build31-device.log`). Build 31 installed successfully on the owner’s iPhone (`/private/tmp/waglock-build31-install.log`).

Device inventory confirms build 31. Automatic launch was declined because the phone was locked; the owner can open the installed app normally. No reconnect or launch retry is required for this UI-only follow-up.

Owner subsequently confirmed build 31 on the phone: “ok that worked.” The password-entry follow-up is accepted; D2S-127 can close. Independent alternative-vault work remains in D2S-115.
