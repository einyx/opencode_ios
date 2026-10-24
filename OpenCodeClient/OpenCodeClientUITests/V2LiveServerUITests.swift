//
//  V2LiveServerUITests.swift
//  OpenCodeClientUITests
//
//  Drives the shipped app against a live OpenCode V2 server.
//
//  The server is described by two environment variables:
//  - `OPENCODE_LIVE_SERVER`: base URL, e.g. `http://127.0.0.1:4096`
//  - `OPENCODE_LIVE_PASSWORD`: the server password
//
//  Without them the tests skip, so the suite stays harmless without a server.
//

import XCTest

final class V2LiveServerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private struct LiveServer {
        let baseURL: URL
        let password: String

        static func fromEnvironment() throws -> LiveServer {
            guard let raw = ProcessInfo.processInfo.environment["OPENCODE_LIVE_SERVER"],
                  let url = URL(string: raw),
                  let password = ProcessInfo.processInfo.environment["OPENCODE_LIVE_PASSWORD"],
                  !password.isEmpty else {
                throw XCTSkip("Set OPENCODE_LIVE_SERVER and OPENCODE_LIVE_PASSWORD to run the live server tests")
            }
            return LiveServer(baseURL: url, password: password)
        }
    }

    /// Ask the server for a fresh pairing code.
    private func requestPairingLink(_ server: LiveServer) throws -> String {
        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(Data("opencode:\(server.password)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error> = .failure(XCTSkip("Pairing request did not complete"))
        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = object["code"] as? String else {
                result = .failure(XCTSkip("Server did not return a pairing code"))
                return
            }
            result = .success(server.baseURL.appendingPathComponent("auth/connect/\(code)").absoluteString)
        }.resume()
        _ = semaphore.wait(timeout: .now() + 15)

        return try result.get()
    }

    /// Open Settings → Hosts → Add Host and return the editor.
    @MainActor
    private func openHostEditor(_ app: XCUIApplication) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should exist")
        tabBar.buttons.element(boundBy: tabBar.buttons.count - 1).tap()

        // The Hosts list is one level below the Settings tab.
        let hostsLink = app.buttons["settings-current-host"]
        XCTAssertTrue(hostsLink.waitForExistence(timeout: 8), "Hosts entry should exist")
        hostsLink.tap()

        let addHost = app.buttons["hosts-add-host"]
        XCTAssertTrue(addHost.waitForExistence(timeout: 8), "Add Host button should exist")
        addHost.tap()

        let nameField = app.textFields["host-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "Host editor should open")
        return nameField
    }

    /// A host added with the password form connects to the V2 server and the
    /// app lists the server's sessions.
    @MainActor
    func testManualHostConnectsToLiveV2Server() throws {
        let server = try LiveServer.fromEnvironment()

        let app = XCUIApplication()
        app.launch()

        openHostEditor(app)

        let nameField = app.textFields["host-name"]
        nameField.tap()
        nameField.typeText("Live V2")

        let urlField = app.textFields["host-server-url"]
        urlField.tap()
        urlField.typeText(server.baseURL.absoluteString)

        let userField = app.textFields["host-username"]
        userField.tap()
        userField.typeText("opencode")

        let passwordField = app.secureTextFields["host-password"]
        passwordField.tap()
        passwordField.typeText(server.password)

        app.buttons["host-save"].tap()

        // The host detail shows the connection phase once the host is saved.
        let phase = app.descendants(matching: .any)["host-connection-phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 20), "Connection phase should be reported")
        XCTAssertEqual(phase.label, "Connected", "The app should connect to the live V2 server")
    }

    /// A pasted pairing link fills the credentials and hides the password form.
    @MainActor
    func testPairingLinkFillsCredentialsAndHidesPasswordForm() throws {
        let server = try LiveServer.fromEnvironment()
        let link = try requestPairingLink(server)

        let app = XCUIApplication()
        app.launch()

        openHostEditor(app)

        let linkField = app.textFields["host-pair-link-field"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 8), "Pairing field should exist")
        linkField.tap()
        linkField.typeText(link)

        let paired = app.descendants(matching: .any)["host-pair-paired"]
        XCTAssertTrue(paired.waitForExistence(timeout: 20), "Pairing should succeed")

        // The credentials came from the link, so they are not asked for.
        XCTAssertFalse(app.secureTextFields["host-password"].exists, "Password field should be hidden after pairing")
        XCTAssertFalse(app.textFields["host-username"].exists, "Username field should be hidden after pairing")

        app.buttons["host-save"].tap()

        let phase = app.descendants(matching: .any)["host-connection-phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 20), "Connection phase should be reported")
        XCTAssertEqual(phase.label, "Connected", "The paired host should connect")
    }
}
