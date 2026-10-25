# D2S-175 — opt-in AutoFill build59 preparation

October25,2026. Owner authorizes the dedicated WagLock password-manager association. **Not activated for release, not installed on the phone, not uploaded/submitted.** Default AppStore configuration and installed58 stay unchanged. [Hosting/activation and device check](../../../../hosting/autofill/README.md).

Prepared `waglock.d2sci.co` association allowlists only the actual signed release App ID `Z3B45KM866.com.d2sci.waglock`. The new opt-in `config/PasswordAutoFill.xcconfig` includes existing AppStore settings and adds only the webcredentials entitlement. No Dev/wildcard association, new app identity, Keychain access group, credential, encryption or storage change.

The previous development profile lacked the capability. Xcode provisioning updates for the existing requested App ID succeeded: signed build59 now uses an explicit matching profile permitting Associated Domains. `tools/check_autofill_association.py --app ...` verifies the exact signed domain/App ID, code signature and profile, not just source configuration. Signed archive `/private/tmp/WagLock-1.0-build59-autofill.xcarchive`; local signed/package receipts are checked in here. This does not clear distribution/export/account gates.

Unsigned and ad-hoc signed Release simulator builds pass. The actual separately installed Release password-change/persistence UI passes at `/private/tmp/waglock-autofill-release-ui.xcresult`. Existing-password vs new-password hints are consistent for main password changes, album setup and password/export backup fields; login's existing `.password` hint remains. Shared UIKit updates preserve the chosen content type without changing text filtering/encoding/submit policy. No new crypto test or independent audit claim is made for this UI/configuration change;334 unit/security passes belong to58.

Local verifier checks pass; manual disposable verifier checks reject wildcard App ID, Dev App ID, duplicate JSON keys, oversized JSON, redirected HTTP endpoint and wrong MIME type, while allowing the exact public contract. The local HTTP fixture is synthetic; it is not deployment/Apple CDN/provider evidence.

Live hosting check fails because the custom domain has no DNS record. Public existing company hosting identifies Firebase project `d2sci-website`; nameservers are Google's ns-cloud-a*. `gcloud` lists the intended active account but refreshing credentials fails with reauthentication required. No token or credential was printed or committed. Owner has been asked to sign in. No company hosting deployment, DNS change or account switch has been performed.

After reauthentication: inspect project/site/custom-domain/DNS access; deploy to a dedicated site/target, configure only required new hostname records, wait for HTTPS, verify origin/no redirects/JSON/exact association, then install the signed preview and test actual provider suggestions with disposable single/two-vault credentials. Apple's CDN/cache and third-party suggestions require real device confirmation. Providers may show both saved vault credentials; the app cannot suppress or rename provider-owned entries. Preserve this caveat and neutral secondary UI.


## October25 deployment follow-up

Owner completed Google reauthentication and confirmed Squarespace Domains manages DNS. Firebase list confirmed only the company default site existed. Created separate `d2sci-waglock` and deployed the two reviewed static files; receipts record the content hashes/version/release. The dedicated HTTPS association endpoint passes exact JSON, MIME and no-redirect checks. The default company site was not deployed or replaced. `.firebaserc` now maps only the verified dedicated target.

The exact custom hostname is registered on the new site, pending DNS/SSL. Firebase requested one CNAME and one certificate TXT record (see custom-domain-pending.json and hosting README). The owner has been asked to add them in Squarespace; no Squarespace authenticated access is available here. Build59 remains signed/prepared but not installed. Installed58 remains unchanged. Next: DNS/certificate/custom-origin checks, Apple delivery check, install and real provider UAT. The original Google-auth blocker above is historical and resolved.
