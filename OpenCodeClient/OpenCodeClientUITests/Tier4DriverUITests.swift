//
//  Tier4DriverUITests.swift
//  OpenCodeClientUITests
//

import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class Tier4DriverUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private lazy var fileConfig: [String: String] = Self.loadFileConfig()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConfigureServerFromEnvironment() throws {
        _ = try requiredServerURL()
        let app = launchApp()
        configureServer(in: app)
    }

    @MainActor
    func testSendPromptFromEnvironment() throws {
        let prompt = try requiredEnv("TIER4_PROMPT")
        let app = launchApp()
        if hasServerURL() {
            configureServer(in: app)
            app.terminate()
            app.launch()
        }
        Tier4DriverSupport.openChat(in: app)
        ensureSessionExists(in: app)

        let input = app.descendants(matching: .any)["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), "chat-input should exist")
        Tier4DriverSupport.replaceText(in: input, with: prompt)

        let send = app.descendants(matching: .any)["chat-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8), "chat-send should exist")
        XCTAssertTrue(send.isEnabled, "chat-send should be enabled after typing prompt")
        let existing = Tier4DriverSupport.userMessageIdentifiers(in: app)
        send.tap()

        let accepted = Tier4DriverSupport.waitForSourceMessageAccepted(in: app, existing: existing, timeout: 30)
        XCTAssertTrue(accepted, "source message should be accepted; phase=\(Tier4DriverSupport.phaseValue(in: app)); alert=\(alertDescription(app)); input=\((input.value as? String) ?? "")")
    }

    @MainActor
    func testAccessibilityObservationSnapshot() throws {
        let app = launchApp()
        let identifiers = [
            "chat-input",
            "chat-send",
            "chat-toolbar-create-session",
            "settings-current-host",
            "settings-test-connection",
            "hosts-add-host",
            "host-server-url",
            "host-password",
            "host-save",
            "host-connection-diagnostic",
        ]

        var lines: [String] = []
        for identifier in identifiers {
            let exists = app.descendants(matching: .any)[identifier].exists
            lines.append("\(identifier)=\(exists)")
        }

        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "tier4_accessibility_observation"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 15), "chat-input should be observable")
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    @MainActor
    private func configureServer(in app: XCUIApplication) {
        Tier4DriverSupport.configureSavedHost(
            in: app,
            serverURL: requiredServerURLOrFail(),
            username: configValue("OPENCODE_USERNAME", "TIER4_USERNAME", "username"),
            password: configValue("OPENCODE_PASSWORD", "TIER4_PASSWORD", "password")
        )
        Tier4DriverSupport.tapTestConnection(in: app)
        XCTAssertTrue(
            Tier4DriverSupport.waitForConnected(in: app, timeout: 30),
            "server should report connected; phase=\(Tier4DriverSupport.phaseValue(in: app)); alert=\(alertDescription(app))"
        )
    }

    @MainActor
    private func ensureSessionExists(in app: XCUIApplication) {
        let input = app.descendants(matching: .any)["chat-input"]
        // New session lives in the session sheet (the chat header only carries
        // view-level controls), so open the sheet before creating one.
        let sessions = app.descendants(matching: .any)["chat-toolbar-session-list"]
        if sessions.waitForExistence(timeout: 10) {
            sessions.tap()
            let create = app.descendants(matching: .any)["chat-toolbar-create-session"]
            if create.waitForExistence(timeout: 6), create.isEnabled {
                create.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(2.0))
            }
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20), "chat-input should exist after creating or selecting a session")
    }

    @MainActor
    private func alertDescription(_ app: XCUIApplication) -> String {
        let alert = app.alerts.firstMatch
        guard alert.exists else { return "" }
        let labels = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        return labels.isEmpty ? alert.label : labels
    }

    private func hasServerURL() -> Bool {
        !configValue("OPENCODE_SERVER_URL", "TIER4_SERVER_URL", "server_url").isEmpty
    }

    private func requiredServerURL() throws -> String {
        guard hasServerURL() else {
            throw XCTSkip("Missing required environment variable: OPENCODE_SERVER_URL or TIER4_SERVER_URL")
        }
        return configValue("OPENCODE_SERVER_URL", "TIER4_SERVER_URL", "server_url")
    }

    private func requiredServerURLOrFail() -> String {
        let value = configValue("OPENCODE_SERVER_URL", "TIER4_SERVER_URL", "server_url")
        XCTAssertFalse(value.isEmpty, "OPENCODE_SERVER_URL or TIER4_SERVER_URL should be set")
        return value
    }

    private func requiredEnv(_ key: String) throws -> String {
        let configKey = key == "TIER4_PROMPT" ? "prompt" : key
        let value = env[key] ?? fileConfig[configKey] ?? ""
        guard !value.isEmpty else {
            throw XCTSkip("Missing required environment variable: \(key)")
        }
        return value
    }

    private func configValue(_ keys: String...) -> String {
        for key in keys {
            if let value = env[key], !value.isEmpty { return value }
            if let value = fileConfig[key], !value.isEmpty { return value }
        }
        return ""
    }

    private static func loadFileConfig() -> [String: String] {
        let url = URL(fileURLWithPath: "/tmp/opencode-ios-tier4-config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.compactMapValues { $0 as? String }
    }
}
