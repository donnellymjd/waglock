# Build47 actual release screenshots

Eight actual app screens: Photos, Media, Notes and a protected album, on iPhone16ProMax (1320×2868) and 13-inch iPadProM4 (2064×2752). Native simulator JPEG capture produces no alpha channel. Images are not resized, retouched or composited. All displayed content is public synthetic data. Each device manifest records hashes, actual release identity/version/build, dimensions and passing workflow status. Application source is frozen at candidate-1.0-build47.

The actual iPad full workflow also passes note/draft cold persistence, Photos/video imports and playback, backup filename clear/edit, native picker cancellation and nested password protection. Actual iOS26.5 release UI separately passes password changes/cold reopen and three in-process lock cycles. These are engineering checks, not final physical or App Store acceptance. No deferred sharing/Trash/alternative-vault feature is pictured.

To reproduce on a dedicated, publicly seeded Store QA device, install the explicit release configuration, seed only generated media, then run `python3 tools/capture_release_screenshots.py SIMULATOR_UDID /tmp/waglock-capture-new`. After full fixture preparation, `--screenshots-only` captures four listing screens. The utility refuses other simulator names and checks the installed public identity/encryption switch. It uses a separate derived-data directory per device. No owner app reset or private library access is performed.

Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) list accepted sizes; final App Store Connect validation still applies. No mockups, cloud-upload claim or approval announcement is included.
