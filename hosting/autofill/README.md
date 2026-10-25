# Dedicated WagLock AutoFill site

Tracked as D2S-175. Prepared October25,2026; **not deployed**. This directory is separate from the company's existing Firebase site. Verified public existing project: `d2sci-website`; Google reauthentication is required before inspecting or changing hosting/DNS resources. Never deploy to that project's default/company site.

The proposed custom domain is `waglock.d2sci.co`. The only credential association is `Z3B45KM866.com.d2sci.waglock`, verified from the actual signed release app. No Dev app, wildcard App ID, universal links, credential form, analytics SDK or vault endpoint is included. `public/.well-known/apple-app-site-association` must be deployed; do not add Firebase's usual `**/.*` ignore rule, which would exclude it.

## Hosting activation

1. Reauthenticate the existing Google/Firebase account. Inspect sites/custom domains and DNS ownership first. Reuse a suitable dedicated WagLock site or create a separate site; do not replace `d2sci-website` company content.
2. Bind this isolated local target to that verified site using Firebase CLI: `firebase target:apply hosting waglock-autofill SITE_ID --project d2sci-website`. This updates `.firebaserc` only with the verified mapping. Do not invent or guess an existing site ID.
3. From this directory deploy only this target: `firebase deploy --only hosting:waglock-autofill --project d2sci-website`. Use an authenticated current Firebase CLI; no tokens/passwords in shell arguments or checked-in files.
4. Add `waglock.d2sci.co` as a custom domain on that dedicated site. Obtain the required DNS records from Firebase's domain wizard/API and change only those records in the authoritative DNS provider. Retain existing company/mail records. Wait for certificate issuance; do not guess address records or use a redirect from the association URL.
5. Verify from the repository root: `python3 tools/check_autofill_association.py --online`. Requires valid HTTPS, HTTP200 with no redirects, JSON content type and the exact production-only association. Apple's CDN can cache previous failures; live-origin success does not prove device delivery.

Before activation, `config/PasswordAutoFill.xcconfig` remains opt-in. The normal AppStore configuration and installed build58 do not gain this domain automatically. A development-signed opt-in build59 has been prepared with the explicit App ID capability/profile and actual signed entitlement verified; no App Store upload/submission. After hosting and device checks, make the accepted association part of the release configuration and update release/privacy status.

## App build and verification

```sh
xcodebuild archive -project WagLock.xcodeproj -scheme WagLock \
  -configuration Release -xcconfig config/PasswordAutoFill.xcconfig \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/WagLock-AutoFill.xcarchive
python3 tools/check_autofill_association.py --online \
  --app /private/tmp/WagLock-AutoFill.xcarchive/Products/Applications/WagLock.app
```

Run these from the repository root. The actual app must have the exact association, verified code signature and an explicit provisioned WagLock App ID permitting Associated Domains. Never change bundle ID, Keychain namespace, access groups, credentials or vault storage to enable AutoFill. No password-manager credentials are needed by the verifier.

## Password-manager device check

Enable the selected provider in iOS Settings → General → AutoFill & Passwords. With disposable credentials, save `https://waglock.d2sci.co` as the entry's website. After installing the signed associated build and allowing Apple to retrieve the file, focus WagLock's password field (try Full keyboard), select the provider's suggestion and verify it opens the expected library. Verify cancellation, wrong password, visibility/keyboard switching and background locking. New/change fields should offer generation where supported; existing-password fields should offer selection. Test backup and album credentials independently and retain exact Unicode/whitespace/special characters.

Use two disposable vault entries to observe suggestions. Both may be offered for the same app domain; the app cannot hide, rename, delete or separate a provider's saved entries. Nothing should label a secondary vault automatically. Document actual provider/iOS observations, not a guarantee of invisible decoy use. No real passwords, screenshots of credentials or provider database should be committed or sent to chat.

References: [Apple associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains), [AutoFill workflow](https://developer.apple.com/documentation/security/about-the-password-autofill-workflow), [Firebase multiple sites](https://firebase.google.com/docs/hosting/multisites), [custom domain](https://firebase.google.com/docs/hosting/custom-domain), [1Password AutoFill security](https://support.1password.com/ios-autofill-security/).
