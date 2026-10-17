import XCTest

final class FileSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchResultsOpenFileContent() {
        let app = launchSearch(mode: "results")
        let result = app.descendants(matching: .any)["file-search-result-notes.txt"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(app.staticTexts["W06_FILE_SENTINEL"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["notes.txt"].waitForExistence(timeout: 4))
    }

    func testSearchEmptyState() {
        let app = launchSearch(mode: "empty")
        XCTAssertTrue(app.descendants(matching: .any)["file-search-empty"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["file-search-result-notes.txt"].exists)
    }

    func testSearchLoadingState() {
        let app = launchSearch(mode: "loading")
        XCTAssertTrue(app.descendants(matching: .any)["file-search-loading"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["file-search-result-notes.txt"].exists)
    }

    func testSearchInputClearThenOpenWorkspaceB() {
        let app = launchSearch(mode: "live")
        searchClearThenOpenB(app)
        XCTAssertFalse(app.staticTexts["CONTENT_A"].exists)
        let probe = app.descendants(matching: .any)["file-search-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        XCTAssertTrue(probe.label.contains("find:/tmp/w06-ws-b"))
        XCTAssertTrue(probe.label.contains("content:/tmp/w06-ws-b"))
        XCTAssertFalse(probe.label.contains("/tmp/w06-ws-a"))
    }

    func testSplitSearchOpensWorkspaceB() {
        let app = launchSearch(mode: "split")
        XCTAssertTrue(app.descendants(matching: .any)["file-search-split-host"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["file-split-open-preview"].exists)
        searchClearThenShowResult(app)
        let matches = app.descendants(matching: .any).matching(identifier: "file-search-result-notes.txt")
        dumpSplitHit(app, matches, "before")
        XCTAssertEqual(matches.count, 1)
        let result = matches.element(boundBy: 0)
        XCTAssertEqual(result.identifier, "file-search-result-notes.txt")
        XCTAssertTrue(result.isHittable)
        result.tap()
        let opened = app.staticTexts["CONTENT_B"].waitForExistence(timeout: 8)
        dumpSplitHit(app, matches, opened ? "after-open" : "after-miss")
        XCTAssertTrue(opened)
        XCTAssertTrue(app.descendants(matching: .any)["file-content-screen"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["CONTENT_A"].exists)
        let probe = app.descendants(matching: .any)["file-search-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        XCTAssertTrue(probe.label.contains("find:/tmp/w06-ws-b"))
        XCTAssertTrue(probe.label.contains("content:/tmp/w06-ws-b"))
        XCTAssertFalse(probe.label.contains("/tmp/w06-ws-a"))
    }

    func testReusedFileViewDropsLatePathSuccess() {
        let app = launchReuse(mode: "late-path")
        waitUntilReuseRequestStarted(app)
        app.descendants(matching: .any)["file-content-switch-path"].tap()
        XCTAssertTrue(app.staticTexts["CONTENT_B"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["b.txt"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["file-content-share"].waitForExistence(timeout: 4))
        app.descendants(matching: .any)["file-content-release-late"].tap()
        let probe = app.descendants(matching: .any)["file-content-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "late:1"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["CONTENT_B"].exists)
        XCTAssertFalse(app.staticTexts["CONTENT_A"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["file-content-error"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["file-content-share"].exists)
        XCTAssertTrue(app.navigationBars["b.txt"].exists)
    }

    func testReusedFileViewDropsLatePathError() {
        let app = launchReuse(mode: "late-error")
        waitUntilReuseRequestStarted(app)
        app.descendants(matching: .any)["file-content-switch-path"].tap()
        XCTAssertTrue(app.staticTexts["CONTENT_B"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["file-content-release-late"].tap()
        let probe = app.descendants(matching: .any)["file-content-probe"]
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "late:1"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["CONTENT_B"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["file-content-error"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["file-content-share"].exists)
    }

    func testSamePathWorkspaceSwitchRecordsDirectoryAndDropsLateA() {
        let app = launchReuse(mode: "late-workspace")
        waitUntilReuseRequestStarted(app)
        app.descendants(matching: .any)["file-content-switch-workspace"].tap()
        XCTAssertTrue(app.staticTexts["CONTENT_B"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["notes.txt"].waitForExistence(timeout: 4))
        app.descendants(matching: .any)["file-content-release-late"].tap()
        let probe = app.descendants(matching: .any)["file-content-probe"]
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "late:1"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 8), .completed)
        XCTAssertTrue(probe.label.contains("/tmp/w06-ws-a"))
        XCTAssertTrue(probe.label.contains("/tmp/w06-ws-b"))
        XCTAssertTrue(app.staticTexts["CONTENT_B"].exists)
        XCTAssertFalse(app.staticTexts["CONTENT_A"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["file-content-share"].exists)
    }

    func testSameFileRebindsSessionWithoutReload() {
        let app = launchReuse(mode: "session-rebind")
        let probe = app.descendants(matching: .any)["file-content-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "count:1"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        let link = app.links["Open other"]
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["SESSION_REBIND_BODY"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["notes.md"].waitForExistence(timeout: 4))
        let before = requestCount(probe.label)
        XCTAssertEqual(before, 1)
        XCTAssertTrue(probe.label.contains("pending:-"))
        app.descendants(matching: .any)["file-content-bind-session"].tap()
        let screen = app.descendants(matching: .any)["file-content-screen"]
        let reboundOwner = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "session-b"), object: screen)
        XCTAssertEqual(XCTWaiter.wait(for: [reboundOwner], timeout: 8), .completed, probe.label)
        XCTAssertTrue(app.navigationBars["notes.md"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["file-content-loading"].exists)
        let stillLoaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "count:1"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [stillLoaded], timeout: 4), .completed, "label=\(probe.label) value=\(probe.value ?? "")")
        XCTAssertEqual(requestCount(probe.label), before, probe.label)
        XCTAssertTrue(app.links["Open other"].waitForExistence(timeout: 20))
        app.descendants(matching: .any)["file-content-activate-link"].tap()
        let staged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "pending:session-b"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [staged], timeout: 8), .completed, probe.label)
        XCTAssertTrue(probe.label.contains("open:other.md"), probe.label)
        XCTAssertEqual(requestCount(probe.label), before)
        XCTAssertTrue(app.staticTexts["SESSION_REBIND_BODY"].exists)
        XCTAssertTrue(app.navigationBars["notes.md"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["file-content-loading"].exists)
    }

    func testSinglePullRefreshIssuesOneRequest() {
        let app = launchReuse(mode: "refresh")
        let probe = app.descendants(matching: .any)["file-content-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["BODY-1"].waitForExistence(timeout: 8))
        let before = requestCount(probe.label)
        XCTAssertGreaterThan(before, 0)
        let screen = app.descendants(matching: .any)["file-content-screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 4))
        let body = app.staticTexts["BODY-1"]
        let start = body.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 360))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        let oneMore = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "count:\(before + 1)"),
            object: probe
        )
        XCTAssertEqual(XCTWaiter.wait(for: [oneMore], timeout: 8), .completed)
        let extra = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "count:\(before + 2)"),
            object: probe
        )
        XCTAssertEqual(XCTWaiter.wait(for: [extra], timeout: 1.5), .timedOut)
    }

    private func dumpSplitHit(_ app: XCUIApplication, _ matches: XCUIElementQuery, _ name: String) {
        let id = "file-search-result-notes.txt"
        var lines: [String] = ["name=\(name)", "anyCount=\(matches.count)"]
        func describe(_ label: String, _ query: XCUIElementQuery) {
            lines.append("\(label) count=\(query.count)")
            for index in 0..<min(query.count, 3) {
                let element = query.element(boundBy: index)
                lines.append(
                    "  [\(index)] type=\(element.elementType.rawValue) id=\(element.identifier) label=\(element.label) hittable=\(element.isHittable) focus=\(element.hasFocus) enabled=\(element.isEnabled) frame=\(element.frame)"
                )
            }
        }
        describe("button", app.buttons.matching(identifier: id))
        describe("cell", app.cells.matching(identifier: id))
        describe("other", app.otherElements.matching(identifier: id))
        describe("staticText", app.staticTexts.matching(identifier: id))
        if matches.count == 1 {
            lines.append("matched:\n\(matches.element(boundBy: 0).debugDescription)")
        }
        let field = app.searchFields["Search files"]
        lines.append("search exists=\(field.exists) focus=\(field.hasFocus) value=\(String(describing: field.value)) frame=\(field.exists ? String(describing: field.frame) : "nil")")
        lines.append("keyboard count=\(app.keyboards.count)")
        if app.keyboards.count > 0 {
            let keyboard = app.keyboards.element(boundBy: 0)
            lines.append("keyboard frame=\(keyboard.frame) focus=\(keyboard.hasFocus)")
        }
        lines.append("bypass=\(app.buttons["file-split-open-preview"].exists)")
        lines.append("contentB=\(app.staticTexts["CONTENT_B"].exists) screen=\(app.descendants(matching: .any)["file-content-screen"].exists)")
        let probe = app.descendants(matching: .any)["file-search-probe"]
        lines.append("probe exists=\(probe.exists) label=\(probe.label)")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FileSearchUITests", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n\n" + app.debugDescription
        try? text.write(to: folder.appendingPathComponent("W06_rework5_\(name).hierarchy.txt"), atomically: true, encoding: .utf8)
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("W06_rework5_\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func searchClearThenOpenB(_ app: XCUIApplication) {
        searchClearThenShowResult(app)
        app.descendants(matching: .any)["file-search-result-notes.txt"].tap()
        XCTAssertTrue(app.staticTexts["CONTENT_B"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["file-content-screen"].waitForExistence(timeout: 4))
    }

    private func searchClearThenShowResult(_ app: XCUIApplication) {
        let field = app.searchFields["Search files"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("zz")
        let clear = field.buttons["Clear text"]
        if clear.waitForExistence(timeout: 2) {
            clear.tap()
        } else {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        }
        XCTAssertTrue(app.descendants(matching: .any)["file-tree"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["file-search-results"].exists)
        field.typeText("notes\n")
        XCTAssertTrue(app.descendants(matching: .any)["file-search-result-notes.txt"].waitForExistence(timeout: 8))
    }

    private func waitUntilReuseRequestStarted(_ app: XCUIApplication) {
        let probe = app.descendants(matching: .any)["file-content-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "count:1"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 8), .completed)
        XCTAssertFalse(probe.label.contains("late:1"))
    }

    private func requestCount(_ label: String) -> Int {
        guard let range = label.range(of: "count:") else { return -1 }
        let digits = label[range.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? -1
    }

    private func launchSearch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FILE_SEARCH_FIXTURE"]
        app.launchEnvironment["FILE_SEARCH_FIXTURE_MODE"] = mode
        app.launch()
        return app
    }

    private func launchReuse(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FILE_CONTENT_REUSE_FIXTURE"]
        app.launchEnvironment["FILE_CONTENT_FIXTURE_MODE"] = mode
        app.launch()
        return app
    }
}
