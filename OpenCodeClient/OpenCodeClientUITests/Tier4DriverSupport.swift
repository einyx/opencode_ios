import XCTest

enum Tier4DriverSupport {
    static let phaseIdentifier = "host-connection-phase"
    static let userMessagePrefix = "user-message-"
    static let connectedValues = ["Connected", "已连接"]
    static let failedValues = ["Connection failed", "连接失败"]

    @MainActor
    static func configureSavedHost(
        in app: XCUIApplication,
        serverURL: String,
        username: String,
        password: String
    ) {
        openSettings(in: app)
        let currentHost = app.descendants(matching: .any)["settings-current-host"]
        XCTAssertTrue(currentHost.waitForExistence(timeout: 15), "settings-current-host should exist")
        currentHost.tap()

        let addHost = app.descendants(matching: .any)["hosts-add-host"]
        XCTAssertTrue(addHost.waitForExistence(timeout: 15), "hosts-add-host should exist")
        addHost.tap()

        let name = app.descendants(matching: .any)["host-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "host-name should exist")
        replaceText(in: name, with: "Tier4 Host")

        let urlField = app.descendants(matching: .any)["host-server-url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10), "host-server-url should exist")
        replaceText(in: urlField, with: serverURL)

        if !username.isEmpty {
            let usernameField = reveal(identifier: "host-username", anchor: "host-server-url", in: app)
            XCTAssertEqual(
                app.descendants(matching: .any).matching(identifier: "host-username").count,
                1,
                "host username field should be a single field"
            )
            XCTAssertTrue(usernameField.waitForExistence(timeout: 10), "host username field should exist")
            XCTAssertTrue(usernameField.isHittable, "host username field should be hittable")
            replaceText(in: usernameField, with: username)
        }
        if !password.isEmpty {
            // The password field sits below the keyboard and is not hittable
            // while it is covered, but it is in the tree: tapping it scrolls
            // it into view.
            let passwordField = secureField(identifier: "host-password", in: app)
            replaceText(in: passwordField, with: password)
        }

        let saves = app.buttons.matching(identifier: "host-save")
        XCTAssertEqual(saves.count, 1, "host-save should be exactly one Button, not the navigation bar container")
        let save = saves.element(boundBy: 0)
        XCTAssertTrue(save.waitForExistence(timeout: 10), "host-save Button should exist")
        XCTAssertTrue(save.isEnabled, "host-save should be enabled after required fields")
        XCTAssertTrue(save.isHittable, "host-save Button should be hittable")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), "host editor should dismiss after saving")
        let passwordPrompt = app.sheets["Save Password?"]
        if passwordPrompt.waitForExistence(timeout: 3) {
            let notNow = passwordPrompt.buttons.matching(NSPredicate(format: "label IN %@", ["Not Now", "以后再说", "暂不"]))
            XCTAssertEqual(notNow.count, 1, "password prompt should expose one decline button")
            notNow.element(boundBy: 0).tap()
            XCTAssertTrue(passwordPrompt.waitForNonExistence(timeout: 5))
        }

        let back = navigationButton(in: app, labels: ["Settings", "设置", "Back", "返回"])
        XCTAssertTrue(back.waitForExistence(timeout: 8), "Hosts should expose its Settings back button: \(app.debugDescription)")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: back)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 8), .completed, "Settings back button should be hittable: \(app.debugDescription)")
        back.tap()
        XCTAssertTrue(app.buttons["settings-current-host"].waitForExistence(timeout: 10), "should return to Settings: \(app.debugDescription)")
    }

    @MainActor
    static func tapTestConnection(in app: XCUIApplication) {
        let testConnection = app.descendants(matching: .any)["settings-test-connection"]
        XCTAssertTrue(testConnection.waitForExistence(timeout: 10), "settings-test-connection should exist")
        testConnection.tap()
    }

    @MainActor
    static func openSettings(in app: XCUIApplication) {
        if app.descendants(matching: .any)["settings-current-host"].exists { return }
        openSemanticTab(in: app, labels: ["Settings", "设置"], fallbackIdentifier: "ipad-settings-button")
        XCTAssertTrue(app.descendants(matching: .any)["settings-current-host"].waitForExistence(timeout: 15), "settings tab should open")
    }

    @MainActor
    static func openChat(in app: XCUIApplication) {
        if app.descendants(matching: .any)["chat-input"].exists { return }
        openSemanticTab(in: app, labels: ["Chat", "聊天"], fallbackIdentifier: nil)
        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 20), "chat tab should open")
    }

    @MainActor
    static func openSemanticTab(in app: XCUIApplication, labels: [String], fallbackIdentifier: String?) {
        let tabBar = app.tabBars.element(boundBy: 0)
        if tabBar.waitForExistence(timeout: 5) {
            XCTAssertEqual(app.tabBars.count, 1)
            let matches = tabBar.buttons.matching(NSPredicate(format: "label IN %@", labels))
            let match = matches.element(boundBy: 0)
            if match.exists {
                XCTAssertEqual(matches.count, 1)
                match.tap()
                return
            }
        }
        if let fallbackIdentifier {
            let fallback = app.descendants(matching: .any)[fallbackIdentifier]
            if fallback.waitForExistence(timeout: 5) {
                fallback.tap()
            }
        }
    }

    @MainActor
    static func textField(in app: XCUIApplication, labels: [String]) -> XCUIElement {
        let matches = app.textFields.matching(NSPredicate(format: "label IN %@", labels))
        XCTAssertEqual(matches.count, 1)
        return matches.element(boundBy: 0)
    }

    @MainActor
    static func navigationButton(in app: XCUIApplication, labels: [String]) -> XCUIElement {
        let matches = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", labels))
        XCTAssertLessThanOrEqual(matches.count, 1)
        return matches.element(boundBy: 0)
    }

    @MainActor
    static func phaseValue(in app: XCUIApplication) -> String {
        let phase = app.descendants(matching: .any)[phaseIdentifier]
        guard phase.exists else { return "" }
        if let value = phase.value as? String, !value.isEmpty, value != phaseIdentifier {
            return value
        }
        return phase.label
    }

    @MainActor
    static func waitForConnected(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let phase = phaseValue(in: app)
            if failedValues.contains(phase) { return false }
            if connectedValues.contains(phase) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    static func userMessageIdentifiers(in app: XCUIApplication) -> Set<String> {
        let nodes = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", userMessagePrefix))
        var ids: Set<String> = []
        for index in 0..<nodes.count {
            let identifier = nodes.element(boundBy: index).identifier
            if identifier.hasPrefix(userMessagePrefix) {
                ids.insert(identifier)
            }
        }
        return ids
    }

    @MainActor
    static let sourceStatuses: Set<String> = ["pending", "failed", "confirmed"]

    static func userMessageStatus(in app: XCUIApplication, identifier: String) -> String {
        let nodes = app.descendants(matching: .any).matching(identifier: identifier)
        guard nodes.count == 1 else { return "" }
        let node = nodes.element(boundBy: 0)
        let value = (node.value as? String) ?? ""
        if sourceStatuses.contains(value) { return value }
        if sourceStatuses.contains(node.label) { return node.label }
        return ""
    }

    /// A secure text field.
    ///
    /// A secure field is not matched by an identifier predicate on `.any`, so
    /// it is looked up by its own type.
    @MainActor
    static func secureField(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let field = app.secureTextFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "secure field \(identifier) should exist")
        return field
    }

    @MainActor
    static func reveal(identifier: String, anchor: String, in app: XCUIApplication, attempts: Int = 4) -> XCUIElement {
        func node() -> XCUIElement? {
            let nodes = app.descendants(matching: .any).matching(identifier: identifier)
            if nodes.count == 1 { return nodes.element(boundBy: 0) }
            // A secure text field is not matched by an identifier predicate on
            // `.any`, so secure fields are looked up by their own type.
            let secure = app.secureTextFields[identifier]
            if secure.exists { return secure }
            return nil
        }
        if let found = node(), found.isHittable { return found }
        // The keyboard covers the lower fields, and a swipe on a form that is
        // covered by the keyboard does not move the content. Dismiss the
        // keyboard before scrolling for a field.
        if app.keyboards.count > 0 {
            app.keyboards.element(boundBy: 0).swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        if let found = node(), found.isHittable { return found }
        if let scroller = editorScroller(in: app, anchor: anchor) {
            for _ in 0..<attempts {
                if let found = node(), found.isHittable { return found }
                scroller.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }
        if let found = node() { return found }
        return app.descendants(matching: .any)[identifier].exists
            ? app.descendants(matching: .any)[identifier]
            : app.secureTextFields[identifier]
    }

    @MainActor
    private static func editorScroller(in app: XCUIApplication, anchor: String) -> XCUIElement? {
        let collections = app.collectionViews
        for index in 0..<collections.count {
            let view = collections.element(boundBy: index)
            if view.descendants(matching: .any).matching(identifier: anchor).count > 0 {
                return view
            }
        }
        let scrolls = app.scrollViews
        for index in 0..<scrolls.count {
            let view = scrolls.element(boundBy: index)
            if view.descendants(matching: .any).matching(identifier: anchor).count > 0 {
                return view
            }
        }
        return nil
    }

    @MainActor
    static func waitForNewUserMessage(in app: XCUIApplication, existing: Set<String>, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fresh = userMessageIdentifiers(in: app).subtracting(existing).sorted()
            if let identifier = fresh.first {
                return identifier
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    static func waitForSourceMessageAccepted(
        in app: XCUIApplication,
        existing: Set<String>,
        sourceIdentifier: String? = nil,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var sourceID = sourceIdentifier
        while Date() < deadline {
            if sourceID == nil {
                sourceID = userMessageIdentifiers(in: app).subtracting(existing).sorted().first
            }
            if let sourceID {
                let status = userMessageStatus(in: app, identifier: sourceID)
                if status == "failed" { return false }
                if status == "confirmed" { return true }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    static func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "element should exist before replacing text")
        element.tap()
        if let value = element.value as? String, !value.isEmpty, value != element.placeholderValue {
            element.press(forDuration: 1.0)
            let selectAll = XCUIApplication().menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            }
        }
        // Typing into a field that has not taken the keyboard yet fails with
        // "Neither element nor any descendant has keyboard focus".
        XCTAssertTrue(
            UITestFieldFocus.focus(element),
            "the field should take the keyboard focus before typing"
        )
        element.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
    }
}
