# Forgotten password and deliberate erasure — D2S-176

Owner authorized the1.0 help-and-start-over recommendation on October25,2026. This does not authorize automatically erasing the owner's installed library. Native recovery keys remain future security design; no Cryptomator/storage conversion, password bypass or in-app backup restore is introduced.

## Product behavior

The locked screen's **Can't unlock?** sheet offers saved-password/Face ID help and a link to desktop age backup recovery. The vault unlock password may differ from backup/album credentials; independent recovery needs the appropriate credentials. Face ID may help only if already enabled/available. No server can recover a password.

The public encrypted release also offers **Erase WagLock and start over**. The confirmation names all local vault content and saved unlock access, explains irreversibility and exported-backup/original preservation, and requires both acknowledgement and typing exactly ERASE. Background/disappearance clears confirmation. A forgotten password is not required to erase; device access and deliberate confirmation authorize destruction, not decryption. Wording never identifies a secondary vault. The legacy Dev identity has no reset action from this flow.

## Scope and trust

The live factory is restricted to encrypted com.d2sci.waglock. It removes the known primary/secondary metadata roots (including unpublished creation), encrypted media roots and owned temporary preview/import/share/audio/backup staging. It does not erase the whole Documents/Application Support tree, Photos originals, Files/cloud exports, password-manager entries, another app's data or upstream credentials. Ordinary filesystem deletion and device-only credential removal are logical erasure, not forensic or cloud-copy erasure guarantees.

Keychain services are selected with an exact grammar: root namespace, its biometrics/album-attempt services, and UUID-scoped vault identity/album-biometric/attempt services. Unknown services, Dev and foreign namespaces remain untouched. Services are discovered by attributes rather than decoding a forgotten/corrupt credential or reading protected secrets. No broad SecItemDelete query is used. Each delete and the remaining scoped-service inventory are checked. The erase-intent service is distinct and excluded from deletion.

## Interruption protocol

A versioned, canonical, bounded Keychain intent stores a nonce and the exact validated service set. Only checked explicit intent persistence/read-back authorizes deletion; preferences, missing credentials, mount errors or a corrupt/unavailable intent never do. Login, Face ID and new setup are blocked whenever this state needs completion or cannot be checked.

On confirmation, revoke authentication/session/model/preview capabilities before destructive work. Remove only the fixed app-owned roots on a background task, refusing symlink roots/ancestors. Descendant links themselves are deleted without traversing external targets. Then remove the planned scoped Keychain services, check no owned service remains, clear this app's preferences and prepare its empty media directory for fresh mounting. The existing shared storage handle otherwise outlives deletion; creating only its empty media directory prevents a new library from failing before first import. Do not create an empty metadata root, which would violate fresh-library publication.

The intent is removed and checked absent last, immediately before publishing new setup. Any file/Keychain/preferences/intent error leaves the app locked with Retry. Startup resumes a previously confirmed valid intent; a retry with checked absence does no deletion and returns to ordinary authentication. Interrupted partial deletion cannot pair remaining old credentials/rollback anchors with a new empty store. Source data is not promised recoverable once confirmed erasure begins; this is deliberately destructive and cannot be cancelled after confirmation.

No reset launch argument, development shortcut, wildcard namespace delete, automatic erase on wrong passwords, or automatic existing-library migration is included. The path validator is a pure nonisolated filesystem check so large deletion can run off the UI actor; its symlink rules are unchanged.

## Validation plan

Use generated/disposable data only: no-intent/cancel preservation; unavailable/unwritten/corrupt/foreign/uncertain intent; interruption at every stage and reopening; Keychain/preferences/final-marker failures; real scoped Keychain deletion; symlink root refusal and external target preservation; pending-state auth/setup gating. Actual release UI must create content in both libraries, cancel/clear typed confirmation on background, verify both still open, explicitly erase, create/reopen a new library, reject old passcodes and preserve an actual exported age sample outside vault roots. Destructive UI execution is guarded by a dedicated reset-simulator name. Installing this build on the owner's phone must not execute erasure; the owner chooses that in the UI.

## Unit and package verification — October25

Full342 unit/security tests passed (214 XCTest and128 Swift Testing) in `/private/tmp/waglock-build60-security-final.xcresult`, including8 reset cases covering interruption, corrupt/unavailable intent, deletion failures, scoped real Keychain operations, symlink refusal and authentication gating. An initial compile failure from actor isolation on the pure path validator was corrected with a nonisolated annotation. Final signed1.0(60) archive and live HTTPS/signed-app AutoFill checks pass; distribution and physical acceptance remain separate gates. Actual release destructive UI verification is recorded in [build60 evidence](../release/evidence/build-60/README.md).
