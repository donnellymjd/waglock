import XCTest

/// Seed the disposable simulator's Photos library with the app-icon PNG before this test.
final class ExportLifecycleUITests: XCTestCase {
    @MainActor
    func testPhotoImportShareCancellationAndBackgroundRevocation() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Vaultito Import QA") == true else {
            throw XCTSkip("Requires the explicitly seeded disposable Vaultito Import QA simulator; never select a real photo library.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-waglock.passwordKeyboard", "fullKeyboard", "-autoLockTimeout", "-1"]
        app.launch()
        let field = app.secureTextFields["Enter password"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("album-ui-test-password\n")
        let openImport = app.buttons["photos.import"]
        XCTAssertTrue(openImport.waitForExistence(timeout: 15))
        openImport.tap()
        app.buttons["import.photos"].tap()
        let cell = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 15), app.debugDescription)
        cell.tap()
        app.buttons["Add"].tap()
        let imported = app.alerts.buttons["OK"]
        if imported.waitForExistence(timeout: 20) { imported.tap() }
        let preview = app.descendants(matching: .any).matching(identifier: "photos.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        preview.tap()
        let share = app.buttons["photo.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        func awaitShare() {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch.waitForExistence(timeout: 15))
        }
        func cancelShare() {
            // The remote activity sheet exposes unstable Close elements to XCTest.
            // On this iPhone QA destination, dismiss using the visible header close control.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.115)).tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: share)
            wait(for: [ready], timeout: 10)
        }
        share.tap()
        awaitShare()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Session-bound export of synthetic app icon"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        cancelShare()
        share.tap()
        awaitShare()
        XCUIDevice.shared.press(.home)
        let backgrounded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }, object: nil)
        wait(for: [backgrounded], timeout: 10)
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        let oldSheetGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch)
        wait(for: [oldSheetGone], timeout: 10)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let login = app.secureTextFields["Enter password"]
            return (share.exists && share.isHittable) || (preview.exists && preview.isHittable)
                || (login.exists && login.isHittable)
        }, object: nil)
        if XCTWaiter.wait(for: [settled], timeout: 10) != .completed {
            let failure = XCTAttachment(screenshot: app.screenshot())
            failure.name = "Share resume did not settle"
            failure.lifetime = .keepAlways
            add(failure)
            XCTFail("No accessible preview or login after share revocation: \(app.debugDescription)")
            return
        }
        // The app may close a presented preview during privacy suspension; reopen from its normal UI.
        if !share.isHittable {
            let login = app.secureTextFields["Enter password"]
            if login.exists { login.tap(); login.typeText("album-ui-test-password\n") }
            XCTAssertTrue(preview.waitForExistence(timeout: 10), app.debugDescription)
            preview.tap()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 10), app.debugDescription)
        share.tap()
        awaitShare()
        cancelShare()
    }
}
