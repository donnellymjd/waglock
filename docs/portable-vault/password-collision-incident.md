# Password collision access incident — D2S-178

Reported October26 against installed build62. [Urgent tracking issue](https://linear.app/d2sci/issue/D2S-178/prevent-main-vault-access-loss-after-secondary-password-collision). Submission is on hold for this incident. The owner confirmed on October26 that the main library opens again after the guided secondary-password change to a distinct value. No reset or reinstall was required. Secondary-content verification and preventing recurrence remain open.

## Cause and security constraints

A secondary password change can choose the primary password. Ordinary login then selects the secondary library. This is intentional routing from D2S-165, but the resulting primary-access trap was not adequately handled in the product. Removing primary Face ID leaves no obvious route to the main library.

The secondary change rewraps its own independent credential only; it does not overwrite the primary credential, either data key, either storage root or the existing biometric grant. The old main password still authenticates its original primary record, but ordinary login selects the matching secondary first. These are source and disposable-fixture observations, not an inspection of the owner's private library.

Do not fix this by checking proposed secondary passwords against the primary password: a different result would recreate the primary-password guessing oracle identified in the second security review. Do not prefer primary during a shared-password login: that could reveal the primary under duress. Do not reset, uninstall, migrate, remove credentials or add a normal login vault selector as incident recovery.

## Non-destructive recovery in the existing app

1. Unlock with the shared password. This currently opens the secondary library.
2. In Settings → Security & access → Change password, enter that shared password as the current password. Set and confirm a completely different new password, reserved for this library. Save it safely.
3. Lock the app. Enter the original main password. With the secondary password now distinct, normal login should select the main library again.
4. Verify an existing sample in the main library, then lock and verify the new secondary password opens the original secondary library.

This changes only the selected secondary wrapper and preserves both data keys. Face ID is not required. Do not repeat failed attempts in a cooldown, erase either library or send passwords/private content. A storage or credential-write error requires further investigation rather than reset.

## Regression evidence and remaining gate

`SecondaryVaultAuthenticationTests.testSecondaryPasswordCollisionNeverSelectsOrChangesThePrimaryVault` now exercises two encrypted disposable samples: enable primary Face ID, change the secondary password to the primary password, confirm ordinary login stays secondary, confirm Face ID still targets primary, remove Face ID from primary, confirm ordinary login still selects secondary, change the secondary password to a distinct value, and verify both libraries' original data keys, storage roots, secondary identity and decrypted sample bytes survive.

The existing collision regression already checked moving the secondary password away restores primary routing. The expanded case covers the reported Face ID sequence and encrypted content preservation. All5 `SecondaryVaultAuthenticationTests` pass with0 failures in `/private/tmp/waglock-collision-recovery-final.xcresult`, including the expanded recovery regression. `git diff --check` passes. No production authentication behavior is changed by these regression tests.

Main-vault phone access recovery is owner-confirmed. D2S-178 remains open until a reviewed collision/recoverability UX is chosen and validated. A generic instruction to use a unique password is insufficient evidence that recurrence has been prevented. Any proposed behavior must address accidental owner lockout, the secondary-password oracle and ordinary decoy-login confidentiality together.
