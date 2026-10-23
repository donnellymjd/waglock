import XCTest

/// The actual release bundle is installed separately; never target the owner's development app.
final class EncryptedReleaseUITests: XCTestCase {
    private let owner = "PUBLIC-release-ui-owner-password"
    private let changed = "PUBLIC-release-ui-changed-password"

    @MainActor private func launch() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA") == true else {
            throw XCTSkip("Requires the isolated encrypted-release QA simulator and separately installed release app")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        let setup = app.secureTextFields["setup.password"]
        if setup.waitForExistence(timeout: 8) {
            setup.tap(); setup.typeText(owner)
            app.secureTextFields["setup.confirmPassword"].tap(); app.secureTextFields["setup.confirmPassword"].typeText(owner + "\n")
        } else {
            unlock(app, password: owner)
            if !app.buttons["photos.albums"].waitForExistence(timeout: 4), app.secureTextFields["Enter password"].exists {
                unlock(app, password: changed)
                XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15), app.debugDescription)
                changePassword(app, from: changed, to: owner)
            }
        }
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    @MainActor private func unlock(_ app: XCUIApplication, password: String) {
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 15)); replace(field, with: password + "\n")
    }
    @MainActor private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let previous = field.value as? String ?? ""
        if !previous.isEmpty, previous != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count)) }
        field.typeText(value)
    }
    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        // Native simctl capture avoids XCTest's occasional one-pixel screenshot rounding.
        print("WAGLOCK_NATIVE_CAPTURE:" + name); fflush(stdout)
        Thread.sleep(forTimeInterval: 4)
    }
    @MainActor func testFreshReleasePersistenceAndScreenshots() throws {
        let app = try launch()
        app.tabBars.buttons["Settings"].tap()
        let about = app.buttons["settings.about"]; reveal(app, about); about.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "about.encryptedLibrary").firstMatch.waitForExistence(timeout: 10), "The actual release must enable encrypted storage")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Notes"].tap(); app.navigationBars.buttons["New"].tap()
        let title = app.textFields["note.title"], body = app.textViews["note.content"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        replace(title, with: "Travel plans"); replace(body, with: "# A little room to think\nKeep tickets, memories and ideas together.")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Travel plans"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Store - Notes")
        app.navigationBars.buttons["New"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        replace(title, with: "Packing list"); replace(body, with: "An encrypted draft that survives relaunch.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.tabBars.buttons["Notes"].waitForExistence(timeout: 15)); app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Travel plans"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["New"].tap(); XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Packing list")
        XCTAssertEqual(body.value as? String, "An encrypted draft that survives relaunch.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Photos"].tap()
        app.buttons["photos.import"].tap(); app.buttons["import.photos"].tap()
        let image = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10)); image.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "photos.preview").firstMatch.waitForExistence(timeout: 10))
        capture(app, "Store - Photos")
        app.tabBars.buttons["Media"].tap(); app.buttons["videos.import"].tap(); app.buttons["import.photos"].tap()
        let video = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Video,")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        let preview = app.descendants(matching: .any).matching(identifier: "videos.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); capture(app, "Store - Media"); preview.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "video.player").firstMatch.waitForExistence(timeout: 15))
        app.buttons["video.close"].tap()
        app.tabBars.buttons["Settings"].tap()
        let backup = app.buttons["settings.backup"]; reveal(app, backup); backup.tap()
        let password = app.secureTextFields["backup.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap(); password.typeText("PUBLIC*release._backup-password")
        app.secureTextFields["backup.confirm"].tap(); app.secureTextFields["backup.confirm"].typeText("PUBLIC*release._backup-password\n")
        let create = app.buttons["backup.create"]; reveal(app, create); create.tap()
        let save = app.buttons["backup.save"]; XCTAssertTrue(save.waitForExistence(timeout: 45), app.debugDescription)
        app.buttons["backup.filename.clear"].tap()
        XCTAssertFalse(save.isEnabled)
        app.textFields["backup.filename"].tap(); app.textFields["backup.filename"].typeText("My WagLock backup\n")
        capture(app, "Store - Encrypted backup")
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch.waitForExistence(timeout: 45))
        capture(app, "Store - Files destinations")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Photos"].tap(); app.buttons["photos.albums"].tap()
        func album(_ name: String) {
            app.buttons["album.create"].tap(); app.textFields["album.name"].tap(); app.textFields["album.name"].typeText(name)
            app.buttons["album.save"].tap(); XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10)); app.staticTexts[name].firstMatch.tap()
        }
        album("Trips"); album("Weekend")
        app.buttons["album.actions"].tap(); app.buttons["Album Security"].tap()
        app.buttons["album.protection"].tap(); app.buttons["Album password"].tap()
        app.secureTextFields["album.password"].tap(); app.secureTextFields["album.password"].typeText("PUBLIC-album-password")
        app.secureTextFields["album.password.confirm"].tap(); app.secureTextFields["album.password.confirm"].typeText("PUBLIC-album-password")
        app.buttons["album.save"].tap()
        XCTAssertTrue(app.secureTextFields["album.unlock.password"].waitForExistence(timeout: 10))
        capture(app, "Store - Protected album")
        app.secureTextFields["album.unlock.password"].tap(); app.secureTextFields["album.unlock.password"].typeText("PUBLIC-album-password")
        app.buttons["Unlock with Password"].tap(); XCTAssertTrue(app.buttons["album.create"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.tabBars.buttons["Notes"].waitForExistence(timeout: 15)); app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Travel plans"].firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor private func changePassword(_ app: XCUIApplication, from current: String, to replacement: String) {
        app.tabBars.buttons["Settings"].tap(); let security = app.buttons["settings.security"]; reveal(app, security); security.tap()
        app.buttons["settings.changePassword"].tap()
        let old = app.secureTextFields["passwordChange.current"]
        XCTAssertTrue(old.waitForExistence(timeout: 5)); old.tap(); old.typeText(current)
        app.secureTextFields["passwordChange.new"].tap(); app.secureTextFields["passwordChange.new"].typeText(replacement)
        app.secureTextFields["passwordChange.confirm"].tap(); app.secureTextFields["passwordChange.confirm"].typeText(replacement + "\n")
        let save = app.buttons["passwordChange.save"]; reveal(app, save); save.tap()
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 15), app.debugDescription)
    }
    @MainActor func testReleasePasswordChangePreservesLibrary() throws {
        let app = try launch()
        app.tabBars.buttons["Notes"].tap(); app.navigationBars.buttons["New"].tap()
        replace(app.textFields["note.title"], with: "Password change sample")
        replace(app.textViews["note.content"], with: "The same encrypted note survives a new unlock password.")
        app.navigationBars.buttons["Done"].tap()
        changePassword(app, from: owner, to: changed)
        app.terminate(); app.launch(); unlock(app, password: changed)
        XCTAssertTrue(app.tabBars.buttons["Notes"].waitForExistence(timeout: 15)); app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Password change sample"].firstMatch.waitForExistence(timeout: 10))
        changePassword(app, from: changed, to: owner)
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.tabBars.buttons["Notes"].waitForExistence(timeout: 15)); app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Password change sample"].firstMatch.waitForExistence(timeout: 10))
    }
}
