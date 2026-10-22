# Vaultito — circular rainbow V exploration

Prepared October 18, 2026. First presentation, revised to the owner's request for “a circular ombre rainbow of Vs.” These are three treatments of that requested idea, rather than the unrelated identity directions originally contemplated by the brief. No direction has been selected or installed in the app.

Open [index.html](index.html) for the presentation. [comparison.png](comparison.png) is the quick overview. Individual assets remain separate and editable.

**October 19 review update:** a close pre-existing rainbow chevron ring was found at Vivid Photo Visual, with a second relevant inward-arrow ring at ConvergeHub. The current family is not cleared for release; revise or obtain a qualified review before publication. Read the [dated resemblance review](RESEMBLANCE-REVIEW-2026-10-19.md). This supersedes the release implications of the original design recommendation below.

## Design recommendation

**01 / Open Circle:** six inward-facing, round-ended Vs around an open center. Broad strokes and generous gaps keep the letters readable at 40 pixels. This is the recommended starting point for the primary icon.

**02 / Prism:** eight Vs form a fuller spectrum with a more circular perimeter. This is the closest expression of a rainbow wreath; it trades some individual-letter recognition for a richer overall texture.

**03 / Orbit:** twelve narrower Vs, slightly rotated, form a fine halo. It feels more expressive at large sizes, but the Vs read as texture sooner at 40 pixels. It could support a decorative alternate rather than lead the identity.

**04 / Chalk:** the six-V symbol in ink on warm gray. This is a monochrome alternate candidate. Alternate icons affect appearance only; they do not hide the app, its name or vault existence.

Each V carries a local gradient from the neighboring spectrum colors. These gradients follow the local left-to-right direction before rotation; they do not rely on opacity, overlapping petals, a continuous ribbon or a raster texture. The single-color tests preserve the complete geometry.

## Typography and usage studies

