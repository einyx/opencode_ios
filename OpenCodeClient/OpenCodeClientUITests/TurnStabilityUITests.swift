import XCTest

final class TurnStabilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testExpandedToolsStayExpandedWhenPartAndStepAppend() {
        let app = launch(mode: "append")
        // Every tool call is its own row now — the merged group row is gone.
        // The fixture reuses the part id across two messages, so pin the first.
        let tools = app.descendants(matching: .any)["toolcard.detail.p1"].firstMatch
        let thinking = app.descendants(matching: .any)["message-thinking-card"]
        XCTAssertTrue(tools.waitForExistence(timeout: 12))
        XCTAssertTrue(thinking.waitForExistence(timeout: 8))
        tools.tap()
        thinking.tap()
        assertExpanded(tools)
        assertExpanded(thinking)
        XCTAssertTrue(label("W09_TOOL_P1", in: app).waitForExistence(timeout: 6))
        XCTAssertTrue(label("W09_THINK_OLD", in: app).waitForExistence(timeout: 6))

        app.buttons["w09-turn-append-part"].tap()
        assertExpanded(tools)
        assertExpanded(thinking)
        XCTAssertTrue(label("W09_TOOL_P1", in: app).waitForExistence(timeout: 6))
        XCTAssertTrue(label("W09_TOOL_P2", in: app).waitForExistence(timeout: 6))
        XCTAssertTrue(label("W09_THINK_OLD", in: app).exists)

        app.buttons["w09-turn-append-step"].tap()
        assertExpanded(tools)
        assertExpanded(thinking)
        XCTAssertTrue(label("W09_TOOL_P1", in: app).exists)
        XCTAssertTrue(label("W09_TOOL_P2", in: app).exists)
        XCTAssertTrue(label("W09_TOOL_M2", in: app).waitForExistence(timeout: 6))
        XCTAssertTrue(label("W09_THINK_OLD", in: app).exists)
    }

    @MainActor
    func testLaterStepErrorSpeechAndFooterAreVisible() {
        let app = launch(mode: "metadata")
        XCTAssertTrue(label("W09_SPEECH_M1", in: app).waitForExistence(timeout: 12))
        XCTAssertTrue(label("W09_SPEECH_M2", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(label("W09_ERR_M1", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(label("W09_ERR_M2", in: app).waitForExistence(timeout: 8))
        let footer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "w09/step-two")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 8))
        XCTAssertTrue(footer.label.contains("42 t/s"), footer.label)
        XCTAssertTrue(footer.label.contains("5.0 t/s decoding"), footer.label)
        XCTAssertFalse(label("w09/step-one", in: app).exists)
        XCTAssertFalse(label("99 t/s", in: app).exists)
        XCTAssertFalse(label("20 t/s decoding", in: app).exists)

        let menu = app.buttons["message-actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()
        app.buttons["Select Text"].tap()
        let selection = app.textViews["message-text-selection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 6))
        let copied = selection.value as? String ?? selection.label
        XCTAssertTrue(copied.contains("W09_SPEECH_M1"))
        XCTAssertTrue(copied.contains("W09_SPEECH_M2"))
        app.buttons["Done"].tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()
        app.buttons["Fork from here"].tap()
        XCTAssertTrue(label("W09_FORK_m1", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(label("W09_FORK_m2", in: app).exists)
    }

    @MainActor
    func testNoModelLaterStepDoesNotBorrowFirstModel() {
        let app = launch(mode: "nomodel")
        XCTAssertTrue(label("W09_SPEECH_M2", in: app).waitForExistence(timeout: 12))
        XCTAssertTrue(label("W09_ERR_M1", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(label("W09_ERR_M2", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["message-actions"].waitForExistence(timeout: 6))
        XCTAssertFalse(label("w09/step-one", in: app).exists)
        XCTAssertFalse(label("W09_SPEECH_M1", in: app).exists)
    }

    @MainActor
    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TURN_STABILITY_FIXTURE"]
        app.launchEnvironment = ["UITEST_TURN_STABILITY_MODE": mode]
        app.launch()
        return app
    }

    @MainActor
    private func assertExpanded(_ element: XCUIElement) {
        // The UI-test fixture pins English, so the toggle reports itself in
        // English. Accept either language: the assertion is about the state,
        // not about the wording.
        let value = element.value as? String
        XCTAssertTrue(value == "Expanded" || value == "已展开", "expanded toggle reported \(value ?? "nil")")
    }

    @MainActor
    private func label(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS %@", text)
        ).firstMatch
    }
}
