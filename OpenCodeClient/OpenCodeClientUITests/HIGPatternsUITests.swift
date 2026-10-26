import XCTest

final class HIGPatternsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        app.launch()
        return app
    }

    @MainActor
    func testLoadedSessionSearchFindsChildAndCanBeCleared() {
        let app = launch()
        let sessions = app.buttons["chat-toolbar-session-list"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 8))
        sessions.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Child")
        XCTAssertTrue(app.staticTexts["Child Session"].waitForExistence(timeout: 4))
        // The search covers the loaded sessions of both groups, and keeps the
        // ancestors of a match so the path to it stays readable: "Archived
        // Child" matches, so its parent "Archived Session" stays as the row
        // that holds it.
        XCTAssertTrue(app.staticTexts["Archived Child"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Archived Session"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Searches titles in loaded sessions")).firstMatch.exists)
        search.buttons.firstMatch.tap()
        // With the query gone the archived group collapses again, so its rows
        // leave the list.
        XCTAssertTrue(app.staticTexts["Root Session"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Archived Child"].exists)
    }

    @MainActor
    func testHostCancelProtectsTypedDraft() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        let hosts = app.buttons["settings-current-host"]
        XCTAssertTrue(hosts.waitForExistence(timeout: 5))
        hosts.tap()
        let add = app.buttons["hosts-add-host"]
        XCTAssertTrue(add.waitForExistence(timeout: 4))
        add.tap()
        let field = app.textFields["host-name"]
        for _ in 0..<4 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        UITestFieldFocus.type("Unsaved host", into: field)
        app.navigationBars.buttons["Cancel"].tap()
        let keep = app.buttons["Keep Editing"]
        XCTAssertTrue(keep.waitForExistence(timeout: 4))
        keep.tap()
        XCTAssertEqual(field.value as? String, "Unsaved host")
        app.navigationBars.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 4))
    }

    @MainActor
    func testComposerControlsHaveActionLabelsAndMinimumTargets() {
        let app = launch()
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        input.typeText("Draft")
        for (id, label) in [("chat-send", "Send message"), ("chat-toolbar-model", "")] {
            let control = app.buttons[id]
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            if !label.isEmpty { XCTAssertEqual(control.label, label) }
            XCTAssertTrue(control.isHittable)
        }
    }

    @MainActor
    func testModelAndSendShareOneFooterRow() {
        let app = launch()
        let model = app.buttons["chat-toolbar-model"]
        let send = app.buttons["chat-send"]
        XCTAssertTrue(model.waitForExistence(timeout: 8))
        XCTAssertTrue(send.exists)
        XCTAssertEqual(model.frame.midY, send.frame.midY, accuracy: 3,
                       "Model and send should align on the same bottom control row")
        XCTAssertLessThan(model.frame.maxX, send.frame.minX)
    }

    @MainActor
    func testDeleteRequiresConfirmationAndCancelKeepsSession() {
        let app = launch()
        let sessions = app.buttons["chat-toolbar-session-list"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 8))
        sessions.tap()
        let row = app.descendants(matching: .any)["session-row-root-session"]
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let alert = app.alerts["Delete session?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 4))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cannot be undone")).firstMatch.exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
    }

    @MainActor
    func testLargeTextPermissionSheetKeepsCancelReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CLIENT_CAPABILITY_FIXTURE", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let cancel = app.buttons["capability-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        for _ in 0..<8 where !cancel.isHittable { app.swipeUp() }
        XCTAssertTrue(cancel.isHittable)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "hig-permission-accessibility-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
