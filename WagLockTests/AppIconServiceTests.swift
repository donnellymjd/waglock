import XCTest
import UIKit

@testable import WagLock

@MainActor
final class AppIconServiceTests: XCTestCase {
    func testEveryIconCanBeSelectedWithoutEntitlements() async throws {
        let app = IconApplicationMock()
        let service = AppIconService(application: app)
        for icon in AppIconOption.allCases where icon != .primary {
            try await service.select(icon)
            XCTAssertEqual(service.selectedIconName, icon.iconName)
        }
        XCTAssertEqual(app.changeCount, AppIconOption.allCases.count - 1)
    }

    func testCanChangeAndRestoreDefault() async throws {
        let app = IconApplicationMock()
        let service = AppIconService(application: app)
        try await service.select(.calculator)
        XCTAssertEqual(service.selectedIconName, "AppIcon-Calculator")
        try await service.select(.primary)
        XCTAssertNil(service.selectedIconName)
        XCTAssertEqual(app.changeCount, 2)
    }

    func testAlreadySelectedIconDoesNotCallSystemAgain() async throws {
        let app = IconApplicationMock()
        app.alternateIconName = "AppIcon-Paper"
        let service = AppIconService(application: app)
        try await service.select(.paper)
        XCTAssertEqual(app.changeCount, 0)
    }

    func testPreviousCaughtYouLookingSelectionRemainsAnAlternate() async throws {
        let app = IconApplicationMock()
        app.alternateIconName = "AppIcon-CaughtYouLooking"
        let service = AppIconService(application: app)
        XCTAssertEqual(service.selectedIconName, "AppIcon-CaughtYouLooking")
        service.refresh()
        XCTAssertEqual(service.selectedIconName, "AppIcon-CaughtYouLooking")
        XCTAssertEqual(app.changeCount, 0)

        try await service.select(.spectrum)
        XCTAssertEqual(service.selectedIconName, "AppIcon-Spectrum")
        try await service.select(.primary)
        XCTAssertNil(app.alternateIconName)
        XCTAssertNil(service.selectedIconName)
    }

    func testFailureKeepsSystemSelectionAndAllowsRetry() async throws {
        let app = IconApplicationMock()
        app.alternateIconName = "AppIcon-Paper"
        app.shouldFail = true
        let service = AppIconService(application: app)
        do {
            try await service.select(.pebble)
            XCTFail("The system error should propagate")
        } catch IconApplicationMock.Failure.rejected {}
        XCTAssertEqual(service.selectedIconName, "AppIcon-Paper")
        XCTAssertFalse(service.isChanging)
        app.shouldFail = false
        try await service.select(.pebble)
        XCTAssertEqual(service.selectedIconName, "AppIcon-Pebble")
    }

    func testUnsupportedDeviceDoesNotCallSystem() async throws {
        let app = IconApplicationMock()
        app.supportsAlternateIcons = false
        let service = AppIconService(application: app)
        do {
            try await service.select(.paper)
            XCTFail("Unsupported devices must be rejected")
        } catch AppIconService.IconError.unsupported {}
        XCTAssertEqual(app.changeCount, 0)
    }

    func testConcurrentSelectionCannotStartSecondSystemRequest() async throws {
        let app = IconApplicationMock()
        app.holdChange = true
        let service = AppIconService(application: app)
        let first = Task { try await service.select(.paper) }
        for _ in 0..<100 where app.pending == nil { await Task.yield() }
        XCTAssertTrue(service.isChanging)
        try await service.select(.calculator)
        XCTAssertEqual(app.changeCount, 1)
        app.pending?.resume()
        try await first.value
        XCTAssertEqual(service.selectedIconName, "AppIcon-Paper")
        XCTAssertFalse(service.isChanging)
    }

    func testAllIconsAndPreviewsAreBundledForCurrentDevice() throws {
        let key = UIDevice.current.userInterfaceIdiom == .pad ? "CFBundleIcons~ipad" : "CFBundleIcons"
        do {
            let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? [String: Any])
            let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
            for option in AppIconOption.allCases {
                XCTAssertNotNil(UIImage(named: option.previewAsset), option.previewAsset)
                if let name = option.iconName {
                    XCTAssertNotNil(alternates[name], "Missing \(name) in \(key)")
                }
            }
        }
    }
}

@MainActor
private final class IconApplicationMock: AppIconApplication {
    enum Failure: Error { case rejected }
    var alternateIconName: String?
    var supportsAlternateIcons = true
    var shouldFail = false
    var holdChange = false
    var pending: CheckedContinuation<Void, Never>?
    var changeCount = 0

    func changeIcon(to name: String?) async throws {
        changeCount += 1
        if holdChange {
            await withCheckedContinuation { pending = $0 }
        }
        if shouldFail { throw Failure.rejected }
        alternateIconName = name
    }
}
