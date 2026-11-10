import XCTest

/// The actual release bundle is installed separately; never target the owner's development app.
final class EncryptedReleaseUITests: XCTestCase {
    private let owner = "PUBLIC-release-ui-owner-password"
    private let changed = "PUBLIC-release-ui-changed-password"

    /// Fresh release installs start with Welcome, then require the no-reset acknowledgment.
    @MainActor private func beginOnboarding(_ app: XCUIApplication) {
        let start = app.buttons["onboarding.start"]
        if start.waitForExistence(timeout: 8) { start.tap() }
        let storage = app.buttons["onboarding.storage.continue"]
        if storage.waitForExistence(timeout: 3) { storage.tap() } // Standard is the default.
        let locking = app.buttons["onboarding.locking.continue"]
        if locking.waitForExistence(timeout: 3) { locking.tap() } // Immediately and Standard length are the defaults.
    }
    @MainActor private func acknowledgeNoReset(_ app: XCUIApplication) {
        let toggle = app.switches["setup.acknowledge"]
        if toggle.waitForExistence(timeout: 3), toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
    }
    @MainActor private func dismissFirstBackupSetup(_ app: XCUIApplication) {
        let notNow = app.buttons["onboarding.backup.notNow"]
        if notNow.waitForExistence(timeout: 5) { notNow.tap() }
    }
    @MainActor private func launch(autoLock: Int = -1) throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA") == true else {
            throw XCTSkip("Requires the isolated encrypted-release QA simulator and separately installed release app")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard"]
        // Values other than an offered option fall back to Immediately (ADR-032).
        if autoLock >= 0 { app.launchArguments += ["-autoLockTimeout", String(autoLock)] }
        app.launch()
        beginOnboarding(app)
        let setup = app.secureTextFields["setup.password"]
        if setup.waitForExistence(timeout: 8) {
            setup.tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { setup.tap() }
            setup.typeText(owner)
            app.secureTextFields["setup.confirmPassword"].tap(); app.secureTextFields["setup.confirmPassword"].typeText(owner)
            acknowledgeNoReset(app); app.buttons["setup.save"].tap()
            dismissFirstBackupSetup(app)
        } else {
            unlock(app, password: owner)
            if !app.tabBars.buttons["Albums"].waitForExistence(timeout: 4), app.secureTextFields["Enter password"].exists {
                unlock(app, password: changed)
                if !app.tabBars.buttons["Albums"].waitForExistence(timeout: 4),
                   ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA Reset") == true {
                    // Reuse only the known public result of this destructive fixture's previous run.
                    let fresh = "PUBLIC-after-erase-password"
                    unlock(app, password: fresh)
                    XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15), app.debugDescription)
                    changePassword(app, from: fresh, to: owner)
                } else {
                    XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15), app.debugDescription)
                    changePassword(app, from: changed, to: owner)
                }
            }
        }
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.security"].tap()
        // Auto-lock and passcode length are choices now, defaulting to the most private.
        XCTAssertTrue(app.buttons["settings.autoLock"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["settings.passcodeLength"].exists, app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Library"].tap()
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
        app.tabBars.buttons["Library"].tap()
        app.buttons["library.add"].tap(); app.buttons["import.photos"].tap()
        let image = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10)); image.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        if app.buttons["import.complete.done"].waitForExistence(timeout: 5) { app.buttons["import.complete.done"].tap() }
        if app.buttons["library.filter.photos"].waitForExistence(timeout: 5) { app.buttons["library.filter.photos"].tap() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "photos.preview").firstMatch.waitForExistence(timeout: 10))
        capture(app, "Store - Photos")
        app.tabBars.buttons["Library"].tap(); app.buttons["library.filter.videos"].tap(); app.buttons["videos.import"].tap(); app.buttons["import.photos"].tap()
        let video = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Video,")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10)); video.tap(); app.buttons["Add"].tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 20) { app.alerts.buttons["OK"].tap() }
        if app.buttons["import.complete.done"].waitForExistence(timeout: 5) { app.buttons["import.complete.done"].tap() }
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
        app.tabBars.buttons["Library"].tap(); app.tabBars.buttons["Albums"].tap()
        func album(_ name: String) {
            if !app.descendants(matching: .any).matching(identifier: name).firstMatch.exists {
                app.buttons["album.create"].tap(); app.textFields["album.name"].tap(); app.textFields["album.name"].typeText(name)
                app.buttons["album.save"].tap()
            }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: name).firstMatch.waitForExistence(timeout: 10)); app.descendants(matching: .any).matching(identifier: name).firstMatch.tap()
            if app.buttons["album.unlock.inherited"].waitForExistence(timeout: 1) { app.buttons["album.unlock.inherited"].tap() }
            let locked = app.secureTextFields["album.unlock.password"]
            if locked.exists {
                replace(locked, with: "PUBLIC-album-password")
                app.buttons["album.unlock.submit"].tap()
            }
        }
        album("Trips"); album("Weekend")
        app.buttons["album.actions"].tap(); app.buttons["Album Security"].tap()
        app.buttons["Album password"].tap()
        app.secureTextFields["album.password"].tap(); app.secureTextFields["album.password"].typeText("PUBLIC-album-password")
        app.secureTextFields["album.password.confirm"].tap(); app.secureTextFields["album.password.confirm"].typeText("PUBLIC-album-password")
        app.buttons["album.save"].tap()
        XCTAssertTrue(app.secureTextFields["album.unlock.password"].waitForExistence(timeout: 10))
        capture(app, "Store - Protected album")
        app.secureTextFields["album.unlock.password"].tap(); app.secureTextFields["album.unlock.password"].typeText("PUBLIC-album-password")
        app.buttons["album.unlock.submit"].tap(); XCTAssertTrue(app.buttons["album.create"].waitForExistence(timeout: 10))
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
            app.tabBars.buttons["Library"].tap(); app.buttons["Notes"].firstMatch.tap()
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
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15))
    }

    @MainActor func testRepeatedInProcessLockReopensEncryptedLibrary() throws {
        let app = try launch()
        for _ in 0..<3 {
            app.buttons["Settings"].firstMatch.tap()
            let lock = app.buttons["settings.lock"]; reveal(app, lock); lock.tap()
            let confirm = app.buttons["Log Out"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            unlock(app, password: owner)
            XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertFalse(app.otherElements["library.mount.error"].exists)
        }
    }
    @MainActor func testStoreReadyScreenshots() throws {
        let app = try launch()
        app.buttons["Notes"].firstMatch.tap(); capture(app, "Store - Notes")
        app.tabBars.buttons["Library"].tap(); app.buttons["library.filter.photos"].tap(); capture(app, "Store - Photos")
        app.buttons["library.filter.videos"].tap(); capture(app, "Store - Media")
        app.tabBars.buttons["Albums"].tap()
        app.descendants(matching: .any).matching(identifier: "Trips").firstMatch.tap()
        if app.buttons["album.unlock.inherited"].waitForExistence(timeout: 2) { app.buttons["album.unlock.inherited"].tap() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Weekend").firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "Weekend").firstMatch.tap()
        XCTAssertTrue(app.secureTextFields["album.unlock.password"].waitForExistence(timeout: 10))
        capture(app, "Store - Protected album")
    }
    @MainActor private func openPasscodes(_ app: XCUIApplication) {
        app.buttons["Settings"].firstMatch.tap(); let security = app.buttons["settings.security"]; reveal(app, security); security.tap()
        let passcodes = app.buttons["settings.passcodes"]; XCTAssertTrue(passcodes.waitForExistence(timeout: 5)); passcodes.tap()
    }
    /// Every library changes its own passcode from the same Passcodes screen.
    @MainActor private func changePassword(_ app: XCUIApplication, from current: String, to replacement: String) {
        openPasscodes(app)
        app.buttons["passcodes.change"].tap()
        let old = app.secureTextFields["Current passcode"]
        XCTAssertTrue(old.waitForExistence(timeout: 5)); replace(old, with: current)
        replace(app.secureTextFields["New passcode (6–128 characters)"], with: replacement)
        replace(app.secureTextFields["Confirm passcode"], with: replacement)
        let save = app.buttons["passcodes.change.submit"]; reveal(app, save); save.tap()
        XCTAssertFalse(app.secureTextFields["Current passcode"].waitForExistence(timeout: 8), app.debugDescription)
    }
    /// Adds another library from inside the current one; it opens on the next unlock.
    @MainActor private func addPasscode(_ app: XCUIApplication, _ passcode: String) {
        openPasscodes(app)
        app.buttons["passcodes.add"].tap()
        let field = app.secureTextFields["New passcode (6–128 characters)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); replace(field, with: passcode)
        replace(app.secureTextFields["Confirm passcode"], with: passcode)
        let create = app.buttons["passcodes.add.submit"]; reveal(app, create); create.tap()
        XCTAssertTrue(app.staticTexts["Library created"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Done"].firstMatch.tap()
    }
    @MainActor func testEveryPasscodeOpensItsOwnLibraryWithIdenticalSettings() throws {
        let app = try launch()
        let second = "PUBLIC-release-second-library"
        let marker = String(UUID().uuidString.prefix(8))
        let firstTitle = "First sample " + marker, secondTitle = "Second sample " + marker
        func note(_ title: String) {
            app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
            // The editor initially focuses its body; wait before selecting the title.
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            replace(app.textFields["note.title"], with: title)
            replace(app.textViews["note.content"], with: "Disposable isolated UI fixture")
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 8))
        }
        func passcodeScreenText() -> [String] {
            openPasscodes(app)
            XCTAssertTrue(app.buttons["passcodes.add"].waitForExistence(timeout: 5))
            let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
            for id in ["passcodes.change", "passcodes.timeLock", "passcodes.delete", "passcodes.add"] {
                XCTAssertTrue(app.buttons[id].exists, id)
            }
            for phrase in ["guest", "alternative", "main", "other library", "secondary", "primary"] {
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", phrase)).firstMatch.exists, phrase)
            }
            return labels
        }
        note(firstTitle)
        let firstScreen = passcodeScreenText()
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15))
        addPasscode(app, second)
        app.terminate(); app.launch(); unlock(app, password: second)
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts[firstTitle].exists)
        note(secondTitle)
        XCTAssertEqual(passcodeScreenText(), firstScreen, "Passcodes renders the same in every library")
        app.buttons["Settings"].firstMatch.tap()
        let security = app.buttons["settings.security"]; reveal(app, security); security.tap()
        app.buttons["settings.faceID"].tap()
        XCTAssertTrue(app.staticTexts["Off for this library"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "assigned")).firstMatch.exists)
        capture(app, "Second library security has ordinary controls")
        // A passcode already in use is rejected generically and never opens another library.
        addPasscodeExpectingRejection(app, owner)
        app.terminate(); app.launch(); unlock(app, password: second)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[secondTitle].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[firstTitle].exists)
        app.terminate(); app.launch(); unlock(app, password: owner)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[firstTitle].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[secondTitle].exists)
    }

    @MainActor private func addPasscodeExpectingRejection(_ app: XCUIApplication, _ passcode: String) {
        openPasscodes(app)
        app.buttons["passcodes.add"].tap()
        replace(app.secureTextFields["New passcode (6–128 characters)"], with: passcode)
        replace(app.secureTextFields["Confirm passcode"], with: passcode)
        let create = app.buttons["passcodes.add.submit"]; reveal(app, create); create.tap()
        XCTAssertTrue(app.staticTexts["This passcode can’t be used"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "already")).firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Albums"].exists || app.buttons["Cancel"].exists)
        app.buttons["Cancel"].firstMatch.tap()
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
            // The editor initially focuses its body; wait before selecting the title.
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
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
        addPasscode(app, secondary)
        app.terminate(); app.launch(); unlock(app, password: secondary)
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 15))
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
        beginOnboarding(app)
        let setup = app.secureTextFields["setup.password"]
        XCTAssertTrue(setup.waitForExistence(timeout: 30), app.debugDescription)
        replace(setup, with: fresh)
        replace(app.secureTextFields["setup.confirmPassword"], with: fresh)
        acknowledgeNoReset(app); app.buttons["setup.save"].tap()
        dismissFirstBackupSetup(app)
        XCTAssertTrue(app.tabBars.buttons["Albums"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["PUBLIC primary before erase"].exists)
        XCTAssertFalse(app.staticTexts["PUBLIC separate before erase"].exists)
        note("PUBLIC after erase")
        openPasscodes(app)
        XCTAssertTrue(app.buttons["passcodes.add"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["vault.faceID.unlock"].exists)
        for old in [owner, secondary] {
            unlock(app, password: old)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "password.error").firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(app.tabBars.buttons["Albums"].exists)
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
        beginOnboarding(app)
        let first = app.secureTextFields["setup.password"]
        let confirmation = app.secureTextFields["setup.confirmPassword"]
        let use = app.buttons["setup.confirmEntered"], save = app.buttons["setup.save"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        acknowledgeNoReset(app)
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
        acknowledgeNoReset(app)
        confirmation.tap(); confirmation.typeText("\n")
        dismissFirstBackupSetup(app)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Notes"].firstMatch.tap(); app.navigationBars.buttons["New"].tap()
        replace(app.textFields["note.title"], with: "PUBLIC confirmation sample")
        replace(app.textViews["note.content"], with: "PUBLIC note survives the explicit confirmation password change")
        app.navigationBars.buttons["Done"].tap()
        let currentField = "Current passcode", newField = "New passcode (6–128 characters)", confirmField = "Confirm passcode"
        func openChange() {
            openPasscodes(app)
            app.buttons["passcodes.change"].tap()
            XCTAssertTrue(app.secureTextFields[currentField].waitForExistence(timeout: 8))
        }
        func fillChange() {
            replace(app.secureTextFields[currentField], with: original)
            replace(app.secureTextFields[newField], with: replacement)
            let confirm = app.secureTextFields[confirmField]
            XCTAssertEqual(confirm.value as? String, confirm.placeholderValue)
            replace(confirm, with: "PUBLIC another manual mismatch")
            XCTAssertFalse(app.buttons["passcodes.change.submit"].isEnabled)
            let button = app.buttons["passcodes.change.useEntered"]
            reach(button); button.tap()
            XCTAssertTrue(app.buttons["passcodes.change.submit"].isEnabled)
            XCTAssertTrue(app.secureTextFields[currentField].exists, "Confirmation must not submit")
        }
        openChange(); fillChange()
        replace(app.secureTextFields[newField], with: replacement + "x")
        XCTAssertFalse(app.buttons["passcodes.change.submit"].isEnabled)
        XCUIDevice.shared.press(.home); app.activate(); unlock(app, password: original)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15))
        openChange()
        for id in [currentField, newField, confirmField] {
            let field = app.secureTextFields[id]
            XCTAssertEqual(field.value as? String, field.placeholderValue)
        }
        fillChange()
        let change = app.buttons["passcodes.change.submit"]; reach(change); change.tap()
        XCTAssertFalse(app.secureTextFields[currentField].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 20))
        app.terminate(); app.launch(); unlock(app, password: original)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "password.error").firstMatch.waitForExistence(timeout: 8))
        unlock(app, password: replacement)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC confirmation sample"].waitForExistence(timeout: 8))
        openPasscodes(app); app.buttons["passcodes.add"].tap()
        let secondary = "PUBLIC-confirmation*._-second"
        replace(app.secureTextFields[newField], with: secondary)
        XCTAssertFalse(app.buttons["passcodes.add.submit"].isEnabled)
        let addUse = app.buttons["passcodes.add.useEntered"]; reach(addUse); addUse.tap()
        XCTAssertTrue(app.buttons["passcodes.add.submit"].isEnabled)
        app.buttons["passcodes.add.submit"].tap()
        XCTAssertTrue(app.staticTexts["Library created"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); unlock(app, password: secondary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["PUBLIC confirmation sample"].exists)
    }

    @MainActor func testEveryLibraryChangesOnlyItsOwnPasscodeAndCollisionsAreGeneric() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA Confirmation") == true else {
            throw XCTSkip("Requires the retained public confirmation fixture")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard"]
        let first = "PUBLIC-confirmation*._-changed"
        let second = "PUBLIC-confirmation*._-second"
        let replacement = "PUBLIC-confirmation*._-second-new"
        app.launch(); unlock(app, password: second)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15))
        // Changing to another library's passcode is a generic rejection with a wait.
        openPasscodes(app); app.buttons["passcodes.change"].tap()
        replace(app.secureTextFields["Current passcode"], with: second)
        replace(app.secureTextFields["New passcode (6–128 characters)"], with: first)
        replace(app.secureTextFields["Confirm passcode"], with: first)
        app.buttons["passcodes.change.submit"].tap()
        XCTAssertTrue(app.staticTexts["This passcode can’t be used"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Try again in")).firstMatch.exists)
        app.buttons["Cancel"].firstMatch.tap()
        app.terminate(); app.launch(); unlock(app, password: second)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["PUBLIC confirmation sample"].exists, "The rejection never opened another library")
        // The second library changes its own passcode with only its own passcode.
        sleep(31)
        changePassword(app, from: second, to: replacement)
        app.terminate(); app.launch(); unlock(app, password: replacement)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["PUBLIC confirmation sample"].exists)
        changePassword(app, from: replacement, to: second)
        app.terminate(); app.launch(); unlock(app, password: first)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC confirmation sample"].waitForExistence(timeout: 8))
    }

    @MainActor func testVaultPasswordBackupAndPrivateReminderSettingsStayWithinSelectedLibrary() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("WagLock Encrypted Release QA Confirmation") == true else {
            throw XCTSkip("Requires the retained public confirmation fixture")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.d2sci.waglock")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard"]
        let primary = "PUBLIC-confirmation*._-changed", secondary = "PUBLIC-confirmation*._-alternative"
        func reach(_ element: XCUIElement, towardTop: Bool = false) {
            let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                : app.tables.firstMatch.exists ? app.tables.firstMatch
                : app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app
            for phase in 0..<2 {
                for _ in 0..<6 {
                    if element.exists && element.isHittable { return }
                    let down = element.exists ? element.frame.minY < scroll.frame.minY : (phase == 0 ? towardTop : !towardTop)
                    if down { scroll.swipeDown() } else { scroll.swipeUp() }
                }
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        func openSettings() {
            app.buttons["Settings"].firstMatch.tap()
        }
        func openReminders() {
            let button = app.buttons["settings.backupReminders"]; reach(button); button.tap()
            XCTAssertTrue(app.buttons["backup.reminder.frequency"].waitForExistence(timeout: 8))
        }
        func frequency(_ expected: String) {
            let picker = app.buttons["backup.reminder.frequency"]
            XCTAssertTrue(NSPredicate(format: "value == %@", expected).evaluate(with: picker), app.debugDescription)
        }
        func setFrequency(_ value: String) {
            let picker = app.buttons["backup.reminder.frequency"]
            if picker.value as? String == value { return }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: picker)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons[value].waitForExistence(timeout: 5)); app.buttons[value].tap()
            frequency(value)
        }
        func openBackup() {
            let button = app.buttons["settings.backup"]; reach(button); button.tap()
            let toggle = app.switches["backup.useVaultPassword"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 8))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            XCTAssertTrue(app.secureTextFields["backup.vaultPassword"].waitForExistence(timeout: 5))
        }
        func prepare(_ password: String, expectSuccess: Bool) {
            let field = app.secureTextFields["backup.vaultPassword"]
            reach(field, towardTop: true); replace(field, with: password + "\n")
            let consent = app.switches["backup.reuseConsent"]
            let create = app.buttons["backup.create"]
            reach(consent)
            if consent.value as? String == "0" {
                reach(create); XCTAssertFalse(create.isEnabled)
                reach(consent, towardTop: true); consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            reach(create); XCTAssertTrue(create.isEnabled); create.tap()
            if expectSuccess {
                XCTAssertTrue(app.buttons["backup.save"].waitForExistence(timeout: 45), app.debugDescription)
                let filename = app.textFields["backup.filename"]; reach(filename)
                let suggested = filename.value as? String ?? ""
                XCTAssertNotNil(suggested.range(of: "^WagLock-Backup-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-[0-9]{3}Z$", options: .regularExpression), suggested)
            }
            else {
                let error = app.staticTexts["backup.error"]; reach(error)
                XCTAssertTrue(error.exists)
                XCTAssertFalse(app.buttons["backup.save"].exists)
            }
        }
        app.launch(); unlock(app, password: primary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); openSettings(); openReminders()
        setFrequency("Monthly"); XCTAssertFalse(app.staticTexts["Last saved to Files"].exists)
        setFrequency("Weekly")
        app.terminate(); app.launch(); unlock(app, password: primary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); openSettings(); openReminders()
        frequency("Weekly"); setFrequency("Off")
        app.navigationBars.buttons.element(boundBy: 0).tap(); openBackup()
        prepare("PUBLIC wrong password", expectSuccess: false)
        prepare(primary, expectSuccess: true)
        app.buttons["backup.filename.clear"].tap()
        XCTAssertFalse(app.buttons["backup.save"].isEnabled)
        replace(app.textFields["backup.filename"], with: "PUBLIC dated backup")
        app.textFields["backup.filename"].typeText("\n")
        XCTAssertTrue(app.buttons["backup.save"].isEnabled)
        reach(app.buttons["backup.save"]); app.buttons["backup.save"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        if !cancel.waitForExistence(timeout: 5), app.buttons["Browse"].firstMatch.exists {
            app.buttons["Browse"].firstMatch.tap()
        }
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        else {
            // Native Files can reopen inside On My iPhone with cancellation on its parent.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        XCTAssertFalse(app.staticTexts["backup.saved"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap(); openReminders()
        frequency("Off"); XCTAssertFalse(app.staticTexts["Last saved to Files"].exists)
        app.terminate(); app.launch(); unlock(app, password: secondary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); openSettings(); openReminders()
        frequency("Monthly")
        app.navigationBars.buttons.element(boundBy: 0).tap(); openBackup()
        prepare(primary, expectSuccess: false)
        prepare(secondary, expectSuccess: true)
        app.buttons["backup.discard"].tap()
        app.terminate(); app.launch(); unlock(app, password: primary)
        XCTAssertTrue(app.buttons["Notes"].firstMatch.waitForExistence(timeout: 15)); app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["PUBLIC confirmation sample"].waitForExistence(timeout: 8))
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
