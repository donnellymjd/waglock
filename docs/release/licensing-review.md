# App Store licensing review packet

D2S-106/118. Prepared October 22, 2026. **Open release gate; no clearance or distribution permission is asserted.** The owner selected a small first App Store submission with manual release, followed by later improvements.

## Commercial model clarification

GPLv3 permits charging for copies, including a compiled app, while conveying the covered work and matching Corresponding Source under its conditions. Keeping the source available under GPLv3 and charging for convenient compiled distribution is a permitted commercial model; neither a zero app price nor a lawyer's opinion is required by GPLv3. Source must match the distributed version and satisfy the applicable source-conveyance/build-information conditions; merely publishing some code is insufficient. Recipients retain GPL rights to modify and redistribute.

The upstream TRADEMARK.md App Store section was rechecked through the public GitHub contents API: it explicitly discusses publishing forks with a different app name/icon/bundle identifier and upstream attribution. This supports upstream intent to permit appropriately branded App Store forks. No separate permission to monetize is presumed necessary merely because a price is charged.

The remaining platform question concerns the exact Apple distribution/EULA/signing/content-protection terms and the recipients' GPL rights. Apple Developer Program License Agreement section 5.1 requires compatible licensing with the Program's signing/content-protection terms. This packet has not established a particular current incompatibility, and historical FSF disputes alone do not establish one for this release. Additional copyright permission would be a possible remedy only if a specific conflict is identified; it is not automatically required for every commercial fork. The project's request for legal review is a separate risk-management step, not a GPL condition.

References: [upstream GPLv3 sections 4–6 and 10–12](https://github.com/materialofair/zeroNet_Space/blob/main/LICENSE), [upstream App Store branding guidance](https://github.com/materialofair/zeroNet_Space/blob/main/TRADEMARK.md), [current Apple agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/).

## Inspected evidence

| Component | Evidence | Review consequence |
| --- | --- | --- |
| Inherited app | Root [LICENSE](../../LICENSE) contains GPL version 3; Git history attributes its introduction to upstream commit `450ce65`. [NOTICE](../../NOTICE.md) retains fork attribution. | Determine applicable license grant/version, copyright ownership, corresponding-source/install-information obligations and the proposed Apple distribution terms. |
| Upstream branding | [TRADEMARK.md](../../TRADEMARK.md), especially its English App Store section, requires distinct name/icon/ID and attribution. | App Store-specific branding guidance is not an explicit copyright-license exception. Review both obligations; do not infer clearance from upstream having published an app. |
| Added scrypt core | [Pinned source inventory](../../WagLock/Support/Scrypt/PROVENANCE.md), BSD-2-Clause copyright/conditions in source and bundled notices. | Preserve exact notices and verify final source/binary inventory. This component does not relicense the inherited app. |
| Apple SDK code/interfaces | CryptoKit, CommonCrypto, Security, SwiftData, SQLite and other Apple SDK frameworks. | Review distribution against the actual developer agreements and selected territories. |
| Cryptomator research | Only `spikes/cryptomator` has the research package lock; app target package-product lists are empty. | Do not bundle/link research output. No AGPL Cryptomator app dependency is selected. |
| Independent recovery tool | Official age CLI is independently obtained on the user's computer, not bundled into iOS. | Recovery helper/source distribution and upstream notices remain in the release-source inventory. |
| Artwork | [Current Blue Guardian and historical art provenance](../../design/branding/selected-icon-options/README.md). | Review default and all alternates; inspect compiled assets for any inherited marks. Source availability alone is not artwork/trademark clearance. |

The inspected root license/notice/branding files do not establish a signed App Store exception, dual-license grant or complete chain of rights. Commit authors are evidence for further investigation, not proof of exclusive copyright ownership. Preserve all notices and the full license; do not replace GPL text, remove attribution or relicense another contributor's code.

## Decision needed from qualified review

1. Identify all relevant rights holders and grants for the actual release contents. Is the proposed App Store/TestFlight distribution permissible under those grants and the current Apple agreements?
2. Specify the corresponding source, build/signing/install information, notices, EULA and any other conditions needed for that route. Does either a standard or custom Apple EULA impose incompatible restrictions? A custom EULA is not assumed to cure every distribution restriction.
3. If existing grants are insufficient, identify the precise additional permission/exception required and who can grant it. Preserve GPL rights for the source if using a separate store distribution permission; do not assume one maintainer controls every contribution.
4. If permission is unavailable, assess an independently implemented replacement or another lawful distribution route before expanding the inherited release. No rewrite or license change has been authorized merely by this packet.
5. Record the determination, covered revision/components, territories, reviewer/authority, supporting permissions and any expiry/conditions in this directory before clearing the gate.

The Linear [D2S-106 requirement](https://linear.app/d2sci/issue/D2S-106) explicitly says to obtain legal review before shipping. This packet fulfills engineering preparation, not that external review. No upstream author, lawyer or other person has been contacted.

## Primary reference context

- [Apple's custom EULA configuration](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/) explains that Apple applies a standard agreement unless a custom one is supplied. It does not itself grant rights to third-party source.
- [FSF historical App Store enforcement explanation](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement) documents concerns about additional restrictions. It is a 2010 account, not a current legal determination for this fork or Apple's 2026 terms.
- The actual [local GPLv3 text](../../LICENSE), especially source/object conveyance and downstream restrictions, is part of the review evidence. The current Apple agreements accepted by the account holder must also be reviewed; no agreement was accepted or changed during preparation.

## Unsent permission-request brief

WagLock is an independent modified fork of SealedPocket / ZeroNet Space intended for a free initial iOS App Store release. We will retain upstream attribution, GPL source and notices, publish exact corresponding source/build guidance, and use distinct WagLock names, icons and identifiers. We seek clarification of whether existing copyright permissions cover App Store/TestFlight distribution under Apple's current terms, or whether additional written permission is needed. Please identify the rights you control and any other contributors whose permission would also be necessary. We are not requesting permission to use upstream trademarks or claiming official endorsement.

This is preparation text for the owner/reviewer. It has not been sent, and a reply from one person would still require review of its scope and authority.