The wordmark uses **Manrope**, weight 650. Supporting copy uses weight 400. The wordmark is typeset rather than custom lettering; it is a provisional typography direction. Font copyright: 2018 The Manrope Project Authors. The font is distributed under the **SIL Open Font License 1.1**, included in [fonts/OFL.txt](fonts/OFL.txt). Fonts may be used and bundled under that license; retain its notice and terms. Static 400 and 650 font files were instantiated from the supplied variable font without drawing changes. Source: [Google Fonts Manrope directory](https://github.com/google/fonts/tree/main/ofl/manrope).

Outlined logo SVGs need no installed font. The editable-text lockups use the family aliases `Manrope` and `ManropeSemibold`; install/use the included font or substitute the Manrope variable font at weight 650 in an editor. `build.cjs` defines all mark geometry, spacing, color stops and export composition. No proprietary design application is required.

Provisional minimums: icon 40 px; standalone six-V symbol 32 px; horizontal lockup 160 px wide. Only 40/60/120 px icon rendering has been visually inspected; these are design starting points, not device-readability guarantees. Keep external logo clear space of at least one V stroke (about 6.25% of the 1024-unit symbol canvas) beyond the visible mark. The symbol's built-in margins also provide comfortable separation from the wordmark. Keep the tagline outside the app icon; omit it where it would render below 14 px. Use the single-color dark symbol on light backgrounds and the reversed symbol on dark backgrounds when color is unsuitable. Do not stretch or add shadows/outlines.

## Color values

| Role | HEX | RGB |
| --- | --- | --- |
| Midnight / main background | #241E32 | 36, 30, 50 |
| Cream / presentation | #FAF7F2 | 250, 247, 242 |
| Chalk / alternate background | #EDE9E3 | 237, 233, 227 |
| Coral | #FF797E | 255, 121, 126 |
| Apricot | #FFB56B | 255, 181, 107 |
| Golden | #E5D579 | 229, 213, 121 |
| Mint | #8FD4A2 | 143, 212, 162 |
| Sky | #69C8DC | 105, 200, 220 |
| Periwinkle | #8B9DEB | 139, 157, 235 |
| Lilac | #BC8CE1 | 188, 140, 225 |
| Rose | #EC88B7 | 236, 136, 183 |

The rainbow has strong visual presence against Midnight. The light-background full-color lockup is an appearance study: pale yellow and mint lose contrast there. Prefer the one-color ink version for small light-background marks.

## Preliminary resemblance review

The broad territory is crowded: a rainbow arranged radially can evoke [Apple Photos](https://www.apple.com/id/privacy/docs/Photos_Tech_Brief_Sept_2019.pdf) and [Google Photos](https://partnermarketinghub.withgoogle.com/brands/google-photos/visual-identity/icon/). This is the main visual association to assess before selecting a direction. These proposals use separate inward-pointing chevrons, an open center, no petal overlap and a dark primary tile to distinguish their structure. The eight-V option still has particularly strong rainbow-gallery associations. That is a design assessment, not an opinion on legal confusion.

The exploratory search also considered [Vivaldi's V icon](https://vivaldi.com/press/), [Keepsafe](https://www.getkeepsafe.com/products/), [Private Photo Vault](https://privatephotovault.com/) and [Vanguard](https://investor.vanguard.com/corporate-portal). Their public sites and search results supplied reference context; this was not an exhaustive visual comparison of every current alternate icon or a trademark registry search. No existing mark was copied or traced. Abstract chevrons and circular rainbow logos are common, so originality of this particular drawing does not establish exclusive rights or clearance.

## Export inventory

For each prefix `01-open-circle`, `02-prism`, and `03-orbit`:

- `assets/{prefix}-symbol.svg`: transparent full-color editable vector, 1024-unit canvas; suitable as a candidate login/launch symbol.
- `assets/{prefix}-symbol-one-color.svg`: transparent ink vector.
- `assets/{prefix}-symbol-reversed.svg`: transparent cream vector.
- `assets/{prefix}-wordmark.svg`: standalone outlined Vaultito lettering.
- `assets/{prefix}-lockup-editable-text.svg`: horizontal lockup with editable text.
- `assets/{prefix}-lockup-outlined.svg`: horizontal lockup with outlined lettering.
- `assets/{prefix}-icon-1024.svg`: editable square icon source.
- `assets/{prefix}-icon-1024.png`: clean square, opaque 1024 × 1024 icon candidate; no baked outer corner mask or text.
- `previews/{prefix}-40px.png`, `-60px.png`, `-120px.png`: unmasked square PNGs at actual pixel sizes.
- `previews/{prefix}-sheet.svg` and `.png`: light/dark logos, tagline application, icon and monochrome studies.

Additional files:

- `assets/04-chalk-icon-1024.svg` and `.png`: monochrome alternate candidate.
- `comparison.svg` and `.png`: three treatments together, including preview masks and actual-size tests.
- `previews/home-screen.svg` and `.png`: stylized light/dark Home Screen context with original generic neighboring icons. These are illustrative layouts with approximate masks, not physical-device screenshots.
- `index.html`: local, self-contained presentation using relative asset links; no external requests or analytics.
- `build.cjs`: procedural vector master and repeatable export script, using `sharp` and `@napi-rs/canvas`. Set `VAULTITO_DESIGN_MODULES` to a Node modules directory containing those packages if using another machine.
- `fonts/`: variable font, static instances and license.

All SVGs are editable sources. PNGs are sRGB screen assets. The icon candidates are fully opaque RGB exports. Rounded corners appear only in the presentation previews.

## Authorship, rights and completion stage

AI use: Codex assisted in original procedural vector design, code, typography selection, rendering and writing. No image-generation model, stock artwork, upstream logo or third-party icon artwork was used in the deliverables. Third-party material is limited to the disclosed font; rendering libraries are build tools rather than embedded artwork. Do not describe this work as human-only, trademark-cleared or evidence of certification. The owner may use, modify and distribute the delivered drawings and source; no additional restriction is imposed by these design files. This statement is not a guarantee of copyright protection for AI-assisted output. Keep the font's OFL notices and the app's existing software attribution/license obligations.

The final selected-direction package remains a later stage of the brief: refine the chosen geometry and wordmark, select three meaningful alternates as a family, export the approved PDF/logo variants, complete final device appearance checks and resolve the originality review. This exploration does not approve or integrate any of the four icon candidates into the current app pipeline.
