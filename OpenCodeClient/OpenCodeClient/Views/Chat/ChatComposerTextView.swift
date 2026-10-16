import SwiftUI

#if canImport(UIKit)
import UIKit

enum ChatComposerKeyAction: Equatable {
    case system
    case insertNewline
    case submit

    static func action(for replacementText: String, hasMarkedText: Bool, isShiftReturn: Bool) -> ChatComposerKeyAction {
        guard replacementText == "\n" else { return .system }
        guard !hasMarkedText else { return .system }
        return .insertNewline
    }
}

enum ChatComposerSendGate {
    static func canSend(text: String, isSending: Bool, hasMarkedText: Bool) -> Bool {
        guard !isSending, !hasMarkedText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ChatComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var hasMarkedText: Bool
    var isEditable: Bool = true
    var requestsFirstResponder: Bool = false
    var preferredCursorUTF16: Int? = nil
    let placeholder: String
    let autoScrollToBottomOnTextChange: Bool
    let onSubmit: () -> Void
    var onEndEditing: () -> Void = {}
    var onSelectionUTF16: (NSRange) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, hasMarkedText: $hasMarkedText, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> IMEAwareTextView {
        let textView = IMEAwareTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.returnKeyType = .default
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.accessibilityIdentifier = "chat-input"
        textView.accessibilityLabel = placeholder
        textView.onShiftReturn = {
            context.coordinator.insertNewline(into: textView)
        }
        textView.text = text
        context.coordinator.updateMarkedTextState(for: textView)
        return textView
    }

    func updateUIView(_ uiView: IMEAwareTextView, context: Context) {
        context.coordinator.onEndEditing = onEndEditing
        context.coordinator.onSelectionUTF16 = onSelectionUTF16
        context.coordinator.requestsFirstResponder = requestsFirstResponder
        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }
        if context.coordinator.wasEditable, !isEditable, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        context.coordinator.wasEditable = isEditable
        uiView.isSelectable = true
        if uiView.text != text {
            uiView.text = text
            if let cursor = preferredCursorUTF16, isEditable {
                let length = (text as NSString).length
                uiView.selectedRange = NSRange(location: min(max(0, cursor), length), length: 0)
            }
            if autoScrollToBottomOnTextChange {
                context.coordinator.scrollToBottom(uiView)
            }
        }
        uiView.accessibilityLabel = placeholder
        uiView.onShiftReturn = {
            context.coordinator.insertNewline(into: uiView)
        }
        context.coordinator.updateMarkedTextState(for: uiView)
        if requestsFirstResponder {
            context.coordinator.wasRequestingFocus = true
            if !uiView.isFirstResponder, !context.coordinator.focusScheduled {
                context.coordinator.focusScheduled = true
                DispatchQueue.main.async {
                    context.coordinator.focusScheduled = false
                    guard context.coordinator.requestsFirstResponder, !uiView.isFirstResponder else { return }
                    uiView.becomeFirstResponder()
                }
            }
        } else if context.coordinator.wasRequestingFocus {
            context.coordinator.wasRequestingFocus = false
            context.coordinator.focusScheduled = false
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var hasMarkedText: Bool
        private let onSubmit: () -> Void
        private var isInsertingShiftNewline = false
        var onEndEditing: () -> Void = {}
        var onSelectionUTF16: (NSRange) -> Void = { _ in }
        var focusScheduled = false
        var requestsFirstResponder = false
        var wasRequestingFocus = false
        var wasEditable = true

        init(text: Binding<String>, hasMarkedText: Binding<Bool>, onSubmit: @escaping () -> Void) {
            _text = text
            _hasMarkedText = hasMarkedText
            self.onSubmit = onSubmit
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            onEndEditing()
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            updateMarkedTextState(for: textView)
            onSelectionUTF16(textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateMarkedTextState(for: textView)
            onSelectionUTF16(textView.selectedRange)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
        ) -> Bool {
            let action = ChatComposerKeyAction.action(
                for: replacementText,
                hasMarkedText: textView.markedTextRange != nil,
                isShiftReturn: isInsertingShiftNewline
            )

            switch action {
            case .system:
                return true
            case .insertNewline:
                isInsertingShiftNewline = false
                return true
            case .submit:
                onSubmit()
                return false
            }
        }

        func insertNewline(into textView: UITextView) {
            isInsertingShiftNewline = true
            textView.insertText("\n")
        }

        func updateMarkedTextState(for textView: UITextView) {
            hasMarkedText = textView.markedTextRange != nil
        }

        func scrollToBottom(_ textView: UITextView) {
            let end = NSRange(location: (textView.text as NSString).length, length: 0)
            textView.selectedRange = end
            textView.layoutIfNeeded()
            textView.scrollRangeToVisible(end)
            let minY = -textView.adjustedContentInset.top
            let maxY = max(minY, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
            textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: maxY), animated: false)
        }
    }
}

final class IMEAwareTextView: UITextView {
    var onShiftReturn: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\r", modifierFlags: [.shift], action: #selector(handleShiftReturn))
        ]
    }

    @objc private func handleShiftReturn() {
        onShiftReturn?()
    }
}
#endif
