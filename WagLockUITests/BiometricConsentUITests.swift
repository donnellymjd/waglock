import XCTest

final class BiometricConsentUITests: XCTestCase {
    @MainActor
    func testVaultFaceIDWarningCanBeCancelledBeforeEnrollment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        let password = "album-ui-test-password"
        if app.secureTextFields["setup.confirmPassword"].waitForExistence(timeout: 5) {
            app.secureTextFields["setup.password"].tap()
            app.secureTextFields["setup.password"].typeText(password)
            app.secureTextFields["setup.confirmPassword"].tap()
            app.secureTextFields["setup.confirmPassword"].typeText(password + "\n")
        } else {
            let field = app.secureTextFields["Enter password"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText(password)
            app.buttons["password.unlock"].tap()
        }
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        app.buttons["settings.security"].tap()
        let faceID = app.buttons["settings.faceID"]
        for _ in 0..<8 {
            if faceID.exists && faceID.isHittable { break }
            app.swipeUp()
        }
        faceID.tap()
        if app.buttons["Disable Face ID"].exists { app.buttons["Disable Face ID"].tap() }
        let field = app.secureTextFields["vault.faceID.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(password)
        app.buttons["vault.faceID.enable"].tap()
        let warning = app.alerts["Face ID opens its assigned vault"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "It cannot tell which vault")).firstMatch.exists)
        XCTAssertTrue(warning.buttons["Enable for This Vault"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Face ID assigned-vault warning before enrollment"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        warning.buttons["Cancel"].tap()
        XCTAssertFalse(warning.exists)
        XCTAssertTrue(app.staticTexts["Face ID disabled"].exists)
        XCTAssertEqual(field.value as? String, "Current vault password")
        XCTAssertFalse(app.buttons["Disable Face ID"].exists)
    }
}
