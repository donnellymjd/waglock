import XCTest

final class AppIconUITests: XCTestCase {
    @MainActor
    func testIconGalleryAllowsSelectionWithoutPurchase() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
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
        app.buttons["settings.appIcon"].tap()
        func revealIcon(_ name: String) -> XCUIElement {
            let button = app.buttons["appicon.\(name)"]
            for _ in 0..<6 {
                if button.exists && button.isHittable { break }
                if name == "primary" { app.swipeDown() } else { app.swipeUp() }
            }
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable)
            return button
        }
        for name in ["primary", "caughtYouLooking", "spectrum", "watchfulHusky", "paper", "calculator", "pebble", "ruler"] {
            _ = revealIcon(name)
        }
        _ = revealIcon("primary")
        XCTAssertEqual(app.buttons["appicon.primary"].label, "WagLock")
        XCTAssertFalse(app.staticTexts["Loop"].exists)
        XCTAssertTrue(app.buttons["appicon.caughtYouLooking"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "App icon gallery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.staticTexts["VIP"].exists)
        XCTAssertFalse(app.buttons["Unlock VIP"].exists)
        XCTAssertFalse(app.buttons["Restore Purchases"].exists)
        func confirmIconChange() {
            let confirmation = app.buttons["OK"].firstMatch
            if confirmation.waitForExistence(timeout: 5) { confirmation.tap() }
        }
        // Restore a predictable selection if a previous test changed the system icon.
        if app.buttons["appicon.primary"].value as? String != "In use" {
            app.buttons["appicon.primary"].tap()
            confirmIconChange()
        }
        app.buttons["appicon.paper"].tap()
        confirmIconChange()
        let selected = NSPredicate(format: "value == %@", "In use")
        expectation(for: selected, evaluatedWith: app.buttons["appicon.paper"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.alerts["App icons · VIP"].exists)
        for name in ["caughtYouLooking", "spectrum", "watchfulHusky"] {
            let button = revealIcon(name)
            button.tap()
            confirmIconChange()
            expectation(for: selected, evaluatedWith: button)
            waitForExpectations(timeout: 10)
        }
        let newOptions = XCTAttachment(screenshot: app.screenshot())
        newOptions.name = "New W Spectrum and dog icon options"
        newOptions.lifetime = .keepAlways
        add(newOptions)
        _ = revealIcon("primary")
        app.buttons["appicon.primary"].tap()
        confirmIconChange()
        expectation(for: selected, evaluatedWith: app.buttons["appicon.primary"])
        waitForExpectations(timeout: 10)
    }
}
