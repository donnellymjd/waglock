import XCTest

final class WagLockBrandingUITests: XCTestCase {
    @MainActor
    func testBrandingAndOriginalNoticesRemainAccessible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["WagLock"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["We Always Guard"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Zero Network"].exists)
        let login = XCTAttachment(screenshot: app.screenshot())
        login.name = "WagLock login branding"
        login.lifetime = .keepAlways
        add(login)

        let password = "album-ui-test-password"
        if app.secureTextFields["setup.confirmPassword"].exists {
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
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let about = app.buttons["settings.about"]
        for _ in 0..<8 {
            if about.exists && about.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(about.exists)
        about.tap()
        XCTAssertTrue(app.staticTexts["WagLock"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["We Always Guard"].firstMatch.waitForExistence(timeout: 10))
        let notices = app.buttons["about.openSourceNotices"]
        for _ in 0..<8 {
            if notices.exists && notices.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(notices.exists)
        notices.tap()
        XCTAssertTrue(app.navigationBars["Open Source Notices"].waitForExistence(timeout: 5))
        let originalAttribution = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "© 2025 ZeroNet Space")).firstMatch
        XCTAssertTrue(originalAttribution.exists)
        let noticeScreenshot = XCTAttachment(screenshot: app.screenshot())
        noticeScreenshot.name = "WagLock original attribution and GPL notices"
        noticeScreenshot.lifetime = .keepAlways
        add(noticeScreenshot)
    }
}
