import XCTest

final class PortableBackupUITests: XCTestCase {
    @MainActor
    func testPasswordAndRecipientBackupSystemPickerCancellationAndSave() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Backup QA") == true else {
            throw XCTSkip("Requires the fresh disposable backup QA simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        let owner = "backup-ui-owner-password"
        let setup = app.secureTextFields["setup.password"]
        if setup.waitForExistence(timeout: 8) {
            setup.tap(); setup.typeText(owner)
            let confirm = app.secureTextFields["setup.confirmPassword"]
            confirm.tap(); confirm.typeText(owner + "\n")
        } else {
            let login = app.secureTextFields["Enter password"]
            XCTAssertTrue(login.waitForExistence(timeout: 10)); login.tap(); login.typeText(owner + "\n")
        }
        XCTAssertTrue(app.tabBars.buttons["Notes"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Notes"].tap(); app.navigationBars.buttons["New"].tap()
        let title = "Backup UI " + UUID().uuidString.prefix(5)
        app.textFields["note.title"].tap(); app.textFields["note.title"].typeText(title)
        app.textViews["note.content"].tap(); app.textViews["note.content"].typeText("Public disposable backup note.")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<6 { if element.exists && element.isHittable { return }; app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        let link = app.buttons["settings.backup"]; reveal(link); link.tap()
        XCTAssertTrue(app.secureTextFields["backup.password"].waitForExistence(timeout: 5))
        let phrase = "WagLock*public._backup-test2026"
        app.secureTextFields["backup.password"].tap(); app.secureTextFields["backup.password"].typeText(phrase)
        app.secureTextFields["backup.confirm"].tap(); app.secureTextFields["backup.confirm"].typeText(phrase + "\n")
        let create = app.buttons["backup.create"]; reveal(create); XCTAssertTrue(create.isEnabled); create.tap()
        let save = app.buttons["backup.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 45), app.debugDescription)
        func screenshot(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        let filename = app.textFields["backup.filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        let uniqueName = "Backup QA " + UUID().uuidString.prefix(8)
        app.buttons["backup.filename.clear"].tap()
        XCTAssertFalse(save.isEnabled)
        filename.tap(); filename.typeText(uniqueName + "\n")
        XCTAssertEqual(filename.value as? String, uniqueName)
        screenshot("Encrypted backup ready with custom filename")
        save.tap()
        // iOS 18 remote Files AX can report stale control types/frames under Xcode 27.
        // Dismiss the actual native sheet with its supported drag gesture.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch.waitForExistence(timeout: 45))
        screenshot("Native Files cloud destination picker")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        for _ in 0..<5 { app.swipeDown() }
        let method = app.segmentedControls["backup.method"]
        XCTAssertTrue(method.waitForExistence(timeout: 5)); method.buttons["Age recovery key"].tap()
        let recipient = app.textFields["backup.recipient"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5)); recipient.tap()
        recipient.typeText("age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj\n")
        reveal(create); XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch.waitForExistence(timeout: 45))
        screenshot("Native Files local save")
        // The isolated iPhone 16 fixture starts in On My iPhone. The remote AX tree
        // misreports toolbar frames; use the visible system Save position on this fixture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.114)).tap()
        let saved = app.staticTexts["backup.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), app.debugDescription)
        screenshot("Native Files copy completed")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
    }
}
