import XCTest

final class DesignAppearanceUITests: XCTestCase {
    @MainActor
    func testDarkOnlyGraphiteAndCoreDestinationsRemainAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        func unlock() {
            let field = app.secureTextFields["Enter password"]
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            field.tap()
            field.typeText("album-ui-test-password\n")
            XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15))
        }
        func capture(_ title: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = title
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.launch()
        XCTAssertTrue(app.secureTextFields["Enter password"].waitForExistence(timeout: 15))
        capture("Graphite - unlock")
        unlock()
        capture("Graphite - photos")
        app.buttons["library.add"].tap()
        XCTAssertTrue(app.buttons["import.photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["import.files"].exists)
        XCTAssertTrue(app.buttons["import.audio"].exists)
        capture("Graphite - import")
        app.buttons["Cancel"].tap()
        for tab in ["Albums", "Files", "Notes", "Settings"] {
            app.tabBars.buttons[tab].tap()
            capture("Graphite - \(tab)")
        }
        // Graphite is dark only: the Appearance setting no longer exists.
        XCTAssertFalse(app.buttons["settings.appearance"].exists)
        XCTAssertTrue(app.buttons["settings.layout"].exists)
        app.tabBars.buttons["Library"].tap()
        app.buttons["library.filter.videos"].tap()
        capture("Graphite - library videos")
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.security"].tap()
        XCTAssertTrue(app.buttons["settings.faceID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.guest"].exists)
    }
}
