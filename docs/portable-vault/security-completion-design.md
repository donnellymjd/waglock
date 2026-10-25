# October25 security completion design

Owner authorizes finishing D2S-162/169/170/173 before UAT. Existing native formats/readers and age backup remain; no library reset or Cryptomator conversion.

## Ciphertext binding

Authenticate canonical owned filenames and SHA256 ciphertext digests inside encrypted index records. A versioned enrollment marker baselines pre-release files once without changing ciphertext; this cannot detect tampering predating enrollment. New file digests are collected from owned writes and committed with metadata/catalog changes. Storage checks buffered bytes and streamed consumed bytes against the authenticated digest before any plaintext publication, including share/backup paths. Unknown/mismatched paths fail closed. Registry lifetime is scoped/revoked; no unknown-file deletion.

## Whole-copy rollback and crash reconciliation

A device-only per-library anchor remembers the committed revision and authenticated encrypted-head digest. Before SQLite commit, write/fsync an authenticated ciphertext-only recovery delta and then atomically store a pending target stamp/journal hash in Keychain. On interrupted reopen: accept exactly the target, or replay the exact journal delta from exactly the previously committed state. Any older/different state, missing necessary journal, unavailable anchor or invalid journal fails closed without deleting source data. Finalize the anchor only after committed-state verification; clear only the matching owned journal. This prevents rollback after enrollment as long as the device-only anchor is intact; an attacker who can also restore/delete trusted Keychain state is outside that guarantee. Independent age extraction remains the recovery path, not automatic native rollback acceptance.

## Older password envelopes and timing

Preserve authenticated readers and data secrets. Upgrade legacy wrappers only after successful verification, checked source equality, atomic replacement and read-back; fail closed/preserve sources on errors. Album updates go through the session write gateway and preserve parent/biometric policy. Do not infer reset permission. Ensure optional secondary credential checks perform comparable modern KDF work when absent; measure successful/wrong/absent/present paths without a claim of exact constant time or forensic deniability.

## Verification and limits

Adversarial tests must cover swapped same-vault files, same-read stream mismatch/truncation with old destination preservation, nested backup/share, Keychain/journal/SQLite crash windows, old/full/same-revision rollback, unavailable/corrupt anchors and cross-vault isolation, authenticated legacy rewrap failure/restart and timing evidence. Full regression and actual encrypted release UI/package checks precede phone UAT. OS screenshots/external cameras and complete Swift/decoder memory erasure remain unsupported; they cannot be truthfully fixed through an invented guarantee.
