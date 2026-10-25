//
//  ToolCardsUITests.swift
//  OpenCodeClientUITests
//
//  UX test for the "tool card render redo": launches with a deterministic injected
//  assistant turn (UITEST_TOOL_CARDS_FIXTURE) and asserts the new rendering:
//  assistant fixture text, file-operation cards (2-column grid), and the merged
//  "N tool calls" disclosure row (expandable). Captures a screenshot for
//  visual QA. Anchored on accessibility identifiers per AGENTS.md (no TextField queries).
//

import XCTest

final class ToolCardsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A previous suite (Tier4Driver) may leave the simulator in landscape;
        // the layout assertions below assume the portrait 2-up grid.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testToolCardsFixtureRendersFileCardsAndToolCallRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE"]
        app.launch()

        // Assistant fixture content.
        let assistantText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Here are the changes I made'")
        ).firstMatch
        XCTAssertTrue(assistantText.waitForExistence(timeout: 12), "fixture assistant text 应可见")

        let readCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'toolcard.read.'")
        let writeCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'toolcard.write.'")
        let readCards = app.descendants(matching: .any).matching(readCardPredicate)
        let writeCards = app.descendants(matching: .any).matching(writeCardPredicate)

        // The chat scroll view auto-scrolls to the bottom on launch, so the
        // file-card grid (top of the assistant turn) is un-materialized while
        // the tool rows (bottom) are visible. Lazy cells only materialize
        // inside the viewport — assert each region while it is on screen.

        // Every non-file tool call renders as its own row (no merged
        // "N tool calls" group row any more).
        let bashRow = app.descendants(matching: .any)["toolcard.detail.ap-bash"]
        XCTAssertTrue(bashRow.waitForExistence(timeout: 8), "每个工具调用应渲染成独立的一行")

        // Capture the collapsed state before expanding.
        attachScreenshot(named: "oc_toolcards_collapsed")

        // Scroll up (swipe down) until the file-card grid enters the viewport.
        var scrolled = 0
        while !(readCards.firstMatch.exists || writeCards.firstMatch.exists) && scrolled < 5 {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1.0)
            scrolled += 1
        }
        XCTAssertTrue(readCards.firstMatch.waitForExistence(timeout: 4), "至少一个 toolcard.read.* 读文件卡应渲染")
        XCTAssertTrue(writeCards.firstMatch.waitForExistence(timeout: 4), "至少一个 toolcard.write.* 写文件卡应渲染")

        // Scroll back down to the tool row and expand it.
        while !bashRow.firstMatch.exists && scrolled > 0 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.0)
            scrolled -= 1
        }
        if !bashRow.firstMatch.isHittable {
            app.swipeUp()
        }
        bashRow.firstMatch.tap()

        // The command is on the row's header; the output only appears once the
        // row is expanded.
        let revealed = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'All tests passed'")
        ).firstMatch
        XCTAssertTrue(revealed.waitForExistence(timeout: 6), "展开工具行后应出现工具输出（如 'All tests passed'）")

        // Capture the expanded state — primary visual QA artifact.
        attachScreenshot(named: "oc_toolcards")
    }

    @MainActor
    func testExpandedToolDetailsShowErrorBodies() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE"]
        app.launch()

        tapUniqueToolDetail("toolcard.detail.ap-todo-error", in: app)
        let todoError = app.descendants(matching: .any)["toolcard.error.ap-todo-error"]
        XCTAssertTrue(todoError.waitForExistence(timeout: 6))
        XCTAssertTrue(todoError.label.contains("W02_TODOWRITE_ERROR"))

        tapUniqueToolDetail("toolcard.detail.ap-image-error", in: app)
        let imageError = app.descendants(matching: .any)["toolcard.error.ap-image-error"]
        XCTAssertTrue(imageError.waitForExistence(timeout: 6))
        XCTAssertTrue(imageError.label.contains("W02_IMAGE_READ_ERROR"))

        tapUniqueToolDetail("toolcard.detail.ap-todo-success", in: app)
        XCTAssertFalse(app.staticTexts["W02_TODO_SUCCESS_OUTPUT"].waitForExistence(timeout: 1))
    }

    @MainActor
    private func tapUniqueToolDetail(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == %@", identifier)).count, 1)
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
