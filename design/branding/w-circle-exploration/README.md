# Circle of Ws — color study

October 19, 2026. Requested exploration: keep the circular ombré spectrum and replace the Vs with Ws. This is a symbol study, not a confirmed rename or app integration.

See [comparison.png](comparison.png) for three arrangements: four broad Ws, six balanced Ws, and eight finer Ws. The palette follows the preceding V study, with rounded strokes, local gradients and an open center. Each W has two low points and a raised middle. The letter shape rotates inward around the ring.

The four-W option gives the letter the most space. Six Ws creates a fuller circular color progression. Eight Ws is the closest to the earlier dense ring, but its letter details may merge at small sizes. Actual-size 40, 60 and 120 px PNGs are in `previews/`. [Background studies](previews/backgrounds.png) show the six-W option on midnight, warm light and in one color.

`assets/` contains separate editable full-color symbol SVGs, one-color SVGs, square editable icon SVGs and opaque RGB 1024 × 1024 PNG icons. Exported icons have no baked outer corner mask or wording. Presentation previews use approximate rounded masks.

`build.cjs` is the editable procedural master. It uses sharp and @napi-rs/canvas from the bundled runtime, or from the directory set by `VAULTITO_DESIGN_MODULES`. Typography uses the existing Manrope files and SIL OFL license in [the earlier font directory](../identity-exploration/fonts/OFL.txt). No new third-party artwork or image-generation model was used; these are AI-assisted procedural vector drawings.

The earlier [resemblance review](../identity-exploration/RESEMBLANCE-REVIEW-2026-10-19.md) identified close radial-chevron marks. Replacing Vs with Ws changes the letter silhouette, but does not by itself establish freedom to use the resulting composition. These W studies have not received a new resemblance or trademark screen. Existing app artwork and the earlier concepts are preserved.
