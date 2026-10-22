import XCTest

final class MultilingualUITests: XCTestCase {
    @MainActor
    func testEnglishBetaOnChineseDeviceLanguage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-DemoModeEnabled", "NO",
            "-autoLockTimeout", "-1"
        ]
        app.launch()
        let password = "album-ui-test-password"
        if app.secureTextFields["setup.confirmPassword"].waitForExistence(timeout: 5) {
            app.secureTextFields["setup.password"].tap()
            app.secureTextFields["setup.password"].typeText(password)
            app.secureTextFields["setup.confirmPassword"].tap()
            app.secureTextFields["setup.confirmPassword"].typeText(password + "\n")
        } else if app.secureTextFields["Enter password"].exists {
            app.secureTextFields["Enter password"].tap()
            app.secureTextFields["Enter password"].typeText(password)
            app.buttons["password.unlock"].tap()
        }
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertFalse(app.buttons["Restore Purchases"].exists)
    }
}
