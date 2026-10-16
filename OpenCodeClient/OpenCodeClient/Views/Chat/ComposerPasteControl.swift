import SwiftUI
import UIKit

struct ComposerPasteControl: View {
    @Environment(\.colorScheme) private var colorScheme
    var beginPaste: () -> ([String]) -> Void
    var accessibilityLabel: String

    var body: some View {
        ComposerPasteButton(
            beginPaste: beginPaste,
            accessibilityLabel: accessibilityLabel,
            interfaceStyle: Self.interfaceStyle(for: colorScheme)
        )
        .id(Self.interfaceStyle(for: colorScheme).rawValue)
        .frame(width: ComposerHitTarget.minimum, height: ComposerHitTarget.minimum)
    }

    private static func interfaceStyle(for colorScheme: ColorScheme) -> UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }
}

struct ComposerPasteButton: UIViewRepresentable {
    var beginPaste: () -> ([String]) -> Void
    var accessibilityLabel: String
    var interfaceStyle: UIUserInterfaceStyle

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let control = UIPasteControl(configuration: PasteChrome.configuration(for: interfaceStyle))
        control.target = context.coordinator
        control.accessibilityIdentifier = "chat-paste"
        control.accessibilityLabel = accessibilityLabel
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.beginPaste = beginPaste
        uiView.target = context.coordinator
        uiView.accessibilityLabel = accessibilityLabel
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPasteControl, context: Context) -> CGSize? {
        CGSize(width: ComposerHitTarget.minimum, height: ComposerHitTarget.minimum)
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

enum PasteChrome {
    static func plate(for style: UIUserInterfaceStyle) -> UIColor {
        UIColor(style == .dark ? DesignColors.Neutral.composerDark : DesignColors.Neutral.composerLight)
    }

    static func configuration(for style: UIUserInterfaceStyle) -> UIPasteControl.Configuration {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerRadius = 0
        configuration.baseForegroundColor = UIColor(DesignColors.Brand.primary)
        configuration.baseBackgroundColor = plate(for: style)
        return configuration
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
