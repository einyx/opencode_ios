import XCTest

final class SettingsLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConnectedStatusAppearsOnceWithoutRepeatingItsAccessibilityLabel() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let statuses = app.descendants(matching: .any).matching(identifier: "host-connection-phase")
        XCTAssertTrue(statuses.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(statuses.count, 1, "The connection row must render one status, not both layout alternatives")
        XCTAssertEqual(statuses.firstMatch.label, "Connection")
        XCTAssertEqual(statuses.firstMatch.value as? String, "Connected")
    }

    @MainActor
    func testSettingsLightAndDarkScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        for theme in ["Light", "Dark"] {
            let picker = app.descendants(matching: .any)["settings-appearance"]
            for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
            XCTAssertTrue(picker.waitForExistence(timeout: 4))
            picker.buttons[theme].tap()
            for _ in 0..<3 where !app.buttons["settings-current-host"].isHittable { app.swipeDown() }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "settings-\(theme.lowercased())"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testApprovedSettingsNavigationKeepsVoiceAndAdvancedControlsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        // The session-tree fixture has a successful connection. A downstream
        // data-loading error must not be presented as a connection failure.
        let phase = app.descendants(matching: .any)["host-connection-phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 4))
        XCTAssertEqual(phase.value as? String, "Connected")
        XCTAssertFalse(app.staticTexts["settings-connection-error"].exists)

        let voice = app.buttons["settings-input-voice"]
        if !voice.isHittable { app.swipeUp() }
        XCTAssertTrue(voice.waitForExistence(timeout: 4))
        voice.tap()
        XCTAssertTrue(app.switches["settings-voice-first"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["settings-recording-strategy"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let advanced = app.buttons["settings-advanced"]
        if !advanced.isHittable { app.swipeUp() }
        XCTAssertTrue(advanced.waitForExistence(timeout: 4))
        advanced.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-ai-usage-url"].waitForExistence(timeout: 4))
    }
}
