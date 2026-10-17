import XCTest
import UIKit

final class NavigationSimplificationUITests: XCTestCase {
    private let draftSentinel = "NAV_DRAFT_7f3a"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testRegularHasOneLayoutEntryAndNoSystemTabs() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad regular coverage")
        }
        let app = launch(layout: "automatic")
        XCTAssertTrue(marked(app, "ipad-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertFalse(marked(app, "compact-workspace-layout").exists)
        assertSingleLayoutEntry(app)
        assertSystemTabs(app, visible: false)
        capture(app, name: "regular-no-system-tabs")
    }

    @MainActor
    func testFocusRestoresNavigationAndKeepsDraft() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad focus coverage")
        }
        let app = launch(layout: "automatic")
        XCTAssertTrue(marked(app, "ipad-workspace-layout").waitForExistence(timeout: 8))
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        input.typeText(draftSentinel)
        XCTAssertTrue(composerContains(input, draftSentinel))

        selectLayout(app, english: "Focus", chinese: "专注")
        XCTAssertTrue(marked(app, "compact-workspace-layout").waitForExistence(timeout: 8))
        assertSystemTabs(app, visible: true)
        XCTAssertTrue(composerContains(input, draftSentinel), "切到 Focus 不应丢掉当前聊天草稿")

        systemTab(app, labels: ["Files", "文件"]).tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 4))
        systemTab(app, labels: ["Chat", "聊天"]).tap()
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(composerContains(input, draftSentinel), "经 Files 切回 Chat 后草稿应仍在同一输入框")

        selectLayout(app, english: "Auto", chinese: "自动")
        XCTAssertTrue(marked(app, "ipad-workspace-layout").waitForExistence(timeout: 8))
        assertSystemTabs(app, visible: false)
        assertSingleLayoutEntry(app)
        XCTAssertTrue(composerContains(input, draftSentinel), "回到三栏后草稿应仍在")
        capture(app, name: "focus-roundtrip-draft")
    }

    @MainActor
    func testNarrowWidthRestoresSystemTabsOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad narrow-width coverage")
        }
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_FORCE_WIDTH_CLASS"] = "compact"
        app.launch()
        XCTAssertTrue(marked(app, "compact-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertFalse(marked(app, "ipad-workspace-layout").exists)
        assertSystemTabs(app, visible: true)
        capture(app, name: "ipad-narrow-tabs")
    }

    @MainActor
    func testPhoneKeepsSystemTabs() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("iPhone compact coverage")
        }
        let app = launch()
        XCTAssertTrue(marked(app, "compact-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertFalse(marked(app, "ipad-workspace-layout").exists)
        assertSystemTabs(app, visible: true)
        capture(app, name: "phone-tabs")
    }

    @MainActor
    private func launch(layout: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let layout {
            app.launchEnvironment["UITEST_LAYOUT_PREFERENCE"] = layout
        }
        app.launch()
        return app
    }

    @MainActor
    private func assertSingleLayoutEntry(_ app: XCUIApplication) {
        let menus = app.descendants(matching: .any).matching(identifier: "layout-preference-menu")
        XCTAssertEqual(menus.count, 1, "regular 三栏应只有聊天栏模型按钮左边的布局入口。\(layoutDebug(app))")
        let menu = layoutControl(app)
        XCTAssertTrue(menu.isHittable, "布局入口不可点。\(layoutDebug(app))")
        XCTAssertTrue(app.buttons["ipad-settings-button"].exists)
    }

    @MainActor
    private func assertSystemTabs(_ app: XCUIApplication, visible: Bool) {
        let chat = systemTab(app, labels: ["Chat", "聊天"])
        let files = systemTab(app, labels: ["Files", "文件"])
        let settings = systemTab(app, labels: ["Settings", "设置"])
        if visible {
            XCTAssertTrue(chat.waitForExistence(timeout: 4), "应能通过系统 tab 切到 Chat。\(tabDebug(app))")
            XCTAssertTrue(files.waitForExistence(timeout: 2), "应能通过系统 tab 切到 Files。\(tabDebug(app))")
            XCTAssertTrue(chat.isHittable && files.isHittable, tabDebug(app))
            _ = settings.exists
        } else {
            XCTAssertFalse(chat.isHittable, "regular 三栏不应留下可点的 Chat tab。\(tabDebug(app))")
            XCTAssertFalse(files.isHittable, "regular 三栏不应留下可点的 Files tab。\(tabDebug(app))")
        }
    }

    @MainActor
    private func systemTab(_ app: XCUIApplication, labels: [String]) -> XCUIElement {
        let inBar = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", labels)).element(boundBy: 0)
        if inBar.exists { return inBar }
        return app.buttons.matching(NSPredicate(format: "label IN %@", labels)).element(boundBy: 0)
    }

    @MainActor
    private func tabDebug(_ app: XCUIApplication) -> String {
        let labels = ["Chat", "聊天", "Files", "文件", "Settings", "设置"]
        let buttons = app.buttons.matching(NSPredicate(format: "label IN %@", labels))
        let details = (0..<min(buttons.count, 6)).map { index -> String in
            let button = buttons.element(boundBy: index)
            return "\(button.label)#\(button.identifier) frame=\(button.frame) hittable=\(button.isHittable)"
        }
        return "tabs=[\(details.joined(separator: " | "))] tabBarCount=\(app.tabBars.count)"
    }

    @MainActor
    private func layoutControl(_ app: XCUIApplication) -> XCUIElement {
        let buttons = app.buttons.matching(identifier: "layout-preference-menu")
        if buttons.count > 0, buttons.element(boundBy: 0).isHittable {
            return buttons.element(boundBy: 0)
        }
        for label in ["Layout Mode", "布局模式"] {
            let labeled = app.buttons[label]
            if labeled.exists, labeled.isHittable { return labeled }
        }
        let identified = app.descendants(matching: .any).matching(identifier: "layout-preference-menu")
        for index in 0..<identified.count {
            let element = identified.element(boundBy: index)
            if element.isHittable { return element }
            let nested = element.buttons.firstMatch
            if nested.exists, nested.isHittable { return nested }
        }
        return identified.element(boundBy: 0)
    }

    @MainActor
    private func layoutDebug(_ app: XCUIApplication) -> String {
        let identified = app.descendants(matching: .any).matching(identifier: "layout-preference-menu")
        let details = (0..<min(identified.count, 4)).map { index -> String in
            let element = identified.element(boundBy: index)
            return "type=\(element.elementType.rawValue) frame=\(element.frame) hittable=\(element.isHittable) label=\(element.label)"
        }
        let model = app.buttons["chat-toolbar-model"]
        let tabs = app.tabBars.allElementsBoundByIndex.map { "frame=\($0.frame) hittable=\($0.isHittable)" }
        return "menus=[\(details.joined(separator: " | "))] model=\(model.exists) modelFrame=\(model.frame) modelHittable=\(model.isHittable) tabs=[\(tabs.joined(separator: "; "))]"
    }

    @MainActor
    private func selectLayout(_ app: XCUIApplication, english: String, chinese: String) {
        let menu = layoutControl(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 4), layoutDebug(app))
        XCTAssertTrue(menu.isHittable, layoutDebug(app))
        menu.tap()
        let choice = firstExisting(app, labels: [english, chinese])
        XCTAssertTrue(choice.waitForExistence(timeout: 4), "布局菜单应提供 \(english)/\(chinese)")
        choice.tap()
    }

    @MainActor
    private func firstExisting(_ app: XCUIApplication, labels: [String]) -> XCUIElement {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            for label in labels {
                let button = app.buttons[label]
                if button.exists { return button }
                let item = app.menuItems[label]
                if item.exists { return item }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return app.buttons[labels[0]]
    }

    @MainActor
    private func composerContains(_ input: XCUIElement, _ needle: String) -> Bool {
        let value = input.value as? String ?? ""
        return value.contains(needle)
    }

    @MainActor
    private func marked(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
