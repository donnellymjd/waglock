import XCTest

final class PasswordKeyboardUITests: XCTestCase {
    @MainActor
    func testSwitchingKeyboardPreservesPasswordAndUnlocksExistingLibrary() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-autoLockTimeout", "-1"]
        app.launch()
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        // The unlock screen offers one link that switches to the other keyboard type.
        func use(_ keyboard: String) {
            let link = app.buttons["Use " + keyboard]
            if link.exists { link.tap() }
        }
        use("number pad")
        field.tap()
        field.typeText("593817")
        XCTAssertFalse(app.staticTexts["password.strength"].exists)
        use("full keyboard")
        XCTAssertTrue(app.keys["a"].waitForExistence(timeout: 5))
        app.buttons["password.visibility"].tap()
        let visible = app.textFields["Enter password"]
        XCTAssertEqual(visible.value as? String, "593817")
        visible.tap()
        visible.typeText("abc")
        use("number pad")
        XCTAssertEqual(visible.value as? String, "593817abc")
        use("full keyboard")
        visible.tap()
        visible.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9))
        visible.typeText("album-ui-test-password")
        app.buttons["password.visibility"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Password keyboard without login strength feedback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["password.unlock"].tap()
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15))
    }
}
