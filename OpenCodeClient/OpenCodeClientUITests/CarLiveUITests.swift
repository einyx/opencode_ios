import XCTest
import UIKit

final class CarLiveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testConnectedFixtureShowsBothRolesAndExpandableTool() throws {
        let app = try launchPhone()
        XCTAssertTrue(app.otherElements["car-live-root"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["car-live-mute"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["car-live-close"].exists)
        XCTAssertTrue(app.buttons["car-live-details"].exists)

        let transcript = app.scrollViews["car-live-transcript"]
        let early = app.staticTexts["car-live-caption-user-early"]
        let reply = app.staticTexts["car-live-caption-assistant-reply"]
        XCTAssertTrue(early.waitForExistence(timeout: 4))
        scroll(transcript, untilHittable: early, swipingDown: true)
        XCTAssertTrue(early.isHittable)
        XCTAssertTrue(reply.isHittable)

        let tool = app.buttons["car-live-tool-echo"]
        scroll(transcript, untilHittable: tool, swipingDown: false)
        XCTAssertEqual(tool.value as? String, "collapsed")
        XCTAssertFalse(app.staticTexts["car-live-tool-args-echo"].exists)
        tool.tap()
        let args = app.staticTexts["car-live-tool-args-echo"]
        XCTAssertTrue(args.waitForExistence(timeout: 4))
        scroll(transcript, untilHittable: args, swipingDown: false)
        XCTAssertTrue(args.label.contains("text=ok"))
        let result = app.staticTexts["car-live-tool-result-echo"]
        XCTAssertTrue(result.exists)
        scroll(transcript, untilHittable: result, swipingDown: false)
        XCTAssertEqual(result.label, "ok")
    }

    @MainActor
    func testMuteCloseAndCostDetails() throws {
        let app = try launchPhone()
        let mute = app.buttons["car-live-mute"]
        XCTAssertTrue(mute.waitForExistence(timeout: 8))
        XCTAssertEqual(mute.value as? String, "unmuted")
        XCTAssertFalse(mute.isSelected)
        XCTAssertTrue(mute.isEnabled)
        mute.tap()
        let muted = app.buttons["car-live-mute"]
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true AND value == 'muted'"),
            object: muted
        )
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 4), .completed)

        let interrupt = app.buttons["car-live-interrupt"]
        XCTAssertTrue(interrupt.exists)
        XCTAssertTrue(interrupt.isEnabled)
        XCTAssertFalse(interrupt.isSelected)

        let details = app.buttons["car-live-details"]
        XCTAssertTrue(details.exists)
        XCTAssertEqual(details.value as? String, "collapsed")
        XCTAssertFalse(app.staticTexts["car-live-cost-local"].exists)
        details.tap()
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'expanded'"), object: details)
        XCTAssertEqual(XCTWaiter().wait(for: [expanded], timeout: 4), .completed)
        let detailsBody = app.scrollViews["car-live-details-body"]
        let local = app.staticTexts["car-live-cost-local"]
        XCTAssertTrue(local.waitForExistence(timeout: 4))
        scroll(detailsBody, untilHittable: local, swipingDown: false)
        let portal = app.staticTexts["car-live-cost-portal"]
        XCTAssertTrue(portal.waitForExistence(timeout: 4))
        scroll(detailsBody, untilHittable: portal, swipingDown: false)
        XCTAssertTrue(local.label.contains("$0.12"))
        XCTAssertTrue(portal.label.contains("$0.34"))
        XCTAssertFalse(local.label.contains("$0.120"))
        XCTAssertFalse(portal.label.contains("$0.340"))
        XCTAssertTrue(local.label.contains("Reasoning Reference Estimate (Luna)") || local.label.contains("推理参考估算（Luna）"))
        XCTAssertTrue(portal.label.contains("Platform Session Estimate (Voice + Reasoning)") || portal.label.contains("平台会话估算（语音＋推理）"))
        XCTAssertTrue(portal.label.contains("Unconfirmed") || portal.label.contains("未最终确认"))
        XCTAssertFalse(local.label.contains("Unconfirmed") || local.label.contains("未最终确认"))
        XCTAssertFalse(local.label.contains("0.46"))
        XCTAssertFalse(portal.label.contains("0.46"))
        XCTAssertNotEqual(local.label, portal.label)
        let note = app.staticTexts["car-live-estimate-note"]
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("do not add them together") || note.label.contains("请勿相加"))
        let heading = app.staticTexts["car-live-cost-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 4))
        XCTAssertTrue(heading.label.contains("USD"))
        let unconfirmed = app.staticTexts["car-live-usage-unconfirmed"]
        XCTAssertTrue(unconfirmed.waitForExistence(timeout: 4))
        scroll(detailsBody, untilHittable: unconfirmed, swipingDown: false)
        XCTAssertFalse(unconfirmed.label.contains("0.460"))

        let close = app.buttons["car-live-close"]
        XCTAssertTrue(close.exists)
        XCTAssertTrue(close.isEnabled)
        close.tap()
        XCTAssertTrue(app.buttons["car-live-connect"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["car-live-close"].exists)
        XCTAssertFalse(app.buttons["car-live-mute"].isEnabled)
    }

    @MainActor
    func testToolUpdateScrollsLatestResultIntoView() throws {
        let app = try launchPhone()
        let early = app.staticTexts["car-live-caption-user-early"]
        XCTAssertTrue(early.waitForExistence(timeout: 8))
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: early)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 4), .completed)

        let transcript = app.scrollViews["car-live-transcript"]
        var swipes = 0
        while !early.isHittable && swipes < 8 {
            transcript.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(early.isHittable)

        let tool = app.buttons["car-live-tool-echo"]
        scroll(transcript, untilHittable: tool, swipingDown: false)
        XCTAssertFalse(tool.label.contains("FIXTURE_TOOL_UPDATE_SENTINEL"))
        tool.tap()
        let result = app.staticTexts["car-live-tool-result-echo"]
        XCTAssertTrue(result.waitForExistence(timeout: 4))
        XCTAssertNotEqual(result.label, "FIXTURE_TOOL_UPDATE_SENTINEL")
        swipes = 0
        while !early.isHittable && swipes < 8 {
            transcript.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(early.isHittable)

        app.buttons["car-live-fixture-update"].tap()
        let followed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ AND isHittable == true", "FIXTURE_TOOL_UPDATE_SENTINEL"),
            object: result
        )
        XCTAssertEqual(XCTWaiter().wait(for: [followed], timeout: 4), .completed)
        XCTAssertFalse(early.isHittable)
        XCTAssertFalse(app.buttons["car-live-tool-echo"].label.contains("FIXTURE_TOOL_UPDATE_SENTINEL"))
        XCTAssertEqual(app.buttons.matching(identifier: "car-live-tool-echo").count, 1)
    }

    @MainActor
    func testIconControlsShareRowAndExposeState() throws {
        let app = try launchPhone()
        let mute = app.buttons["car-live-mute"]
        let interrupt = app.buttons["car-live-interrupt"]
        let close = app.buttons["car-live-close"]
        XCTAssertTrue(mute.waitForExistence(timeout: 8))
        XCTAssertTrue(interrupt.exists)
        XCTAssertTrue(close.exists)
        XCTAssertFalse(app.buttons["car-live-connect"].exists)
        XCTAssertFalse(app.buttons["car-live-reconnect"].exists)

        assertSpokenLabelIsNotSymbol(mute)
        assertSpokenLabelIsNotSymbol(interrupt)
        assertSpokenLabelIsNotSymbol(close)
        XCTAssertEqual(mute.value as? String, "unmuted")
        XCTAssertFalse(mute.isSelected)
        XCTAssertFalse(interrupt.isSelected)
        XCTAssertFalse(close.isSelected)

        assertSameRow(mute, interrupt, close)
        let beforeMute = mute.screenshot().pngRepresentation
        XCTAssertNotEqual(beforeMute, interrupt.screenshot().pngRepresentation)
        XCTAssertNotEqual(close.screenshot().pngRepresentation, interrupt.screenshot().pngRepresentation)
        assertDangerFill(close)
        XCTAssertFalse(isDangerFill(mute))
        XCTAssertFalse(isDangerFill(interrupt))

        let transcript = app.scrollViews["car-live-transcript"]
        XCTAssertGreaterThan(transcript.frame.height, 120)
        assertVolumeContainer(app, above: mute)
        XCTAssertGreaterThan(mute.frame.minY, transcript.frame.minY + 80)

        mute.tap()
        let muted = app.buttons["car-live-mute"]
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true AND value == 'muted'"),
            object: muted
        )
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 4), .completed)
        XCTAssertNotEqual(beforeMute, muted.screenshot().pngRepresentation)
        assertBrandSolid(muted)
        XCTAssertFalse(isDangerFill(muted))

        interrupt.tap()
        XCTAssertFalse(app.buttons["car-live-interrupt"].isSelected)
        XCTAssertEqual(app.buttons["car-live-mute"].value as? String, "muted")

        close.tap()
        let connect = app.buttons["car-live-connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["car-live-close"].exists)
        assertSpokenLabelIsNotSymbol(connect)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 64)
        XCTAssertGreaterThan(connect.frame.width, app.buttons["car-live-mute"].frame.width * 1.8)
        XCTAssertLessThanOrEqual(connect.frame.maxY, app.buttons["car-live-mute"].frame.minY + 1)
        assertBrandSolid(connect)
        XCTAssertFalse(isDangerFill(connect))
        XCTAssertFalse(app.buttons["car-live-mute"].isEnabled)
        XCTAssertFalse(app.buttons["car-live-mute"].isSelected)
        assertVolumeContainer(app, above: app.buttons["car-live-mute"])
    }

    private func assertVolumeContainer(_ app: XCUIApplication, above mute: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.otherElements.matching(identifier: "car-live-volume-row")
        let volume = matches.firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 4), file: file, line: line)
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        XCTAssertGreaterThan(volume.frame.height, 16, file: file, line: line)
        XCTAssertLessThanOrEqual(volume.frame.height, 56, file: file, line: line)
        XCTAssertGreaterThan(volume.frame.width, 40, file: file, line: line)
        XCTAssertLessThan(volume.frame.width, 500, file: file, line: line)
        XCTAssertLessThanOrEqual(volume.frame.maxY, mute.frame.minY + 1, file: file, line: line)
    }

    private func assertSpokenLabelIsNotSymbol(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(element.label.isEmpty, file: file, line: line)
        let blocked = [
            "mic.slash",
            "waveform.slash",
            "phone.down.fill",
            "phone.fill",
            "speaker.wave.3.fill",
            "speaker.slash",
            "speaker.fill",
            "xmark",
            "mic",
        ]
        let label = element.label.lowercased()
        for symbol in blocked {
            XCTAssertFalse(label == symbol || label.contains(symbol), "label should stay localized, got \(element.label)", file: file, line: line)
        }
    }

    private func assertSameRow(_ first: XCUIElement, _ second: XCUIElement, _ third: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2, file: file, line: line)
        XCTAssertEqual(second.frame.minY, third.frame.minY, accuracy: 2, file: file, line: line)
        XCTAssertGreaterThanOrEqual(first.frame.height, 64, file: file, line: line)
        XCTAssertGreaterThanOrEqual(second.frame.height, 64, file: file, line: line)
        XCTAssertGreaterThanOrEqual(third.frame.height, 64, file: file, line: line)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 6, file: file, line: line)
        XCTAssertEqual(second.frame.width, third.frame.width, accuracy: 6, file: file, line: line)
        XCTAssertLessThan(first.frame.maxX, second.frame.minX, file: file, line: line)
        XCTAssertLessThan(second.frame.maxX, third.frame.minX, file: file, line: line)
    }

    private func assertDangerFill(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for fraction in [0.18, 0.82] {
            let sample = colorSample(element, xFraction: fraction)
            XCTAssertTrue(isDanger(sample), "expected danger red at \(fraction), got \(String(describing: sample))", file: file, line: line)
        }
    }

    private func assertBrandSolid(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for fraction in [0.18, 0.82] {
            let sample = colorSample(element, xFraction: fraction)
            XCTAssertTrue(isBrandSolid(sample), "expected brand solid at \(fraction), got \(String(describing: sample))", file: file, line: line)
        }
    }

    private func isDangerFill(_ element: XCUIElement) -> Bool {
        [0.18, 0.82].contains { isDanger(colorSample(element, xFraction: $0)) }
    }

    private func isDanger(_ sample: (CGFloat, CGFloat, CGFloat)?) -> Bool {
        guard let sample else { return false }
        return sample.0 > 0.65 && sample.0 > sample.1 + 0.25 && sample.0 > sample.2 + 0.25 && sample.1 < 0.5 && sample.2 < 0.5
    }

    private func isBrandSolid(_ sample: (CGFloat, CGFloat, CGFloat)?) -> Bool {
        guard let sample else { return false }
        return sample.2 > 0.75 && sample.2 > sample.0 + 0.3 && sample.1 > 0.35 && sample.1 < 0.75
    }

    private func colorSample(_ element: XCUIElement, xFraction: CGFloat) -> (CGFloat, CGFloat, CGFloat)? {
        let image = element.screenshot().image
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 1,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let x = min(width - 1, max(0, Int((CGFloat(width) * xFraction).rounded(.down))))
        let y = height / 2
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        guard bytesPerPixel >= 3 else { return nil }
        let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
        guard offset + bytesPerPixel <= CFDataGetLength(data) else { return nil }
        let alphaInfo = CGImageAlphaInfo(rawValue: cgImage.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        let byteOrder = cgImage.bitmapInfo.intersection(.byteOrderMask)
        let b0 = bytes[offset]
        let b1 = bytes[offset + 1]
        let b2 = bytes[offset + 2]
        let b3: UInt8 = bytesPerPixel > 3 ? bytes[offset + 3] : 255
        let channels: (UInt8, UInt8, UInt8, UInt8)
        switch (alphaInfo, byteOrder) {
        case (.premultipliedFirst, .byteOrder32Little), (.first, .byteOrder32Little), (.noneSkipFirst, .byteOrder32Little):
            channels = (b2, b1, b0, b3)
        case (.premultipliedFirst, _), (.first, _), (.noneSkipFirst, _):
            channels = (b1, b2, b3, b0)
        default:
            channels = (b0, b1, b2, b3)
        }
        let alpha = CGFloat(channels.3) / 255
        guard alpha > 0.15 else { return nil }
        let unpremultiply = alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
        let scale = unpremultiply ? 255 * alpha : 255
        return (CGFloat(channels.0) / scale, CGFloat(channels.1) / scale, CGFloat(channels.2) / scale)
    }

    private func scroll(_ transcript: XCUIElement, untilHittable element: XCUIElement, swipingDown: Bool) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            if swipingDown {
                transcript.swipeDown()
            } else {
                transcript.swipeUp()
            }
            tries += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    func testSwitchingTabsKeepsMutedCaptions() throws {
        let app = try launchPhone()
        let mute = app.buttons["car-live-mute"]
        XCTAssertTrue(mute.waitForExistence(timeout: 8))
        mute.tap()
        let muted = app.buttons["car-live-mute"]
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true AND value == 'muted'"),
            object: muted
        )
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 4), .completed)
        let caption = app.staticTexts["car-live-caption-assistant-reply"]
        XCTAssertTrue(caption.waitForExistence(timeout: 4))
        for identifier in ["car-voice-mode-menu", "car-new-session", "car-live-new-session"] {
            let button = app.buttons[identifier]
            XCTAssertFalse(button.exists)
            XCTAssertFalse(button.isHittable)
        }

        let chat = app.tabBars.buttons["Chat"]
        chat.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 8))
        let files = app.tabBars.buttons["Files"]
        files.tap()
        XCTAssertTrue(app.descendants(matching: .any)["file-tree"].waitForExistence(timeout: 8))
        let settings = app.tabBars.buttons["Settings"]
        settings.tap()
        XCTAssertTrue(app.buttons["settings-current-host"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Ambient Mode"].tap()

        XCTAssertTrue(app.otherElements["car-live-root"].waitForExistence(timeout: 8))
        let returned = app.buttons["car-live-mute"]
        XCTAssertTrue(returned.waitForExistence(timeout: 4))
        XCTAssertEqual(returned.value as? String, "muted")
        XCTAssertTrue(returned.isSelected)
        XCTAssertTrue(app.staticTexts["car-live-caption-assistant-reply"].exists)
        XCTAssertTrue(app.staticTexts["car-live-caption-user-early"].exists)
    }

    @MainActor
    func testDetailsLandscapeDiagnostic() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try launchPhone(["UITEST_CAR_LIVE_DETAILS_OPEN"], focusLayout: true)
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { evaluated, _ in
                guard let application = evaluated as? XCUIApplication else { return false }
                let frame = application.frame
                return frame.width > frame.height
            },
            object: app
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [landscape], timeout: 6),
            .completed,
            "app.frame=\(app.frame) orientation=\(XCUIDevice.shared.orientation)"
        )
        let detailsBody = app.scrollViews["car-live-details-body"]
        XCTAssertTrue(detailsBody.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            detailsBody.frame.height,
            40,
            "detailsBody.frame=\(detailsBody.frame) app.frame=\(app.frame) orientation=\(XCUIDevice.shared.orientation)"
        )
        let close = app.buttons["car-live-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        XCTAssertTrue(close.isHittable)
        keepScreenshot(app, name: "details-landscape-diagnostic")
    }

    @MainActor
    func testDetailsMetricsFollowContainerWidth() throws {
        let app = try launchPhone(["UITEST_CAR_LIVE_DETAILS_OPEN"], focusLayout: true)
        let detailsBody = app.scrollViews["car-live-details-body"]
        XCTAssertTrue(detailsBody.waitForExistence(timeout: 8))
        let voice = app.descendants(matching: .any)["car-live-voice-seconds"]
        let session = app.descendants(matching: .any)["car-live-session-seconds"]
        let input = app.descendants(matching: .any)["car-live-input-usage"]
        XCTAssertTrue(voice.waitForExistence(timeout: 4))
        revealInDetails(detailsBody, voice)
        revealInDetails(detailsBody, session)
        XCTAssertTrue(voice.label.contains("00:00:12"))
        XCTAssertFalse(voice.label.contains("00:00:00"))
        XCTAssertTrue(session.label.contains("25:01:01"))
        revealInDetails(detailsBody, input)
        XCTAssertTrue(input.label.contains("1.23M"))
        XCTAssertEqual(input.value as? String, "1234567")
        XCTAssertFalse(input.label.contains("1234567"))
        XCTAssertTrue(app.buttons["car-live-close"].isHittable)
        XCTAssertLessThanOrEqual(detailsBody.frame.height, 260)
        XCTAssertGreaterThan(app.buttons["car-live-close"].frame.minY, detailsBody.frame.minY)
        assertDetailsColumns(app, accessibility: false)
        keepScreenshot(app, name: "details-refresh-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        keepScreenshot(app, name: "details-refresh-landscape-after-orientation")
        let rotated = XCTNSPredicateExpectation(
            predicate: NSPredicate { evaluated, _ in
                guard let body = evaluated as? XCUIElement else { return false }
                let frame = body.frame
                return frame.width > 500 && frame.height > 40
            },
            object: detailsBody
        )
        let root = app.otherElements["car-live-root"]
        XCTAssertEqual(
            XCTWaiter().wait(for: [rotated], timeout: 6),
            .completed,
            "app.frame=\(app.frame) detailsBody.frame=\(detailsBody.frame) car-live-root.frame=\(root.frame) orientation=\(XCUIDevice.shared.orientation)"
        )
        resetDetailsScroll(detailsBody)
        keepScreenshot(app, name: "details-refresh-landscape")
        assertDetailsColumns(app, accessibility: false)
    }

    @MainActor
    func testDetailsMetricsUseOneColumnForAccessibilityText() throws {
        let app = try launchPhone([
            "UITEST_CAR_LIVE_DETAILS_OPEN",
            "UITEST_CAR_LIVE_ACCESSIBILITY_TEXT",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ], focusLayout: true)
        let body = app.scrollViews["car-live-details-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(body.frame.height, 40)
        XCTAssertLessThanOrEqual(body.frame.height, 260)
        let voice = app.descendants(matching: .any)["car-live-voice-seconds"]
        let session = app.descendants(matching: .any)["car-live-session-seconds"]
        XCTAssertTrue(voice.waitForExistence(timeout: 4))
        revealInDetails(body, voice)
        XCTAssertGreaterThan(voice.frame.width, body.frame.width * 0.7)
        XCTAssertFalse(voice.label.isEmpty)
        XCTAssertFalse(voice.label.contains("…"))
        keepScreenshot(app, name: "details-refresh-accessibility")
        revealInDetails(body, session)
        XCTAssertGreaterThan(session.frame.width, body.frame.width * 0.7)
        XCTAssertFalse(session.label.contains("…"))
        if isOnScreen(voice, in: body) {
            XCTAssertGreaterThan(session.frame.minY, voice.frame.minY + 4)
        }
        let note = app.staticTexts["car-live-estimate-note"]
        revealInDetails(body, note)
        XCTAssertTrue(isOnScreen(note, in: body))
        XCTAssertTrue(note.label.contains("do not add them together") || note.label.contains("请勿相加"))
        XCTAssertFalse(note.label.contains("…"))
        XCTAssertTrue(app.buttons["car-live-close"].exists)
        XCTAssertGreaterThan(body.frame.height, 40)
    }

    @MainActor
    private func assertDetailsColumns(_ app: XCUIApplication, accessibility: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let ids = [
            "car-live-voice-seconds",
            "car-live-session-seconds",
            "car-live-input-usage",
            "car-live-output-usage",
            "car-live-cache-read",
            "car-live-cache-write",
            "car-live-input-level",
            "car-live-output-level",
        ]
        let body = app.scrollViews["car-live-details-body"]
        XCTAssertTrue(body.exists, file: file, line: line)
        let columns = detailsColumnCount(width: body.frame.width, accessibility: accessibility)
        var index = 0
        while index < ids.count {
            let rowCount = min(columns, ids.count - index)
            let row = (0..<rowCount).map { app.descendants(matching: .any)[ids[index + $0]] }
            for cell in row {
                revealInDetails(body, cell, file: file, line: line)
                XCTAssertTrue(isOnScreen(cell, in: body), "\(ids[index]) stayed off the details scroller", file: file, line: line)
                XCTAssertFalse(cell.label.isEmpty, file: file, line: line)
                XCTAssertFalse(cell.label.contains("…"), file: file, line: line)
            }
            if rowCount == 1 {
                XCTAssertGreaterThan(row[0].frame.width, body.frame.width * 0.7, file: file, line: line)
            } else {
                XCTAssertLessThan(row[0].frame.width, body.frame.width * 0.75, file: file, line: line)
                for column in 1..<rowCount {
                    XCTAssertEqual(row[column].frame.minY, row[0].frame.minY, accuracy: 8, file: file, line: line)
                    XCTAssertGreaterThan(row[column].frame.minX, row[column - 1].frame.maxX - 4, file: file, line: line)
                }
            }
            index += rowCount
        }
    }

    @MainActor
    private func revealInDetails(_ container: XCUIElement, _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if isOnScreen(element, in: container) { return }
        XCTAssertGreaterThan(container.frame.width, 2, file: file, line: line)
        XCTAssertGreaterThan(container.frame.height, 2, file: file, line: line)
        for _ in 0..<3 {
            if isOnScreen(element, in: container) { return }
            drag(container, upward: false)
        }
        var tries = 0
        while !isOnScreen(element, in: container) && tries < 8 {
            drag(container, upward: true)
            tries += 1
        }
        XCTAssertTrue(
            isOnScreen(element, in: container),
            "failed to reveal \(element.identifier) frame=\(element.frame) container=\(container.frame)",
            file: file,
            line: line
        )
    }

    private func isOnScreen(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        guard element.exists, container.frame.width > 2, container.frame.height > 2 else { return false }
        let overlap = element.frame.intersection(container.frame)
        return overlap.width > 8 && overlap.height > 8
    }

    private func resetDetailsScroll(_ container: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(container.frame.height, 40, file: file, line: line)
        for _ in 0..<5 {
            drag(container, upward: false)
        }
    }

    private func drag(_ container: XCUIElement, upward: Bool) {
        if upward {
            container.swipeUp()
        } else {
            container.swipeDown()
        }
    }

    private func detailsColumnCount(width: CGFloat, accessibility: Bool) -> Int {
        if accessibility || width < 240 { return 1 }
        if width < 560 { return 2 }
        if width < 800 { return 3 }
        return 4
    }

    private func keepScreenshot(_: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = name
        add(shot)
    }

    @MainActor
    private func launchPhone(_ extra: [String] = [], focusLayout: Bool = false) throws -> XCUIApplication {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Car Mode is iPhone-only")
        }
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CAR_LIVE_FIXTURE"] + extra
        if focusLayout {
            app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = "focus"
        }
        app.launch()
        return app
    }
}
