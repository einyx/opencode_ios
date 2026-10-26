import XCTest
import UIKit

/// Real app screens populated by existing, network-free sample-data fixtures.
/// Captures are exported from the result bundle, never from personal sessions.
final class AppStoreScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testCaptureListingScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE", "UITEST_APP_STORE_SCREENSHOTS",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        app.launch()

        let composer = app.textViews["chat-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 12))
        let prompt = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Refactor the API client")).firstMatch
        for _ in 0..<8 where !prompt.isHittable {
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(prompt.isHittable)
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The API client now uses typed responses")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 8))
        capture(app, "01-chat-and-tool-activity")

        app.buttons["chat-toolbar-model"].tap()
        XCTAssertTrue(app.buttons["model-picker-row-openai-gpt-4.1"].waitForExistence(timeout: 5))
        capture(app, "02-models-and-agents")
        app.navigationBars.buttons["Done"].tap()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.exists)
        settings.tap()
        let host = app.buttons["settings-current-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        let statuses = app.descendants(matching: .any).matching(identifier: "host-connection-phase")
        XCTAssertEqual(statuses.count, 1)

        host.tap()
        let addHost = app.buttons["hosts-add-host"]
        XCTAssertTrue(addHost.waitForExistence(timeout: 5))
        for _ in 0..<4 where !addHost.isHittable { app.swipeUp() }
        addHost.tap()
        XCTAssertTrue(app.buttons["host-pair-scan-qr"].waitForExistence(timeout: 5))
        capture(app, "03-connect-your-server")
    }

    @MainActor
    func testCaptureIPadWorkspace() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad screenshot") }
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE", "UITEST_APP_STORE_SCREENSHOTS",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "automatic"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["ipad-workspace-layout"].waitForExistence(timeout: 12))
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The API client now uses typed responses")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 8))
        capture(app, "04-ipad-workspace")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
