import XCTest

final class DesignAppearanceUITests: XCTestCase {
    @MainActor
    func testAppearancePersistsAndCoreDestinationsRemainAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        func unlock() {
            let field = app.secureTextFields["Enter password"]
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            field.tap()
            field.typeText("album-ui-test-password\n")
            XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
        }
        func capture(_ title: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = title
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.launch()
        XCTAssertTrue(app.secureTextFields["Enter password"].waitForExistence(timeout: 15))
        capture("Figma implementation - unlock")
        unlock()
        capture("Figma implementation - photos")
        app.buttons["photos.import"].tap()
        XCTAssertTrue(app.buttons["import.photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["import.files"].exists)
        XCTAssertTrue(app.buttons["import.audio"].exists)
        capture("Figma implementation - import")
        app.buttons["Cancel"].tap()
        for tab in ["Media", "Files", "Notes", "Settings"] {
            app.tabBars.buttons[tab].tap()
            capture("Figma implementation - \(tab)")
        }
        app.buttons["settings.appearance"].tap()
        let picker = app.segmentedControls["settings.appearance.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Dark"].tap()
        XCTAssertTrue(picker.buttons["Dark"].isSelected)
        capture("Figma implementation - dark appearance")
        app.tabBars.buttons["Notes"].tap()
        capture("Figma implementation - dark notes")
        app.terminate()
        app.launch()
        unlock()
        app.tabBars.buttons["Settings"].tap()
        capture("Figma implementation - dark settings")
        app.buttons["settings.appearance"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Dark"].isSelected)
        picker.buttons["Light"].tap()
        capture("Figma implementation - light appearance")
        app.tabBars.buttons["Notes"].tap()
        capture("Figma implementation - light notes")
        app.tabBars.buttons["Settings"].tap()
        picker.buttons["System"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.security"].tap()
        XCTAssertTrue(app.buttons["settings.faceID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.guest"].exists)
    }
}
