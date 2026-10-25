//
//  KeyboardDismiss.swift
//  OpenCodeClient
//
//  A Done button above the keyboard.
//
//  A text field inside a Form leaves the keyboard covering the controls with
//  no way out: the bar that would dismiss it is hidden behind the keyboard
//  too. The toolbar item lives above the keyboard, so it is always reachable.
//

import SwiftUI

extension View {
    /// Adds a Done button to the keyboard toolbar and lets a scroll dismiss
    /// the keyboard.
    func dismissableKeyboard() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.t(.appDone)) {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
    }
}
