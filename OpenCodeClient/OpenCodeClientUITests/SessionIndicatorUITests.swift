import XCTest

final class SessionIndicatorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testLightListComposerAndDisconnected() {
        verify(theme: "light")
    }

    @MainActor func testDarkListComposerAndDisconnected() {
        verify(theme: "dark")
    }

    @MainActor private func verify(theme: String) {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_INDICATOR_FIXTURE"]
        app.launchEnvironment["UITEST_FORCE_THEME"] = theme
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["session-row-running"].firstMatch.waitForExistence(timeout: 10))
        for id in ["yellow", "red", "running", "child", "blue"] {
            assertIndicatorCentered(in: app, sessionID: id)
        }
        let toggle = app.buttons["session-toggle-running"]
        XCTAssertEqual(toggle.frame.width, 44, accuracy: 1)
        XCTAssertEqual(toggle.frame.height, 44, accuracy: 1)
        capture("indicator-\(theme)-list")
        app.buttons["indicator-fixture-toggle"].tap()
        XCTAssertTrue(app.staticTexts["composer-activity-text"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["composer-activity-text"].label.isEmpty)
        capture("indicator-\(theme)-composer")
        app.buttons["indicator-fixture-disconnect"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["composer-session-indicator"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Status awaiting sync'")).firstMatch.exists)
        capture("indicator-\(theme)-disconnected")
        app.terminate()
    }

    @MainActor private func assertIndicatorCentered(in app: XCUIApplication, sessionID: String) {
        func element(_ prefix: String) -> XCUIElement {
            app.descendants(matching: .any)["\(prefix)-\(sessionID)"].firstMatch
        }
        let dot = element("session-indicator")
        let title = element("session-title")
        let time = element("session-time")
        XCTAssertTrue(dot.exists && title.exists && time.exists)
        var block = title.frame.union(time.frame)
        let summary = element("session-summary")
        if summary.exists { block = block.union(summary.frame) }
        XCTAssertEqual(dot.frame.midY, block.midY, accuracy: 1.5,
                       "Indicator must center on the entire text block for \(sessionID)")
        XCTAssertLessThan(dot.frame.maxX, title.frame.minX)
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
