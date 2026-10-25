import XCTest

final class ComposerControlsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch(side: String? = nil, speech: Bool = true, images: Bool = true, voiceFirst: Bool = false, draft: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE"]
        app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        if speech { app.launchEnvironment["UITEST_COMPOSER_SPEECH_CONFIGURED"] = "1" }
        if let side { app.launchEnvironment["UITEST_COMPOSER_SIDE"] = side }
        if !images { app.launchEnvironment["UITEST_COMPOSER_HIDE_IMAGE"] = "1" }
        if voiceFirst { app.launchEnvironment["UITEST_COMPOSER_VOICE_FIRST"] = "1" }
        if let draft { app.launchEnvironment["UITEST_COMPOSER_DRAFT"] = draft }
        app.launch()
        XCTAssertTrue(app.textViews["chat-input"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func assertAligned(_ app: XCUIApplication, left: Bool, imageVisible: Bool = true) {
        let mic = app.buttons["speech-transport"]
        let photo = app.buttons["chat-attach-image"]
        let send = app.buttons["chat-send"]
        let input = app.textViews["chat-input"]
        XCTAssertTrue(mic.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(send.exists)
        // The mic is part of the composer action cluster (photo, mic, send):
        // one row of equal-weight glyphs at the trailing edge, with the send
        // button the only filled one.
        if left {
            XCTAssertLessThan(mic.frame.maxX, send.frame.maxX)
        } else {
            XCTAssertGreaterThan(mic.frame.minX, send.frame.minX)
        }
        if imageVisible {
            XCTAssertTrue(photo.exists)
            // Photo, mic and send share one bottom-aligned row.
            XCTAssertLessThan(photo.frame.maxX, mic.frame.minX)
            XCTAssertLessThan(mic.frame.maxX, send.frame.minX)
            XCTAssertEqual(photo.frame.maxY, send.frame.maxY, accuracy: 1)
            XCTAssertEqual(mic.frame.maxY, send.frame.maxY, accuracy: 1)
            XCTAssertTrue(photo.isHittable)
        } else {
            XCTAssertFalse(photo.exists)
        }
        if left {
            XCTAssertLessThan(send.frame.maxX, input.frame.minX)
        } else {
            XCTAssertGreaterThan(send.frame.minX, input.frame.maxX)
        }
        XCTAssertGreaterThanOrEqual(mic.frame.width, 44)
        XCTAssertGreaterThanOrEqual(mic.frame.height, 44)
        XCTAssertTrue(mic.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = left ? "composer-left" : "composer-right"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testDefaultRightHandedControls() {
        let app = launch()
        assertAligned(app, left: false)
        app.textViews["chat-input"].tap()
        app.textViews["chat-input"].typeText("handed-draft")
        XCTAssertTrue((app.textViews["chat-input"].value as? String)?.contains("handed-draft") == true)
        XCTAssertTrue(app.buttons["chat-send"].isEnabled)
    }

    @MainActor
    func testLeftHandedControls() {
        assertAligned(launch(side: "left"), left: true)
    }

    @MainActor
    func testHiddenImageDoesNotLeaveAnActionSlot() {
        let app = launch(side: "left", images: false)
        assertAligned(app, left: true, imageVisible: false)
    }

    @MainActor
    func testNoTokenHidesEntireRailAndRestoresKeyboard() {
        let app = launch(speech: false, voiceFirst: true)
        XCTAssertFalse(app.buttons["speech-transport"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["speech-waveform"].exists)
        XCTAssertFalse(app.buttons["chat-keyboard"].exists)
        let input = app.textViews["chat-input"]
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        input.typeText("typed-without-voice")
        XCTAssertTrue((input.value as? String)?.contains("typed-without-voice") == true)
        XCTAssertTrue(app.buttons["chat-send"].isEnabled)
    }

    @MainActor
    func testSettingsMoveControlsAndHideImageWithoutLosingDraft() {
        let sentinel = "KEEP_COMPOSER_DRAFT"
        let app = launch(draft: sentinel)
        XCTAssertTrue((app.textViews["chat-input"].value as? String)?.contains(sentinel) == true)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-current-host"].waitForExistence(timeout: 4))
        let inputVoice = app.buttons["settings-input-voice"]
        for _ in 0..<3 where !inputVoice.isHittable { app.swipeUp() }
        XCTAssertTrue(inputVoice.waitForExistence(timeout: 4))
        inputVoice.tap()
        let picker = app.descendants(matching: .any)["settings-composer-action-side"]
        for _ in 0..<6 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.exists && picker.isHittable, app.debugDescription)
        picker.tap()
        app.buttons["Left-hand side mode"].tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Left-hand side mode"),
            object: picker
        )
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 4), .completed)
        let toggle = app.descendants(matching: .any)["settings-show-image-button"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        let inner = toggle.descendants(matching: .switch).firstMatch
        XCTAssertTrue(inner.isHittable)
        inner.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: inner)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 4), .completed)
        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.textViews["chat-input"].waitForExistence(timeout: 4))
        XCTAssertTrue((app.textViews["chat-input"].value as? String)?.contains(sentinel) == true)
        assertAligned(app, left: true, imageVisible: false)
    }
}
