import XCTest

final class GuestPasswordUITests: XCTestCase {
    @MainActor
    func testTextGuestCredentialAndNumericGuestCredentialUseTheSharedLogin() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-autoLockTimeout", "-1"]
        app.launch()
        func login(_ password: String) {
            let field = app.secureTextFields["Enter password"]
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            let numeric = password.allSatisfy(\.isNumber)
            app.buttons[numeric ? "Number pad" : "Full keyboard"].tap()
            field.tap()
            field.typeText(password)
            XCTAssertFalse(app.staticTexts["password.strength"].exists)
            if numeric {
                app.buttons["password.keyboard.submit"].tap()
            } else {
                field.typeText("\n")
            }
            XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        }
        func reveal(_ button: XCUIElement) {
            for _ in 0..<8 {
                if button.exists && button.isHittable { return }
                app.swipeUp()
            }
            XCTAssertTrue(button.isHittable)
        }
        func logout() {
            app.tabBars.buttons["Settings"].tap()
            if app.buttons["settings.security"].exists { app.buttons["settings.security"].tap() }
            if app.navigationBars["Guest Mode"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
            let button = app.buttons["Log Out"]
            reveal(button)
            button.tap()
            app.sheets.buttons["Log Out"].tap()
            XCTAssertTrue(app.secureTextFields["Enter password"].waitForExistence(timeout: 10))
        }
        login("album-ui-test-password")
        for password in ["guest test phrase 7319", "593817"] {
            app.tabBars.buttons["Settings"].tap()
            let security = app.buttons["settings.security"]
            if security.exists { security.tap() }
            if app.buttons["settings.guest"].exists { app.buttons["settings.guest"].tap() }
            let configure = app.buttons["settings.guest.configure"]
            reveal(configure)
            configure.tap()
            let field = app.secureTextFields["guest.password"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(password)
            XCTAssertTrue(app.staticTexts["password.strength"].exists)
            let confirmation = app.secureTextFields["guest.password.confirm"]
            confirmation.tap()
            confirmation.typeText(password)
            app.buttons["guest.password.save"].tap()
            XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
            logout()
            login(password)
            app.tabBars.buttons["Settings"].tap()
            XCTAssertFalse(app.buttons["settings.faceID"].exists)
            logout()
            login("album-ui-test-password")
        }
    }
}
