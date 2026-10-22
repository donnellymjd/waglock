import XCTest

final class AlbumWorkflowUITests: XCTestCase {
    @MainActor
    func testNestedAlbumsLockAndPasswordProtection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard"]
        app.launch()
        let vaultPassword = "album-ui-test-password"
        if app.secureTextFields["setup.password"].waitForExistence(timeout: 8) {
            app.secureTextFields["setup.password"].tap()
            app.secureTextFields["setup.password"].typeText(vaultPassword)
            app.secureTextFields["setup.confirmPassword"].tap()
            app.secureTextFields["setup.confirmPassword"].typeText(vaultPassword + "\n")
        } else if app.secureTextFields["Enter password"].waitForExistence(timeout: 3) {
            app.secureTextFields["Enter password"].tap()
            app.secureTextFields["Enter password"].typeText(vaultPassword + "\n")
        }
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
        app.buttons["photos.albums"].tap()
        let suffix = UUID().uuidString.prefix(6)
        let parent = "Parent \(suffix)"
        let child = "Child \(suffix)"
        func createAlbum(_ name: String) {
            app.buttons["album.create"].tap()
            app.textFields["album.name"].tap()
            app.textFields["album.name"].typeText(name)
            app.buttons["album.save"].tap()
            XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10))
            app.staticTexts[name].firstMatch.tap()
        }
        createAlbum(parent)
        createAlbum(child)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["album.actions"].tap()
        app.buttons["Lock Album"].tap()
        XCTAssertTrue(app.buttons["album.unlock.inherited"].waitForExistence(timeout: 5))
        app.buttons["album.unlock.inherited"].tap()
        XCTAssertTrue(app.staticTexts[child].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts[child].firstMatch.tap()
        XCTAssertTrue(app.buttons["album.unlock.inherited"].waitForExistence(timeout: 5))
        app.buttons["album.unlock.inherited"].tap()
        app.buttons["album.actions"].tap()
        app.buttons["Album Security"].tap()
        app.buttons["album.protection"].tap()
        app.buttons["Album password"].tap()
        app.secureTextFields["album.password"].tap()
        app.secureTextFields["album.password"].typeText("child-ui-password")
        app.secureTextFields["album.password.confirm"].tap()
        app.secureTextFields["album.password.confirm"].typeText("child-ui-password")
        app.buttons["album.save"].tap()
        XCTAssertTrue(app.secureTextFields["album.unlock.password"].waitForExistence(timeout: 10))
        app.secureTextFields["album.unlock.password"].tap()
        app.secureTextFields["album.unlock.password"].typeText("incorrect")
        app.buttons["Unlock with Password"].tap()
        XCTAssertTrue(app.staticTexts["The password is incorrect or the album is damaged."].waitForExistence(timeout: 5))
        app.secureTextFields["album.unlock.password"].tap()
        app.secureTextFields["album.unlock.password"].typeText("child-ui-password")
        app.buttons["Unlock with Password"].tap()
        XCTAssertTrue(app.buttons["album.create"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unlocked nested album"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.security"].tap()
        for _ in 0..<5 where !app.buttons["settings.faceID"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["settings.faceID"].waitForExistence(timeout: 5))
        app.buttons["settings.faceID"].tap()
        XCTAssertTrue(app.secureTextFields["vault.faceID.password"].waitForExistence(timeout: 5))
    }
}
