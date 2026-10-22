import XCTest

final class WagLockSmokeUITests: XCTestCase {
    @MainActor
    func testFreshInstallShowsWagLockAndDevelopmentLimitations() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["WagLock"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["We Always Guard"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts[
            "Early test build. Use sample media only. Portable recovery and security hardening are still in development."
        ].waitForExistence(timeout: 10))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "WagLock fresh-install setup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
