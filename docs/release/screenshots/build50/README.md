# Build50 actual release screenshots

Eight unedited native JPEGs from WagLock1.0(50), com.d2sci.waglock, with fresh encrypted storage: Photos, Media, Notes with Resume draft, and a protected album. iPhone16ProMax:1320x2868; 13-inch iPadProM4:2064x2752. Every image has no alpha, verified dimensions and a SHA-256 recorded in its device capture.json. No image was resized, retouched or composited. Only generated public fixtures are visible.

Both actual-release screenshot workflows pass: `/private/tmp/waglock-build50-store-iphone/Workflow.xcresult` and `/private/tmp/waglock-build50-store-ipad/Workflow.xcresult`. Application source matches candidate-1.0-build50. The owner separately confirms all final phone checks, including independent Mac backup recovery, passed October23. Earlier build47 images remain historical. These captures do not establish distribution signing, export classification or App Store approval.

[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) remain subject to final App Store Connect validation. Use these current files for submission. Reproduce with tools/capture_release_screenshots.py on an isolated Store QA simulator, using the explicit signed release configuration and public fixtures only.
