import XCTest

final class LibraryMountUITests: XCTestCase {
    @MainActor
    func testOwnerLibraryRemountsAcrossRelaunchFailedLoginAndLogout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        let password = "album-ui-test-password"
        func unlock() {
            let field = app.secureTextFields["Enter password"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap()
            field.typeText(password)
            app.buttons["password.unlock"].tap()
            XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
        }
        app.launch()
        if app.secureTextFields["setup.confirmPassword"].waitForExistence(timeout: 5) {
            app.secureTextFields["setup.password"].tap()
            app.secureTextFields["setup.password"].typeText(password)
            app.secureTextFields["setup.confirmPassword"].tap()
            app.secureTextFields["setup.confirmPassword"].typeText(password + "\n")
        } else { unlock() }
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
        app.buttons["photos.albums"].tap()
        let name = "Retained session fixture \(UUID().uuidString.prefix(6))"
        for _ in 0..<10 {
            if app.buttons["album.create"].exists && app.buttons["album.create"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["album.create"].waitForExistence(timeout: 5))
        app.buttons["album.create"].tap()
        app.textFields["album.name"].tap()
        app.textFields["album.name"].typeText(name)
        app.buttons["album.save"].tap()
        for _ in 0..<10 {
            if app.staticTexts[name].firstMatch.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["photos.albums"].exists)
        XCTAssertFalse(app.staticTexts[name].exists)
        field.tap()
        field.typeText("wrong-disposable-passcode")
        app.buttons["password.unlock"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "incorrect")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photos.albums"].exists)
        unlock()
        app.buttons["photos.albums"].tap()
        for _ in 0..<10 {
            if app.staticTexts[name].firstMatch.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        let logout = app.buttons["Lock WagLock"]
        for _ in 0..<8 {
            if logout.exists && logout.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(logout.isHittable)
        logout.tap()
        let confirmation = app.sheets.buttons["Log Out"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.secureTextFields["Enter password"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["photos.albums"].exists)
        unlock()
        app.buttons["photos.albums"].tap()
        for _ in 0..<10 {
            if app.staticTexts[name].firstMatch.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Retained owner library after authenticated remount"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
