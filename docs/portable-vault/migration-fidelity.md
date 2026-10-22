# Private Photo Vault export fidelity — test preparation

Recorded 2026-10-17 for [D2S-108](https://linear.app/d2sci/issue/D2S-108) and D2S-113. **Status: fixtures and comparison tooling ready; actual source-app exports remain untested.** No source app or real library was opened, exported, modified or deleted. The initial installed-app/version query failed when the phone connection became unavailable. A metadata-only retry on 2026-10-18 succeeded: **Photo Vault**, bundle ID `com.enchantedcloud.photovault`, version **25.8**, bundle version **25.8.2**, installed on iOS **27.0.1**. This identifies the installed app; export menus, capabilities and fidelity remain untested.

## What public documentation establishes

The vendor's [tutorials](https://privatephotovault.com/tutorials/) describe export and computer WiFi Transfer, and warn that options vary by version/platform. Its [FAQ](https://privatephotovault.com/faq/) lists MOV/MP4 support. These pages do not establish original-byte, EXIF, album, Live Photo or timestamp preservation. Measure the installed version before recommending a migration route.

## Disposable fixtures and local verifier

[tools/migration_fidelity.py](../../tools/migration_fidelity.py) requires Python 3.9+ and no third-party packages. It generates four PNG files: landscape, portrait, square, nested/Unicode paths, duplicate basenames with different contents, and an identical-content duplicate in another album. It intentionally does not generate JPEG EXIF, HEIC, videos or Live Photo pairs; those matrix cells require additional disposable samples.

From the repository root, choose **new** output paths:

```sh
python3 tools/migration_fidelity.py fixtures \
  /private/tmp/vaultito-migration-fixtures-NEW \
  /private/tmp/vaultito-migration-baseline-NEW.json

# For an additional folder of known non-private originals, e.g. a short test video:
python3 tools/migration_fidelity.py scan /path/to/disposable-originals \
  /private/tmp/vaultito-video-baseline-NEW.json

# Run on the raw source-app export, before importing into Vaultito:
python3 tools/migration_fidelity.py compare \
  /private/tmp/vaultito-migration-baseline-NEW.json \
  /path/to/disposable-source-app-export \
  /private/tmp/vaultito-export-report-NEW.json
```

The verifier hashes files in bounded chunks, matches content across renames, retains duplicate multiplicity and reports exact filename/album-path matches, missing originals, changed contents at the same path and extra exports. It never deletes or edits source/export files. It refuses symlinks, reports inside the scanned tree and overwriting existing reports/baselines. Reports contain plaintext names/hashes, stay local, and should not be uploaded with private library data. Case/Unicode-normalization differences can appear as name/path changes while bytes still match.

An equal hash verifies the embedded bytes, including any embedded metadata, survived. It does not independently validate capture-date interpretation, video playback/audio, Live Photo pairing or album ordering. If bytes changed, separate metadata/media inspection is necessary to explain the difference. Filesystem timestamps are not EXIF capture dates.

Executed the fixture generator and self-comparison with four exact matches; macOS `sips` confirmed 320×180, 180×320 and 240×240 dimensions. Seven tool tests passed, covering preserved/flattened names, duplicate counts, truncation, symlinks and protection against overwriting inputs/baselines. This validates the verifier, not any source-app export. Local sample root: `/private/tmp/vaultito-migration-fixtures-01`; baseline/report: `/private/tmp/vaultito-migration-baseline-01.json`, `/private/tmp/vaultito-migration-self-check-01.json`.

## Hands-on export matrix

Use only disposable fixtures. Record source app name/version/build, iOS version, selected quality/export options and whether a feature requires payment. Do not buy/enable cloud service or delete source assets for this test.

| Path | Availability | Counts/bytes | Names/albums | EXIF/dates | Video/audio/Live Photo | Batch limits |
| --- | --- | --- | --- | --- | --- | --- |
| Export to Photos | Verify in installed app | Not measured | Not measured | Not measured | Not measured | Not measured |
| Share/Save to Files | Verify in installed app | Not measured | Not measured | Not measured | Not measured | Not measured |
| WiFi Transfer to computer | Publicly documented; verify installed version | Not measured | Not measured | Not measured | Not measured | Not measured |

1. Preserve a baseline outside the source app, and place copies of the dummy files in test albums there using an available import route. If import/transport already changes bytes, report the result as an end-to-end ingest/export measurement; do not attribute it solely to export.
2. Export a small test batch through each available path, keeping outputs separate. Record album hierarchy, duplicate-name behavior, selection limits and export options. Treat exports outside a vault as plaintext. Retain all originals and exports until verified.
3. Compare each raw export before touching Vaultito. Test a known short non-private video separately and check rotation, duration, audio and original container/codec. Add JPEG/EXIF, HEIC and Live Photo examples only when available; leave untested cells explicit.
4. Only after raw export validation, import copies into an unlocked Vaultito test vault via Files and verify a decrypted round-trip separately. The current main Photos/PHPicker image path recompresses JPEG, so a Photos→Vaultito result cannot prove original-byte preservation. The Files and album paths still need measured end-to-end validation.
5. Expand to batch limits and the later 1,000-asset migration gate after the small fixture matrix passes. No automatic source cleanup or live-library conversion is authorized by this preparation.

## Current intervention boundary

The agent cannot inspect a locked source app's export menus or run a real source-app export on the physical iPhone through the build tools. The next evidence requires the owner to make the source app available and perform a small dummy export, then supply its local folder path for read-only comparison. No private photos or passwords are required. Phone-only and desktop-assisted migration recommendations remain pending those results; encrypted storage adoption and live conversion remain separate decisions.
