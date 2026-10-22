import XCTest

/// Uses only the explicitly disposable, already-initialized QA simulator.
final class UICompletionUITests: XCTestCase {
    @MainActor
    func testGeneratedVideoImportAndPlayer() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Vaultito Import QA") == true else {
            throw XCTSkip("Requires the seeded disposable QA simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 15)); field.tap(); field.typeText("album-ui-test-password\n")
        XCTAssertTrue(app.tabBars.buttons["Media"].waitForExistence(timeout: 15)); app.tabBars.buttons["Media"].tap()
        app.buttons["videos.import"].tap(); app.buttons["import.photos"].tap()
        let video = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Video,")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10), "Seed the generated video with simctl addmedia before this QA test")
        video.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        let preview = app.descendants(matching: .any).matching(identifier: "videos.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); preview.tap()
        XCTAssertTrue(app.buttons["video.close"].waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Generated video - player"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["video.close"].tap()
        XCTAssertTrue(app.tabBars.buttons["Media"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemainingDestinationsInLightAndDark() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Vaultito Import QA") == true else {
            throw XCTSkip("Requires the disposable initialized WagLock QA simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap(); field.typeText("album-ui-test-password\n")
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
        func shot(_ label: String) {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = label; capture.lifetime = .keepAlways; add(capture)
        }
        func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<6 {
                if element.exists && element.isHittable { return }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable)
        }
        for appearance in ["Light", "Dark"] {
            app.tabBars.buttons["Settings"].tap()
            app.buttons["settings.appearance"].tap()
            let picker = app.segmentedControls["settings.appearance.picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.buttons[appearance].tap()
            app.buttons["settings.layout"].tap()
            shot("\(appearance) - library layout")
            back(); back()
            app.buttons["settings.security"].tap()
            shot("\(appearance) - security")
            app.buttons["settings.autoLock"].tap()
            shot("\(appearance) - auto-lock")
            back()
            app.buttons["settings.changePassword"].tap()
            XCTAssertTrue(app.navigationBars["Change Password"].waitForExistence(timeout: 5) || app.navigationBars["Change password"].exists)
            shot("\(appearance) - change password")
            app.buttons["Cancel"].firstMatch.tap()
            let guest = app.buttons["settings.guest"]
            reveal(guest); guest.tap()
            app.buttons["settings.guest.configure"].tap()
            XCTAssertTrue(app.secureTextFields["guest.password"].waitForExistence(timeout: 5))
            shot("\(appearance) - guest password")
            app.buttons["Cancel"].firstMatch.tap()
            back()
            let calculator = app.buttons["settings.calculator"]
            reveal(calculator); calculator.tap()
            shot("\(appearance) - calculator settings")
            app.buttons["Preview calculator"].tap()
            XCTAssertTrue(app.buttons["7"].waitForExistence(timeout: 5))
            shot("\(appearance) - calculator")
            back(); back(); back()
            let storage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Storage")).firstMatch
            storage.tap()
            shot("\(appearance) - storage")
            back()
            app.buttons["settings.about"].tap()
            shot("\(appearance) - about")
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Offline & privacy")).firstMatch.tap()
            shot("\(appearance) - offline privacy")
            back()
            app.navigationBars.buttons["Done"].tap()
            app.tabBars.buttons["Notes"].tap()
            let newNote = app.navigationBars.buttons["New"]
            XCTAssertTrue(newNote.waitForExistence(timeout: 5)); newNote.tap()
            let title = app.textFields["note.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
            let name = "UI \(appearance) \(UUID().uuidString.prefix(4))"
            let old = (title.value as? String) ?? ""
            if old != "Title" && old != "Untitled" && !old.isEmpty { title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
            title.typeText(name)
            let editor = app.textViews["note.content"]
            editor.tap(); editor.typeText("Disposable design review note.")
            shot("\(appearance) - note editor")
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
            shot("\(appearance) - note cards")
            app.tabBars.buttons["Media"].tap()
            app.segmentedControls.buttons["Audio"].tap()
            let audioRow = app.descendants(matching: .any).matching(identifier: "audio.row").firstMatch
            shot("\(appearance) - audio library")
            if audioRow.exists {
                audioRow.tap()
                XCTAssertTrue(app.buttons["audio.player.close"].waitForExistence(timeout: 5))
                shot("\(appearance) - audio player")
                app.buttons["audio.player.close"].tap()
            }
            app.tabBars.buttons["Photos"].tap()
            shot("\(appearance) - grouped photos")
            let preview = app.descendants(matching: .any).matching(identifier: "photos.preview").firstMatch
            if preview.waitForExistence(timeout: 5) {
                preview.tap()
                XCTAssertTrue(app.buttons["photo.info"].waitForExistence(timeout: 5))
                shot("\(appearance) - photo viewer")
                app.buttons["photo.info"].tap()
                XCTAssertTrue(app.navigationBars["Photo information"].waitForExistence(timeout: 5))
                shot("\(appearance) - photo information")
                app.buttons["photo.info.close"].tap()
                app.buttons["photo.close"].tap()
            }
        }
    }
}
