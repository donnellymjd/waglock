import XCTest
@testable import WagLock

final class LocalizationCoverageTests: XCTestCase {
    func testBetaBundlesOnlyEnglish() {
        XCTAssertEqual(Set(Bundle.main.localizations).subtracting(["Base"]), ["en"])
    }

    func testEnglishCriticalFlowsAndPermissions() throws {
        let keys = ["setup.header.title", "login.unlock", "tab.photos", "tab.media", "tab.audio",
                    "tab.files", "tab.secretSpace", "tab.settings", "action.cancel", "action.confirm",
                    "filePreview.error.decrypt", "media.error.deleteFailed"]
        for key in keys {
            let text = Bundle.main.localizedString(forKey: key, value: "__MISSING__", table: "Localizable")
            XCTAssertNotEqual(text, "__MISSING__")
            XCTAssertNotEqual(text, key)
            XCTAssertFalse(text.isEmpty)
        }
        let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let permissionsPath = try XCTUnwrap(Bundle(path: path)?.path(forResource: "InfoPlist", ofType: "strings"))
        let data = try Data(contentsOf: URL(fileURLWithPath: permissionsPath))
        let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        XCTAssertNil(values["CFBundleDisplayName"], "Use the configuration-specific name for Dev and release builds")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                       Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "WagLock Dev")
        let notices = try XCTUnwrap(Bundle.main.url(forResource: "OpenSourceNotices", withExtension: "txt"))
        let noticeText = try String(contentsOf: notices, encoding: .utf8)
        XCTAssertTrue(noticeText.contains("GNU GENERAL PUBLIC LICENSE"))
        XCTAssertTrue(noticeText.contains("© 2025 ZeroNet Space"))
        for key in ["NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"] {
            XCTAssertFalse(try XCTUnwrap(values[key]).isEmpty)
        }
    }

    func testCrashExecutableHasLatinNameAndStableIdentity() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "WagLock")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.d2sci.vaultito.dev")
    }
}
