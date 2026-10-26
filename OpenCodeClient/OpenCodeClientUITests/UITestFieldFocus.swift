//
//  UITestFieldFocus.swift
//  OpenCodeClientUITests
//

import XCTest

/// Focus helpers for the UI tests.
///
/// A tap on a text field often lands while the keyboard is still settling, and
/// the field never takes the focus: the typing that follows then goes nowhere
/// and the test fails with "Neither element nor any descendant has keyboard
/// focus". A field that sits *under* the keyboard cannot be tapped at all
/// until the form scrolls, so the helper scrolls before it retries.
enum UITestFieldFocus {
    /// Taps the field and waits until it holds the keyboard focus.
    ///
    /// Returns whether the field took the focus.
    @MainActor
    static func focus(_ field: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 4) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for attempt in 0..<3 {
            field.tap()
            let expectation = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed {
                return true
            }
            // The field is probably under the keyboard: scrolling the form
            // brings it up, and the keyboard stays where it is.
            //
            // The swipe has to land on the form's own collection view: a
            // swipe that starts on a text field selects text instead of
            // scrolling, and the topmost one is the sheet's form.
            if attempt < 2 {
                let forms = app.collectionViews
                if forms.count > 0 {
                    forms.element(boundBy: forms.count - 1).swipeUp()
                }
            }
        }
        return false
    }

    /// Focuses the field and types into it.
    @MainActor
    static func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(focus(field, in: app), "the field should take the keyboard focus")
        field.typeText(text)
    }
}
