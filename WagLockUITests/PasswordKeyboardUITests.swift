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
        app.buttons["Number pad"].tap()
        field.tap()
        field.typeText("593817")
        XCTAssertFalse(app.staticTexts["password.strength"].exists)
        app.buttons["Full keyboard"].tap()
        XCTAssertTrue(app.keys["a"].waitForExistence(timeout: 5))
        app.buttons["password.visibility"].tap()
        let visible = app.textFields["Enter password"]
        XCTAssertEqual(visible.value as? String, "593817")
        visible.tap()
        visible.typeText("abc")
        app.buttons["Number pad"].tap()
        XCTAssertEqual(visible.value as? String, "593817abc")
        app.buttons["Full keyboard"].tap()
        visible.tap()
        visible.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9))
        visible.typeText("album-ui-test-password")
        app.buttons["password.visibility"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Password keyboard without login strength feedback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["password.unlock"].tap()
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
    }
}
