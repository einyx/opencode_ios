import XCTest

final class Tier4OfflineUITests: XCTestCase {
    private let serverURL = "https://example.com/failover/Connected"
    private let username = "tier4"
    private let password = "offline-secret"
    private let prompt = "offline prompt boundary"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCarSemanticConfigRejectsBodyTextUntilPhaseChanges() throws {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Ambient Mode"].waitForExistence(timeout: 15), "Ambient Mode tab should be a semantic tab, not an index")
        Tier4DriverSupport.configureSavedHost(in: app, serverURL: serverURL, username: username, password: password)
        XCTAssertEqual(recordValue(app), password, "saved password should be the credential spy value")

        Tier4DriverSupport.tapTestConnection(in: app)
        let checking = NSPredicate(format: "value == %@ OR label == %@", "Checking OpenCode health", "Checking OpenCode health")
        let phase = app.descendants(matching: .any)[Tier4DriverSupport.phaseIdentifier]
        XCTAssertTrue(phase.waitForExistence(timeout: 8), "phase label should exist while health is held")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: Tier4DriverSupport.phaseIdentifier).count, 1)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: checking, object: phase)], timeout: 8), .completed)
        let body = diagnosticBody(app)
        XCTAssertTrue(body.contains("Connected"), "held health body should contain the URL token Connected: \(body)")
        XCTAssertTrue(body.contains("failover"), "held health body should contain failover: \(body)")
        XCTAssertFalse(Tier4DriverSupport.waitForConnected(in: app, timeout: 1), "URL text must not count as connected")
        XCTAssertFalse(Tier4DriverSupport.failedValues.contains(Tier4DriverSupport.phaseValue(in: app)))

        app.descendants(matching: .any)["tier4-release-health-failed"].tap()
        XCTAssertFalse(Tier4DriverSupport.waitForConnected(in: app, timeout: 8))
        XCTAssertEqual(Tier4DriverSupport.phaseValue(in: app), "Connection failed")

        Tier4DriverSupport.tapTestConnection(in: app)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: checking, object: phase)], timeout: 8), .completed)
        XCTAssertFalse(Tier4DriverSupport.waitForConnected(in: app, timeout: 1))
        app.descendants(matching: .any)["tier4-release-health-connected"].tap()
        XCTAssertTrue(Tier4DriverSupport.waitForConnected(in: app, timeout: 8))
        XCTAssertEqual(Tier4DriverSupport.phaseValue(in: app), "Connected")
    }

    @MainActor
    func testSendHoldThenFailureIsNotAccepted() throws {
        let app = launch()
        let source = try sendAndLatchPendingRow(in: app)
        XCTAssertFalse(
            Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: [], sourceIdentifier: source, timeout: 1),
            "optimistic row must not be accepted while prompt is held"
        )
        app.descendants(matching: .any)["tier4-release-send-fail"].tap()
        XCTAssertFalse(Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: [], sourceIdentifier: source, timeout: 8))
        XCTAssertEqual(
            Tier4DriverSupport.userMessageStatus(in: app, identifier: source),
            "failed"
        )
    }

    @MainActor
    func testSendAcceptsOnlyMatchingServerAck() throws {
        let app = launch()
        let source = try sendAndLatchPendingRow(in: app)
        XCTAssertFalse(Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: [], sourceIdentifier: source, timeout: 1))

        app.descendants(matching: .any)["tier4-release-send-http"].tap()
        XCTAssertFalse(Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: [], sourceIdentifier: source, timeout: 1))
        XCTAssertEqual(
            Tier4DriverSupport.userMessageStatus(in: app, identifier: source),
            "pending"
        )

        app.descendants(matching: .any)["tier4-release-send-other"].tap()
        XCTAssertFalse(Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: [], sourceIdentifier: source, timeout: 1))
        XCTAssertEqual(
            Tier4DriverSupport.userMessageStatus(in: app, identifier: source),
            "pending"
        )

        app.descendants(matching: .any)["tier4-release-send-ack"].tap()
        XCTAssertTrue(
            Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: [], sourceIdentifier: source, timeout: 8)
        )
        XCTAssertEqual(
            Tier4DriverSupport.userMessageStatus(in: app, identifier: source),
            "confirmed"
        )
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIER4_OFFLINE_FIXTURE"]
        app.launch()
        return app
    }

    @MainActor
    private func sendAndLatchPendingRow(in app: XCUIApplication) throws -> String {
        Tier4DriverSupport.openChat(in: app)
        let input = app.descendants(matching: .any)["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), "chat-input should exist")
        let existing = Tier4DriverSupport.userMessageIdentifiers(in: app)
        Tier4DriverSupport.replaceText(in: input, with: prompt)
        let send = app.descendants(matching: .any)["chat-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8), "chat-send should exist")
        send.tap()
        guard let source = Tier4DriverSupport.waitForNewUserMessage(in: app, existing: existing, timeout: 8) else {
            XCTFail("optimistic user row should appear")
            return ""
        }
        XCTAssertEqual(Tier4DriverSupport.userMessageStatus(in: app, identifier: source), "pending")
        let statusNodes = app.descendants(matching: .any).matching(identifier: source)
        XCTAssertEqual(statusNodes.count, 1, "source status node must be unique")
        let status = statusNodes.element(boundBy: 0)
        XCTAssertNotEqual(status.label, prompt, "status node must not replace message text")
        XCTAssertNotEqual(status.label, "More", "status node must not replace the actions menu")
        let promptNodes = app.staticTexts.matching(NSPredicate(format: "label == %@", prompt))
        XCTAssertGreaterThan(promptNodes.count, 0, "message text must stay accessible")
        for index in 0..<promptNodes.count {
            XCTAssertNotEqual(promptNodes.element(boundBy: index).identifier, source)
        }
        let menus = app.descendants(matching: .any).matching(identifier: "message-actions")
        XCTAssertEqual(menus.count, 1, "message actions must stay accessible")
        let inputValue = (input.value as? String) ?? ""
        XCTAssertFalse(inputValue.contains(prompt), "composer should be cleared before acceptance")
        return source
    }

    @MainActor
    private func recordValue(_ app: XCUIApplication) -> String {
        let nodes = app.descendants(matching: .any).matching(identifier: "host-credential-record")
        XCTAssertEqual(nodes.count, 1, "current host credential record must be unique")
        guard nodes.count == 1 else { return "" }
        return nodes.element(boundBy: 0).value as? String ?? ""
    }

    @MainActor
    private func diagnosticBody(_ app: XCUIApplication) -> String {
        let nodes = app.staticTexts.matching(identifier: "host-connection-diagnostic")
        XCTAssertEqual(nodes.count, 1, "diagnostic body must be a unique text node")
        guard nodes.count == 1 else { return "" }
        return nodes.element(boundBy: 0).label
    }
}
