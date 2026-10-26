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
/// focus". Waiting for the focus — and tapping again if it did not take —
/// makes the typing deterministic.
enum UITestFieldFocus {
    /// Taps the field and waits until it holds the keyboard focus.
    ///
    /// Returns whether the field took the focus.
    @MainActor
    static func focus(_ field: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for attempt in 0..<3 {
            field.tap()
            let expectation = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed {
                return true
            }
            // The tap may have landed on the keyboard instead of the field.
            // Scroll the field into the middle of the screen and try again.
            if attempt < 2 {
                field.swipeUp()
            }
        }
        return false
    }

    /// Focuses the field and types into it.
    @MainActor
    static func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(focus(field), "the field should take the keyboard focus")
        field.typeText(text)
    }
}
