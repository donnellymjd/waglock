# WagLock UI implementation coverage — build 37

All 70 design states are mapped below to working application screens or their native iOS counterparts. This is a UI completion record, not a claim that planned storage, private notes, recovery, favorites or alternative vault functionality is implemented. Production screens show real media and operation state; prototype sample values and navigation-only example buttons are not shipped.

The approved native adaptations retain SF Pro, SF Symbols, actual navigation/tab bars, Forms, pickers, alerts, Face ID and share sheets. The shared app-owned palette, cards, fields, spacing and surfaces follow the Figma design in both appearances. Native navigation placement and system confirmation geometry intentionally differ from the review fallbacks. No Figma screenshot or temporary asset URL is used as app UI.

Photo Favorite is represented by the working Info destination rather than an inert Favorite button; favorites remain a separate gallery feature in D2S-112. Notes retain their current persistence and are not described as completed encrypted Markdown notes. Trash, two independent top-level vaults, portable recovery and shared consent are separate development priorities.

| Design state | Runtime implementation | Behavior / adaptation |
| --- | --- | --- |
| photos | PhotosView | Date-grouped live photos, search, selection/export and owner/guest empty states. |
| albums | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| videos | VideosView / VideoPlayerView | Search, aspect-fit thumbnails, native navigation, real playback/seek/rate/volume, export and deletion. |
| audio | AudioView / AudioPlaybackSheet | Live audio rows, inline playback and player sheet; recording controls retained. Hardware sound/recording acceptance is separate. |
| files | FilesView / MediaDetailView / FilePreviewView | Live file cards; PDFKit, text/Markdown and native QuickLook with actual format/error handling. |
| notes | SecretSpaceView / NoteEditorView | Pinned/regular note cards, actual editor/save flow, adaptive full-screen backgrounds. Does not imply encrypted Markdown-note implementation. |
| import | ImportButtonsView / EncryptedFilePasswordInputView | Live progress, original-file explanations, original-password entry and native completion/error alerts. Prototype example links are omitted. |
| settings | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| photo | PhotoDetailView | Real zoom/swipe viewer, immutable info sheet, export and delete. Info replaces the prototype Favorite action because persistent favorites are separate D2S-112 functionality. |
| albumContents | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| selection | PhotosView | Date-grouped live photos, search, selection/export and owner/guest empty states. |
| export | BatchExportView / ShareSheet | Selected IDs, live preparation and immediate native share sheet. No fake ready/example screen; actual export creates unencrypted copies. |
| videoPlayer | VideosView / VideoPlayerView | Owner override in build44: full-screen native AVKit controls on black, navigation-bar Done/Share and Info/Delete menu. Supersedes the stacked card design. |
| audioPlayer | AudioView / AudioPlaybackSheet | Live audio rows, inline playback and player sheet; recording controls retained. Hardware sound/recording acceptance is separate. |
| filePreview | FilesView / MediaDetailView / FilePreviewView | Live file cards; PDFKit, text/Markdown and native QuickLook with actual format/error handling. |
| editor | SecretSpaceView / NoteEditorView | Pinned/regular note cards, actual editor/save flow, adaptive full-screen backgrounds. Does not imply encrypted Markdown-note implementation. |
| appearance | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| appIcons | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| security | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| faceID | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| storage | SettingsView.storageScreen | Live storage values and cache action with native confirmation. Meter compares library bytes with library bytes plus available space, not a guessed device capacity. |
| about | AboutView / NetworkVerificationView / OpenSourceNoticesView | Source link, accurate local/iOS disclosures and original complete bundled license text. |
| offline | AboutView / NetworkVerificationView / OpenSourceNoticesView | Source link, accurate local/iOS disclosures and original complete bundled license text. |
| licenses | AboutView / NetworkVerificationView / OpenSourceNoticesView | Source link, accurate local/iOS disclosures and original complete bundled license text. |
| setup | LoginView / SetupPasswordView | Real credentials, keyboard selector, help/error handling, setup strength and no-reset warning. No strength score at routine login. |
| changePassword | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| guest | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| disguise | DisguiseSettingsView / CalculatorView | Numeric login policy, live calculator preview and themed keypad; no undetectability promise. |
| calculator | DisguiseSettingsView / CalculatorView | Numeric login policy, live calculator preview and themed keypad; no undetectability promise. |
| albumSetup | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| albumUnlock | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| moveAlbum | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| importProgress | ImportButtonsView / EncryptedFilePasswordInputView | Live progress, original-file explanations, original-password entry and native completion/error alerts. Prototype example links are omitted. |
| importComplete | ImportButtonsView / EncryptedFilePasswordInputView | Live progress, original-file explanations, original-password entry and native completion/error alerts. Prototype example links are omitted. |
| importFailed | ImportButtonsView / EncryptedFilePasswordInputView | Live progress, original-file explanations, original-password entry and native completion/error alerts. Prototype example links are omitted. |
| importEncrypted | ImportButtonsView / EncryptedFilePasswordInputView | Live progress, original-file explanations, original-password entry and native completion/error alerts. Prototype example links are omitted. |
| exportProgress | BatchExportView / ShareSheet | Selected IDs, live preparation and immediate native share sheet. No fake ready/example screen; actual export creates unencrypted copies. |
| exportReady | BatchExportView / ShareSheet | Selected IDs, live preparation and immediate native share sheet. No fake ready/example screen; actual export creates unencrypted copies. |
| empty | PhotosView | Date-grouped live photos, search, selection/export and owner/guest empty states. |
| searchEmpty | PhotosView | Date-grouped live photos, search, selection/export and owner/guest empty states. |
| autoLock | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| faceEnable | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| faceConsent | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| faceOnlyWarning | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| recoveryHelp | LoginView / SetupPasswordView | Real credentials, keyboard selector, help/error handling, setup strength and no-reset warning. No strength score at routine login. |
| passwordProgress | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| moveProgress | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| photoInfo | PhotoDetailView | Real zoom/swipe viewer, immutable info sheet, export and delete. Info replaces the prototype Favorite action because persistent favorites are separate D2S-112 functionality. |
| deleteConfirm | Native confirmation dialogs | Existing real deletion semantics; no encrypted Trash claim before D2S-140 ships. |
| clearCache | SettingsView.storageScreen | Live storage values and cache action with native confirmation. Meter compares library bytes with library bytes plus available space, not a guessed device capacity. |
| guestDisable | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| calculatorEnabled | DisguiseSettingsView / CalculatorView | Numeric login policy, live calculator preview and themed keypad; no undetectability promise. |
| iconConfirm | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| passwordComplete | SettingsView / BiometricSettingsView / GuestModeSetupView / ChangePasswordView | Functional security drilldowns, native choices/confirmations, original consent and password-strength rules retained. |
| shareSheet | BatchExportView / ShareSheet | Selected IDs, live preparation and immediate native share sheet. No fake ready/example screen; actual export creates unencrypted copies. |
| licenseText | AboutView / NetworkVerificationView / OpenSourceNoticesView | Source link, accurate local/iOS disclosures and original complete bundled license text. |
| sortOrder | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| albumActions | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| renameAlbum | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| albumDelete | AlbumBrowserView / AlbumConfigurationView / AlbumUnlockView | Nested albums, tiled contents, policy choices, device-bound acknowledgement, real verified moves and native confirmations. |
| guestLibrary | PhotosView | Date-grouped live photos, search, selection/export and owner/guest empty states. |
| unlockError | LoginView / SetupPasswordView | Real credentials, keyboard selector, help/error handling, setup strength and no-reset warning. No strength score at routine login. |
| unsupportedFile | FilesView / MediaDetailView / FilePreviewView | Live file cards; PDFKit, text/Markdown and native QuickLook with actual format/error handling. |
| loadingItem | LoadingOverlay / document and media loaders | Shared adaptive progress cards with real operation state and existing cancellation/retry behavior. |
| guestMedia | AudioView / AudioPlaybackSheet | Live audio rows, inline playback and player sheet; recording controls retained. Hardware sound/recording acceptance is separate. |
| guestFiles | FilesView / MediaDetailView / FilePreviewView | Live file cards; PDFKit, text/Markdown and native QuickLook with actual format/error handling. |
| guestNotes | SecretSpaceView / NoteEditorView | Pinned/regular note cards, actual editor/save flow, adaptive full-screen backgrounds. Does not imply encrypted Markdown-note implementation. |
| guestSettings | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| layout | SettingsView / AppIconSettingsView | Five settings destinations, persisted appearance, real grid/sort controls, eight icons and native OS icon feedback. |
| unlock | LoginView / SetupPasswordView | Real credentials, keyboard selector, help/error handling, setup strength and no-reset warning. No strength score at routine login. |

## Verification boundaries

Unit/security regressions and simulator workflows establish only the behavior recorded in the [implementation evidence](../../docs/portable-vault/figma-ui-implementation.md). Screenshots use disposable/generated media and are reviewed against the design, not shipped as assets. UI state coverage is broader than individual automated screenshots. Physical sound/recording, hardware Face ID, large libraries and the ongoing security/recovery findings retain their own acceptance requirements.
