# Password collision access incident — D2S-178

Reported October26 against installed build62. [Urgent tracking issue](https://linear.app/d2sci/issue/D2S-178/prevent-main-vault-access-loss-after-secondary-password-collision). The incident hold was cleared after the owner accepted build63 on October26; D2S-178 is Done. The owner confirmed on October26 that the main library opens again after the guided secondary-password change to a distinct value. No reset or reinstall was required. The owner subsequently passed the build63 checklist covering both libraries and the approved collision-prevention flow.

## Cause and security constraints

A secondary password change can choose the primary password. Ordinary login then selects the secondary library. This is intentional routing from D2S-165, but the resulting primary-access trap was not adequately handled in the product. Removing primary Face ID leaves no obvious route to the main library.

The secondary change rewraps its own independent credential only; it does not overwrite the primary credential, either data key, either storage root or the existing biometric grant. The old main password still authenticates its original primary record, but ordinary login selects the matching secondary first. These are source and disposable-fixture observations, not an inspection of the owner's private library.

Do not fix this by checking proposed secondary passwords against the primary password: a different result would recreate the primary-password guessing oracle identified in the second security review. Do not prefer primary during a shared-password login: that could reveal the primary under duress. Do not reset, uninstall, migrate, remove credentials or add a normal login vault selector as incident recovery.

## Historical build62 recovery (completed before upgrading)

1. Unlock with the shared password. This currently opens the secondary library.
2. In Settings → Security & access → Change password, enter that shared password as the current password. Set and confirm a completely different new password, reserved for this library. Save it safely.
3. Lock the app. Enter the original main password. With the secondary password now distinct, normal login should select the main library again.
4. Verify an existing sample in the main library, then lock and verify the new secondary password opens the original secondary library.

This changes only the selected secondary wrapper and preserves both data keys. Face ID is not required. Do not repeat failed attempts in a cooldown, erase either library or send passwords/private content. A storage or credential-write error requires further investigation rather than reset.

## Regression evidence and remaining gate

The pre-fix regression `SecondaryVaultAuthenticationTests.testSecondaryPasswordCollisionNeverSelectsOrChangesThePrimaryVault` exercised two encrypted disposable samples: enable primary Face ID, change the secondary password to the primary password, confirm ordinary login stays secondary, confirm Face ID still targets primary, remove Face ID from primary, confirm ordinary login still selects secondary, change the secondary password to a distinct value, and verify both libraries' original data keys, storage roots, secondary identity and decrypted sample bytes survive.

The existing collision regression already checked moving the secondary password away restores primary routing. The expanded case covers the reported Face ID sequence and encrypted content preservation. All5 `SecondaryVaultAuthenticationTests` pass with0 failures in `/private/tmp/waglock-collision-recovery-final.xcresult`, including the expanded recovery regression. `git diff --check` passes. No production authentication behavior is changed by these regression tests.

Main-vault phone access recovery is owner-confirmed. The owner-approved primary-only management design below passed automated and physical validation in63; D2S-178 is Done. A generic instruction to use a unique password is insufficient evidence that recurrence has been prevented. Any proposed behavior must address accidental owner lockout, the secondary-password oracle and ordinary decoy-login confidentiality together.

## Owner-approved prevention — build63

On October26 the owner approved primary-only login-password management. Alternative sessions omit Change password and all alternative-management wording. Both authentication methods reject alternative-session password changes before any credential or attempt-budget reads. The obsolete secondary-authenticated rewrap service API is removed. Selected-vault password verification for backups and Face ID remains available and scoped; album passwords are unaffected.

The main security screen retains Change password and adds Change alternative password. The latter requires the current main password, current alternative password, and a new confirmed alternative password. Face ID is not sufficient. Both current credentials have independent durable settings attempt budgets, reserved before verification. Fresh verification of the main password authorizes comparing the new alternative password against its exact UTF-8 bytes; a transient extra verifier read cannot accidentally permit a match. Main-password changes authenticate the current main password before checking against the alternative credential. Both directions reject a collision.

Management is synchronous on the main actor, with the originating active primary session checked before the secondary operation. The form clears passwords and dismisses on background, logout or session replacement. Only the alternative credential wrapper is replaced; its source bytes and the primary source record are rechecked, and exact saved bytes are read back. No key changes, record deletion, rollback, biometric retargeting, file migration or reset occurs. An uncertain write reports failure without restoring stale credentials or deleting either key.

Existing collision login still selects the alternative library. There is no new login selector, primary bypass or automatic credential rewrite. The owner's build62 collision was resolved and main access confirmed before this update. Recovery instructions above describe build62; they must not be offered as a guest-session password-change feature in build63. A preexisting collision with no primary biometric access needs separate recovery planning before upgrade.

Verification and phone acceptance for build63 are recorded in [the candidate evidence](../release/evidence/build-63/README.md) when complete. The owner replied “Passed” to the build63 phone checklist on October26, clearing this incident hold. Other submission gates remain separate.
