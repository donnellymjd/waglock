import XCTest

final class PasswordSetupUITests: XCTestCase {
    @MainActor
    func testNumericSetupHasNoRetiredCalculatorEntry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-autoLockTimeout", "-1"]
        app.launch()
        let first = app.secureTextFields["setup.password"]
        if first.waitForExistence(timeout: 10) {
            app.buttons["Number pad"].tap()
            first.tap()
            first.typeText("246810")
            XCTAssertTrue(app.staticTexts["password.strength"].exists)
            let confirmation = app.secureTextFields["setup.confirmPassword"]
            confirmation.tap()
            confirmation.typeText("246810")
            app.buttons["Full keyboard"].tap()
            let finish = app.buttons["Finish Setup"]
            if !finish.isHittable { app.swipeUp() }
            finish.tap()
        } else {
            guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("Build30 Fresh QA") == true else {
                throw XCTSkip("Numeric calculator fixture requires the disposable Build30 Fresh QA simulator.")
            }
            let login = app.secureTextFields["Enter password"]
            if login.waitForExistence(timeout: 5) {
                app.buttons["Full keyboard"].tap()
                login.tap()
                login.typeText("246810\n")
            }
        }
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        app.buttons["settings.security"].tap()
        XCTAssertFalse(app.buttons["Calculator Login Mode"].exists)
        XCTAssertFalse(app.switches["Enable Calculator Login Mode"].exists)
        app.terminate()
        app.launch()
        let password = app.secureTextFields["Enter password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        app.buttons["Full keyboard"].tap()
        password.tap()
        password.typeText("246810\n")
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
    }
}
