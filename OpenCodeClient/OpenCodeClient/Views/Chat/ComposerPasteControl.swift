import SwiftUI
import UIKit

struct ComposerPasteControl: UIViewRepresentable {
    var beginPaste: () -> ([String]) -> Void
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        apply(accessibilityLabel, to: control)
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.beginPaste = beginPaste
        uiView.target = context.coordinator
        apply(accessibilityLabel, to: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPasteControl, context: Context) -> CGSize? {
        CGSize(width: ComposerHitTarget.minimum, height: ComposerHitTarget.minimum)
    }

    private func apply(_ label: String, to control: UIPasteControl) {
        control.accessibilityIdentifier = "chat-paste"
        control.accessibilityLabel = label
    }

    final class Coordinator: UIView {
        var beginPaste: (() -> ([String]) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        override func paste(itemProviders: [NSItemProvider]) {
            let deliver = beginPaste?()
            let providers = itemProviders
            Task { @MainActor in
                let strings = await ComposerPastePayload.strings(from: providers)
                deliver?(strings)
            }
        }

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
        }
    }
}

enum ComposerPastePayload {
    static func strings(from providers: [NSItemProvider]) async -> [String] {
        var parts: [String] = []
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            let text: String? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    continuation.resume(returning: object as? String)
                }
            }
            guard let text, !text.isEmpty else { continue }
            parts.append(text)
        }
        return parts
    }
}
