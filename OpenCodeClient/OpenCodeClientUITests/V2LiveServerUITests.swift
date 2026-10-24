//
//  V2LiveServerUITests.swift
//  OpenCodeClientUITests
//
//  Drives the shipped app against a live OpenCode V2 server.
//
//  The server is described either by environment variables or by a dedicated
//  config file at /tmp/opencode-ios-live-server-config.json with
//  `server_url`, `username` and `password` keys. The file has its own path on
//  purpose: /tmp/opencode-ios-tier4-config.json belongs to the Tier 4
//  fixtures, and writing it here would make those tests read a live server.
//
//  Run it on its own: it saves a real host profile in the app, so the app
//  state has to be reset afterwards or the Tier 4 fixtures inherit it.
//
//    xcrun simctl uninstall <udid> com.grapeot.OpenCodeClient
//
//  Without a server the tests skip, so the suite stays harmless without one.
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
            let config = fileConfig()
            let rawURL = firstNonEmpty(
                ProcessInfo.processInfo.environment["OPENCODE_LIVE_SERVER"],
                config["live_server"],
                config["server_url"]
            )
            let password = firstNonEmpty(
                ProcessInfo.processInfo.environment["OPENCODE_LIVE_PASSWORD"],
                config["live_password"],
                config["password"]
            )
            guard let rawURL,
                  let url = URL(string: rawURL),
                  let password,
                  !password.isEmpty else {
                throw XCTSkip("Set OPENCODE_LIVE_SERVER and OPENCODE_LIVE_PASSWORD, or write /tmp/opencode-ios-live-server-config.json, to run the live server tests")
            }
            return LiveServer(baseURL: url, password: password)
        }

        private static func firstNonEmpty(_ values: String?...) -> String? {
            for value in values {
                if let value, !value.isEmpty { return value }
            }
            return nil
        }

        /// The live server config file.
        private static func fileConfig() -> [String: String] {
            let url = URL(fileURLWithPath: "/tmp/opencode-ios-live-server-config.json")
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return object.compactMapValues { $0 as? String }
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

    /// A host added with the password form connects to the V2 server and the
    /// app reports the connected phase.
    @MainActor
    func testManualHostConnectsToLiveV2Server() throws {
        let server = try LiveServer.fromEnvironment()

        let app = XCUIApplication()
        app.launch()

        Tier4DriverSupport.configureSavedHost(
            in: app,
            serverURL: server.baseURL.absoluteString,
            username: "opencode",
            password: server.password
        )
        Tier4DriverSupport.tapTestConnection(in: app)

        XCTAssertTrue(
            Tier4DriverSupport.waitForConnected(in: app, timeout: 30),
            "server should report connected; phase=\(Tier4DriverSupport.phaseValue(in: app))"
        )
    }

    /// A pasted pairing link fills the credentials, hides the password form,
    /// and the paired host connects.
    @MainActor
    func testPairingLinkFillsCredentialsAndHidesPasswordForm() throws {
        let server = try LiveServer.fromEnvironment()
        let link = try requestPairingLink(server)

        let app = XCUIApplication()
        app.launch()

        Tier4DriverSupport.openSettings(in: app)
        let currentHost = app.descendants(matching: .any)["settings-current-host"]
        XCTAssertTrue(currentHost.waitForExistence(timeout: 15), "settings-current-host should exist")
        currentHost.tap()

        let addHost = app.descendants(matching: .any)["hosts-add-host"]
        XCTAssertTrue(addHost.waitForExistence(timeout: 15), "hosts-add-host should exist")
        addHost.tap()

        let name = app.descendants(matching: .any)["host-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "host-name should exist")
        Tier4DriverSupport.replaceText(in: name, with: "Live V2 paired")

        let linkField = app.descendants(matching: .any)["host-pair-link-field"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 10), "host-pair-link-field should exist")
        Tier4DriverSupport.replaceText(in: linkField, with: link)

        let paired = app.descendants(matching: .any)["host-pair-paired"]
        XCTAssertTrue(paired.waitForExistence(timeout: 20), "pairing should succeed")

        // The credentials came from the link, so they are not asked for.
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "host-password").count > 0,
            "password field should be hidden after pairing"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "host-username").count > 0,
            "username field should be hidden after pairing"
        )

        let save = app.buttons.matching(identifier: "host-save")
        XCTAssertEqual(save.count, 1, "host-save should be exactly one Button")
        XCTAssertTrue(save.element(boundBy: 0).waitForExistence(timeout: 10), "host-save Button should exist")
        save.element(boundBy: 0).tap()
        XCTAssertTrue(save.element(boundBy: 0).waitForNonExistence(timeout: 10), "host editor should dismiss after saving")

        let back = Tier4DriverSupport.navigationButton(in: app, labels: ["Settings", "设置", "Back", "返回"])
        XCTAssertTrue(back.waitForExistence(timeout: 8), "Hosts should expose its Settings back button")
        back.tap()
        XCTAssertTrue(app.buttons["settings-current-host"].waitForExistence(timeout: 10), "should return to Settings")

        Tier4DriverSupport.tapTestConnection(in: app)
        XCTAssertTrue(
            Tier4DriverSupport.waitForConnected(in: app, timeout: 30),
            "paired host should report connected; phase=\(Tier4DriverSupport.phaseValue(in: app))"
        )
    }
}
