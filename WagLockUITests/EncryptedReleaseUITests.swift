import XCTest

/// The actual release bundle is installed separately; never target the owner's development app.
final class EncryptedReleaseUITests: XCTestCase {
    private let owner = "PUBLIC-release-ui-owner-password"
    private let changed = "PUBLIC-release-ui-changed-password"

    @MainActor private func launch(autoLock: Int = -1) throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA") == true else {
            throw XCTSkip("Requires the isolated encrypted-release QA simulator and separately installed release app")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard"]
        // Old timeout preferences must not weaken the release background-lock policy.
        if autoLock >= 0 { app.launchArguments += ["-autoLockTimeout", String(autoLock)] }
        app.launch()
        let setup = app.secureTextFields["setup.password"]
        if setup.waitForExistence(timeout: 8) {
            setup.tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { setup.tap() }
            setup.typeText(owner)
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
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.security"].tap()
        XCTAssertTrue(app.otherElements["settings.autoLock.immediate"].exists || app.staticTexts["Immediately when you leave the app"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["settings.autoLock"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Photos"].firstMatch.tap()
        return app
    }
    @MainActor private func unlock(_ app: XCUIApplication, password: String) {
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 15)); replace(field, with: password + "\n")
    }
    @MainActor private func replace(_ field: XCUIElement, with value: String) {
        let isSecure = field.elementType == .secureTextField
        field.tap()
        let previous = field.value as? String ?? ""
        if !previous.isEmpty, previous != field.placeholderValue {
            if field.elementType == .textView {
                // Use native selection: restored text can put the caret anywhere.
                field.press(forDuration: 1.2)
                let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
                let selectAll = app.menuItems["Select All"]
                XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription)
                selectAll.tap()
                field.typeText(XCUIKeyboardKey.delete.rawValue)
            } else {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            }
        }
        if !value.isEmpty { field.typeText(value) }
        if !isSecure {
            let entered = field.value as? String ?? ""
            let actual = entered == field.placeholderValue ? "" : entered
            XCTAssertEqual(actual, value, "Test input must replace the entire prior value")
        }
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
        app.buttons["Settings"].firstMatch.tap()
        let about = app.buttons["settings.about"]; reveal(app, about); about.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "about.encryptedLibrary").firstMatch.waitForExistence(timeout: 10), "The actual release must enable encrypted storage")
        app.buttons["Done"].tap()
        app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
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
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Travel plans"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["New"].tap(); XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Packing list")
        XCTAssertEqual(body.value as? String, "An encrypted draft that survives relaunch.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Photos"].firstMatch.tap()
        app.buttons["photos.import"].tap(); app.buttons["import.photos"].tap()
        let image = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10)); image.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "photos.preview").firstMatch.waitForExistence(timeout: 10))
        capture(app, "Store - Photos")
        app.buttons["Media"].firstMatch.tap(); app.buttons["videos.import"].tap(); app.buttons["import.photos"].tap()
        let video = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Video,")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        let preview = app.descendants(matching: .any).matching(identifier: "videos.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); capture(app, "Store - Media"); preview.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "video.player").firstMatch.waitForExistence(timeout: 15))
        app.buttons["video.close"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let backup = app.buttons["settings.backup"]; reveal(app, backup); backup.tap()
        let password = app.secureTextFields["backup.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap(); password.typeText("PUBLIC*release._backup-password")
        app.secureTextFields["backup.confirm"].tap(); app.secureTextFields["backup.confirm"].typeText("PUBLIC*release._backup-password\n")
        // Repeated runs retain the public protected album created below. Supply its
        // fixture password rather than expecting backup to bypass album protection.
        for field in app.secureTextFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup.album.")).allElementsBoundByIndex {
            reveal(app, field); replace(field, with: "PUBLIC-album-password\n")
        }
        let create = app.buttons["backup.create"]; reveal(app, create)
        XCTAssertTrue(create.isEnabled, app.debugDescription); create.tap()
        let save = app.buttons["backup.save"]; XCTAssertTrue(save.waitForExistence(timeout: 45), app.debugDescription)
        app.buttons["backup.filename.clear"].tap()
        XCTAssertFalse(save.isEnabled)
        app.textFields["backup.filename"].tap(); app.textFields["backup.filename"].typeText("My WagLock backup\n")
        capture(app, "Store - Encrypted backup")
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch.waitForExistence(timeout: 45))
        capture(app, "Store - Files destinations")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        }
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Photos"].firstMatch.tap(); app.buttons["photos.albums"].tap()
        func album(_ name: String) {
            if !app.staticTexts[name].firstMatch.exists {
                app.buttons["album.create"].tap(); app.textFields["album.name"].tap(); app.textFields["album.name"].typeText(name)
                app.buttons["album.save"].tap()
            }
            XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10)); app.staticTexts[name].firstMatch.tap()
            if app.buttons["Open Album"].waitForExistence(timeout: 1) { app.buttons["Open Album"].tap() }
            let locked = app.secureTextFields["album.unlock.password"]
            if locked.exists {
                replace(locked, with: "PUBLIC-album-password")
                app.buttons["Unlock with Password"].tap()
            }
        }
        album("Trips"); album("Weekend")
        app.buttons["album.actions"].tap(); app.buttons["Album Security"].tap()
        app.buttons["album.protection"].coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap(); app.buttons["Album password"].tap()
        app.secureTextFields["album.password"].tap(); app.secureTextFields["album.password"].typeText("PUBLIC-album-password")
        app.secureTextFields["album.password.confirm"].tap(); app.secureTextFields["album.password.confirm"].typeText("PUBLIC-album-password")
        app.buttons["album.save"].tap()
        XCTAssertTrue(app.secureTextFields["album.unlock.password"].waitForExistence(timeout: 10))
        capture(app, "Store - Protected album")
        app.secureTextFields["album.unlock.password"].tap(); app.secureTextFields["album.unlock.password"].typeText("PUBLIC-album-password")
        app.buttons["Unlock with Password"].tap(); XCTAssertTrue(app.buttons["album.create"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Travel plans"].firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor func testDraftEditorSurvivesRepeatedImmediateBackgroundLocks() throws {
        let app = try launch()
        app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
        let title = app.textFields["note.title"], body = app.textViews["note.content"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let existing = body.value as? String ?? ""
        XCTAssertTrue(existing.isEmpty || existing.contains("PUBLIC"))
        replace(title, with: "")
        var expected = "PUBLIC first draft stays in its editor after background."
        replace(body, with: expected)
        for cycle in 1...5 {
            expected += " Cycle \(cycle)."; replace(body, with: expected)
            Thread.sleep(forTimeInterval: 2)
            XCTAssertFalse(app.staticTexts["note.save.error"].exists)
            XCUIDevice.shared.press(.home); app.activate()
            unlock(app, password: owner)
            XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15))
            app.buttons["Notes"].firstMatch.tap()
            XCTAssertTrue(app.buttons["notes.resumeDraft"].waitForExistence(timeout: 5))
            app.buttons["notes.resumeDraft"].tap()
            XCTAssertTrue(body.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(body.value as? String, expected)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["notes.resumeDraft"].waitForExistence(timeout: 5))
    }

    @MainActor func testFirstBodyOnlyDraftFromEmptyNotesSurvivesBackground() throws {
        let app = try launch(autoLock: 0)
        app.buttons["Notes"].firstMatch.tap()
        // Explicitly clear only the preceding PUBLIC draft on this dedicated
        // fixture. Never reset an app, credentials or an owner's library.
        if app.buttons["notes.resumeDraft"].waitForExistence(timeout: 2) {
            app.buttons["notes.resumeDraft"].tap()
            let previous = app.textViews["note.content"]
            XCTAssertTrue(previous.waitForExistence(timeout: 5))
            XCTAssertTrue((previous.value as? String ?? "").contains("PUBLIC"))
            replace(previous, with: ""); replace(app.textFields["note.title"], with: "")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["Photos"].firstMatch.tap(); app.buttons["Notes"].firstMatch.tap()
        }
        let create = app.buttons["New note"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), "Requires the dedicated fresh empty-notes fixture")
        create.tap()
        let body = app.textViews["note.content"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap(); body.typeText("PUBLIC first draft with no title, left without Done.")
        Thread.sleep(forTimeInterval: 2) // Exercise the delayed encrypted write before background.
        XCTAssertFalse(app.staticTexts["note.save.error"].exists)
        XCUIDevice.shared.press(.home); app.activate(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        let resume = app.buttons["notes.resumeDraft"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), app.debugDescription)
        resume.tap(); XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "PUBLIC first draft with no title, left without Done.")
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "PUBLIC first draft with no title, left without Done.")
    }

    @MainActor func testUnfinishedDraftIsVisibleAfterBackgroundLockAndColdRelaunch() throws {
        let app = try launch(autoLock: 0)
        app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
        let title = app.textFields["note.title"], body = app.textViews["note.content"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        replace(title, with: "PUBLIC background draft")
        replace(body, with: "The latest PUBLIC edit survives leaving without Done.")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.staticTexts["note.save.error"].exists)
        XCUIDevice.shared.press(.home); app.activate()
        unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        let resume = app.buttons["notes.resumeDraft"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), app.debugDescription)
        resume.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "PUBLIC background draft")
        XCTAssertEqual(body.value as? String, "The latest PUBLIC edit survives leaving without Done.")
        // No Done or Back before process death: the previous background flush is durable.
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "The latest PUBLIC edit survives leaving without Done.")
        replace(body, with: "PUBLIC latest retry after a second background.")
        XCUIDevice.shared.press(.home); app.activate(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "PUBLIC latest retry after a second background.")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["PUBLIC background draft"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(resume.exists, "Explicit save replaces the draft with a saved note")
        app.staticTexts["PUBLIC background draft"].firstMatch.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        replace(body, with: "PUBLIC existing note edit also survives background.")
        XCUIDevice.shared.press(.home); app.activate(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        app.staticTexts["PUBLIC background draft"].firstMatch.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "PUBLIC existing note edit also survives background.")
    }

    @MainActor func testBackgroundNeverPromotesNewDraftOrChangesAnotherSavedNote() throws {
        for timeout in [0, 600] {
            let app = try launch(autoLock: timeout)
            app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
            let title = app.textFields["note.title"], body = app.textViews["note.content"]
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            let existing = body.value as? String ?? ""
            XCTAssertTrue(existing.isEmpty || existing.contains("PUBLIC"))
            let anchor = "PUBLIC anchor \(timeout)"
            replace(title, with: anchor); replace(body, with: "PUBLIC saved anchor body")
            // Only the anchor is explicitly saved; neither following draft is.
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts[anchor].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["notes.resumeDraft"].exists)
            let noteList = app.descendants(matching: .any).matching(identifier: "notes.list").firstMatch
            XCTAssertTrue(noteList.waitForExistence(timeout: 5))
            let savedCount = try XCTUnwrap(noteList.value as? String)
            XCTAssertTrue(savedCount.hasSuffix(" saved notes"))
            app.staticTexts[anchor].firstMatch.tap()
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons["New"].tap()
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            replace(title, with: "PUBLIC draft A"); replace(body, with: "PUBLIC draft A body")
            for phase in ["A", "B"] {
                if phase == "B" {
                    app.navigationBars.buttons["New"].tap()
                    XCTAssertTrue(body.waitForExistence(timeout: 5))
                    XCTAssertEqual(body.value as? String, "PUBLIC draft A body", "New currently resumes the single draft slot")
                    replace(title, with: "PUBLIC draft B")
                    title.typeText("\n") // Return must not implicitly save a new note.
                    XCTAssertTrue(body.waitForExistence(timeout: 5))
                    replace(body, with: "PUBLIC draft B body")
                }
                Thread.sleep(forTimeInterval: 3)
                XCTAssertFalse(app.staticTexts["note.save.error"].exists)
                XCUIDevice.shared.press(.home); app.activate()
                unlock(app, password: owner)
                XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15))
                app.buttons["Notes"].firstMatch.tap()
                let resume = app.buttons["notes.resumeDraft"]
                XCTAssertTrue(resume.waitForExistence(timeout: 5))
                // List virtualization and draft headings change visible cell counts.
                // Compare the accessible saved-model count, excluding the draft slot.
                XCTAssertEqual(noteList.value as? String, savedCount, "Background must never promote a draft into a saved note")
                XCTAssertTrue(resume.staticTexts["PUBLIC draft " + phase].exists)
                XCTAssertTrue(app.staticTexts[anchor].firstMatch.exists)
                if phase == "B" { XCTAssertFalse(app.staticTexts["PUBLIC draft A"].exists) }
            }
            app.terminate(); app.launch(); unlock(app, password: owner)
            XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
            XCTAssertEqual(noteList.value as? String, savedCount)
            app.buttons["notes.resumeDraft"].tap(); XCTAssertTrue(body.waitForExistence(timeout: 5))
            XCTAssertEqual(body.value as? String, "PUBLIC draft B body")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.staticTexts[anchor].firstMatch.tap(); XCTAssertTrue(body.waitForExistence(timeout: 5))
            XCTAssertEqual(title.value as? String, anchor)
            XCTAssertEqual(body.value as? String, "PUBLIC saved anchor body")
        }
    }

    @MainActor func testRetiredCalculatorAndAttemptBudgetSurviveRelaunch() throws {
        let app = try launch()
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.security"].tap()
        XCTAssertFalse(app.buttons["Calculator Login Mode"].exists)
        app.terminate()
        app.launchArguments += ["-disguiseModeEnabled", "YES"]
        app.launch()
        for attempt in 1...2 {
            unlock(app, password: "PUBLIC deliberately incorrect password")
            XCTAssertTrue(app.staticTexts["Incorrect password. \(5 - attempt) attempts remaining."].waitForExistence(timeout: 8), app.debugDescription)
            app.terminate(); app.launch()
            XCTAssertTrue(app.secureTextFields["Enter password"].waitForExistence(timeout: 10))
        }
        unlock(app, password: owner)
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
    }

    @MainActor func testRepeatedInProcessLockReopensEncryptedLibrary() throws {
        let app = try launch()
        for _ in 0..<3 {
            app.buttons["Settings"].firstMatch.tap()
            let lock = app.buttons["settings.lock"]; reveal(app, lock); lock.tap()
            let confirm = app.buttons["Log Out"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            unlock(app, password: owner)
            XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertFalse(app.otherElements["library.mount.error"].exists)
        }
    }
    @MainActor func testStoreReadyScreenshots() throws {
        let app = try launch()
        app.buttons["Notes"].firstMatch.tap(); capture(app, "Store - Notes")
        app.buttons["Photos"].firstMatch.tap(); capture(app, "Store - Photos")
        app.buttons["Media"].firstMatch.tap(); capture(app, "Store - Media")
        app.buttons["Photos"].firstMatch.tap(); app.buttons["photos.albums"].tap()
        app.staticTexts["Trips"].firstMatch.tap()
        if app.buttons["Open Album"].waitForExistence(timeout: 2) { app.buttons["Open Album"].tap() }
        XCTAssertTrue(app.staticTexts["Weekend"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Weekend"].firstMatch.tap()
        XCTAssertTrue(app.secureTextFields["album.unlock.password"].waitForExistence(timeout: 10))
        capture(app, "Store - Protected album")
    }
    @MainActor private func changePassword(_ app: XCUIApplication, from current: String, to replacement: String) {
        app.buttons["Settings"].firstMatch.tap(); let security = app.buttons["settings.security"]; reveal(app, security); security.tap()
        app.buttons["settings.changePassword"].tap()
        let old = app.secureTextFields["passwordChange.current"]
        XCTAssertTrue(old.waitForExistence(timeout: 5)); old.tap(); old.typeText(current)
        app.secureTextFields["passwordChange.new"].tap(); app.secureTextFields["passwordChange.new"].typeText(replacement)
        app.secureTextFields["passwordChange.confirm"].tap(); app.secureTextFields["passwordChange.confirm"].typeText(replacement + "\n")
        let save = app.buttons["passwordChange.save"]; reveal(app, save); save.tap()
        XCTAssertTrue(app.buttons["Photos"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
    }
    @MainActor func testAlternativePasscodeOpensIndependentPersistentNotesAndSettings() throws {
        let app = try launch()
        let guest = "PUBLIC-release-secondary-password"
        let marker = String(UUID().uuidString.prefix(8))
        let ownerTitle = "Primary sample " + marker, guestTitle = "Separate sample " + marker
        func note(_ title: String) {
            app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
            replace(app.textFields["note.title"], with: title)
            replace(app.textViews["note.content"], with: "Disposable isolated UI fixture")
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 8))
        }
        note(ownerTitle)
        app.buttons["Settings"].firstMatch.tap(); app.buttons["settings.security"].tap()
        let configure = app.buttons["settings.guest.configure"]
        if configure.exists {
            reveal(app, configure); configure.tap()
            replace(app.secureTextFields["guest.password"], with: guest)
            replace(app.secureTextFields["guest.password.confirm"], with: guest)
            app.buttons["guest.password.save"].tap()
            XCTAssertTrue(app.staticTexts["Alternative passcode configured"].waitForExistence(timeout: 10), app.debugDescription)
        }
        app.terminate(); app.launch(); unlock(app, password: guest)
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts[ownerTitle].exists)
        note(guestTitle)
        app.buttons["Settings"].firstMatch.tap(); app.buttons["settings.security"].tap()
        XCTAssertFalse(app.buttons["settings.guest.configure"].exists)
        XCTAssertFalse(app.staticTexts["Alternative passcode configured"].exists)
        XCTAssertTrue(app.buttons["settings.changePassword"].exists)
        XCTAssertTrue(app.buttons["settings.faceID"].exists)
        app.buttons["settings.faceID"].tap()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Passcodes continue")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "assign Face ID")).firstMatch.exists)
        replace(app.secureTextFields["vault.faceID.password"], with: guest)
        app.buttons["vault.faceID.enable"].tap()
        let consent = app.alerts["Enable Face ID"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Face ID opens its assigned vault"].exists)
        XCTAssertFalse(consent.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "choose a vault")).firstMatch.exists)
        consent.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        capture(app, "Secondary security has ordinary vault controls")
        app.terminate(); app.launch(); unlock(app, password: guest)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[guestTitle].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[ownerTitle].exists)
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[ownerTitle].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[guestTitle].exists)
    }

    @MainActor func testExplicitEraseCancelsSafelyThenStartsAnIndependentFreshLibrary() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA Reset") == true else {
            throw XCTSkip("Destructive UI test requires its dedicated disposable reset simulator")
        }
        let app = try launch()
        let secondary = "PUBLIC-release-secondary-password"
        let fresh = "PUBLIC-after-erase-password"
        func note(_ title: String) {
            app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
            replace(app.textFields["note.title"], with: title)
            replace(app.textViews["note.content"], with: "PUBLIC disposable erase sample")
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 8))
        }
        func openErase() {
            let help = app.buttons["password.help"]
            XCTAssertTrue(help.waitForExistence(timeout: 10)); reveal(app, help); help.tap()
            XCTAssertTrue(app.navigationBars["Can't unlock?"].waitForExistence(timeout: 5), app.debugDescription)
            let instructions = app.descendants(matching: .any).matching(identifier: "recovery.instructions").firstMatch
            reveal(app, instructions); XCTAssertTrue(instructions.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "secondary vault")).firstMatch.exists)
            let erase = app.buttons["recovery.erase.open"]; reveal(app, erase); erase.tap()
            XCTAssertTrue(app.textFields["recovery.erase.confirmation"].waitForExistence(timeout: 5))
        }
        note("PUBLIC primary before erase")
        app.buttons["Settings"].firstMatch.tap(); app.buttons["settings.security"].tap()
        let configure = app.buttons["settings.guest.configure"]; reveal(app, configure); configure.tap()
        replace(app.secureTextFields["guest.password"], with: secondary)
        replace(app.secureTextFields["guest.password.confirm"], with: secondary)
        app.buttons["guest.password.save"].tap()
        XCTAssertTrue(app.staticTexts["Alternative passcode configured"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); unlock(app, password: secondary)
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 15))
        note("PUBLIC separate before erase")
        app.terminate(); app.launch(); openErase()
        let field = app.textFields["recovery.erase.confirmation"]
        let acknowledge = app.switches["recovery.erase.acknowledge"]
        let erase = app.buttons["recovery.erase.confirm"]
        XCTAssertFalse(erase.isEnabled)
        replace(field, with: "ERASE"); XCTAssertFalse(erase.isEnabled)
        acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(acknowledge.value as? String, "1"); XCTAssertTrue(erase.isEnabled)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertFalse(erase.isEnabled)
        XCTAssertEqual(acknowledge.value as? String, "0")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC primary before erase"].waitForExistence(timeout: 8))
        app.terminate(); app.launch(); unlock(app, password: secondary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC separate before erase"].waitForExistence(timeout: 8))
        app.terminate(); app.launch(); openErase()
        replace(field, with: "ERASE")
        acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(acknowledge.value as? String, "1")
        reveal(app, erase); erase.tap()
        let setup = app.secureTextFields["setup.password"]
        XCTAssertTrue(setup.waitForExistence(timeout: 30), app.debugDescription)
        replace(setup, with: fresh)
        replace(app.secureTextFields["setup.confirmPassword"], with: fresh + "\n")
        XCTAssertTrue(app.buttons["photos.albums"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["PUBLIC primary before erase"].exists)
        XCTAssertFalse(app.staticTexts["PUBLIC separate before erase"].exists)
        note("PUBLIC after erase")
        app.buttons["Settings"].firstMatch.tap(); app.buttons["settings.security"].tap()
        XCTAssertTrue(app.buttons["settings.guest.configure"].exists)
        XCTAssertFalse(app.staticTexts["Alternative passcode configured"].exists)
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["vault.faceID.unlock"].exists)
        for old in [owner, secondary] {
            unlock(app, password: old)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "password.error").firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["photos.albums"].exists)
        }
        unlock(app, password: fresh)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC after erase"].waitForExistence(timeout: 8))
    }

    @MainActor func testExplicitPasswordConfirmationKeepsManualMismatchChecksAndPreservesLibrary() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA Confirmation") == true else {
            throw XCTSkip("Requires a fresh disposable confirmation-form simulator")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard"]
        app.launch()
        func reach(_ element: XCUIElement) {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<8 {
                if element.exists && element.isHittable { return }
                if element.exists && element.frame.minY < scroll.frame.minY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        let original = "PUBLIC-confirmation*._-setup"
        let replacement = "PUBLIC-confirmation*._-changed"
        let first = app.secureTextFields["setup.password"]
        let confirmation = app.secureTextFields["setup.confirmPassword"]
        let use = app.buttons["setup.confirmEntered"], save = app.buttons["setup.save"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        reach(use); XCTAssertFalse(use.isEnabled)
        replace(first, with: original)
        XCTAssertEqual(confirmation.value as? String, confirmation.placeholderValue)
        replace(confirmation, with: "PUBLIC manual mismatch" + "\n")
        XCTAssertTrue(first.exists, "A mismatch must not create a library")
        XCTAssertTrue(app.staticTexts["Passwords do not match"].firstMatch.exists)
        reach(use); use.tap()
        XCTAssertTrue(save.isEnabled)
        replace(first, with: original + "x")
        confirmation.tap(); confirmation.typeText("\n")
        XCTAssertTrue(first.exists, "Editing must not silently mirror into confirmation")
        XCTAssertTrue(app.staticTexts["Passwords do not match"].firstMatch.exists)
        replace(first, with: original)
        confirmation.tap(); confirmation.typeText("\n")
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
        replace(app.textFields["note.title"], with: "PUBLIC confirmation sample")
        replace(app.textViews["note.content"], with: "PUBLIC note survives the explicit confirmation password change")
        app.navigationBars.buttons["Done"].tap()
        func openChange() {
            app.buttons["Settings"].firstMatch.tap(); app.buttons["settings.security"].tap()
            app.buttons["settings.changePassword"].tap()
            XCTAssertTrue(app.secureTextFields["passwordChange.current"].waitForExistence(timeout: 8))
        }
        func fillChange() {
            replace(app.secureTextFields["passwordChange.current"], with: original)
            replace(app.secureTextFields["passwordChange.new"], with: replacement)
            let confirm = app.secureTextFields["passwordChange.confirm"]
            XCTAssertEqual(confirm.value as? String, confirm.placeholderValue)
            replace(confirm, with: "PUBLIC another manual mismatch")
            XCTAssertFalse(app.buttons["passwordChange.save"].isEnabled)
            let button = app.buttons["passwordChange.confirmEntered"]
            reach(button); button.tap()
            XCTAssertTrue(app.buttons["passwordChange.save"].isEnabled)
            XCTAssertTrue(app.secureTextFields["passwordChange.current"].exists, "Confirmation must not submit")
        }
        openChange(); fillChange()
        replace(app.secureTextFields["passwordChange.new"], with: replacement + "x")
        XCTAssertFalse(app.buttons["passwordChange.save"].isEnabled)
        XCUIDevice.shared.press(.home); app.activate(); unlock(app, password: original)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15))
        openChange()
        for id in ["passwordChange.current", "passwordChange.new", "passwordChange.confirm"] {
            let field = app.secureTextFields[id]
            XCTAssertEqual(field.value as? String, field.placeholderValue)
        }
        fillChange()
        let change = app.buttons["passwordChange.save"]; reach(change); change.tap()
        XCTAssertTrue(app.buttons["Photos"].firstMatch.waitForExistence(timeout: 20))
        app.terminate(); app.launch(); unlock(app, password: original)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "password.error").firstMatch.waitForExistence(timeout: 8))
        unlock(app, password: replacement)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC confirmation sample"].waitForExistence(timeout: 8))
        app.buttons["Settings"].firstMatch.tap(); app.buttons["settings.security"].tap()
        let configure = app.buttons["settings.guest.configure"]; reach(configure); configure.tap()
        let secondary = "PUBLIC-confirmation*._-alternative"
        replace(app.secureTextFields["guest.password"], with: secondary)
        XCTAssertFalse(app.buttons["guest.password.save"].isEnabled)
        let guestUse = app.buttons["guest.password.confirmEntered"]; reach(guestUse); guestUse.tap()
        XCTAssertTrue(app.buttons["guest.password.save"].isEnabled)
        app.buttons["guest.password.save"].tap()
        XCTAssertTrue(app.staticTexts["Alternative passcode configured"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); unlock(app, password: secondary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["PUBLIC confirmation sample"].exists)
    }

    @MainActor func testReleasePasswordChangePreservesLibrary() throws {
        let app = try launch()
        app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
        replace(app.textFields["note.title"], with: "Password change sample")
        replace(app.textViews["note.content"], with: "The same encrypted note survives a new unlock password.")
        app.navigationBars.buttons["Done"].tap()
        changePassword(app, from: owner, to: changed)
        app.terminate(); app.launch(); unlock(app, password: changed)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Password change sample"].firstMatch.waitForExistence(timeout: 10))
        changePassword(app, from: changed, to: owner)
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Password change sample"].firstMatch.waitForExistence(timeout: 10))
    }
}
