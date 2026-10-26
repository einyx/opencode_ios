import SwiftUI

/// The Settings screen family reads the shared Warm Editorial tokens.
///
/// Since the 2026-10-26 Warm Editorial adoption these values *are* the app's
/// palette (`DesignColors.Page`), so Settings no longer carries a private
/// palette — the aliases stay because the call sites read well.
enum SettingsStyle {
    static func background(_ scheme: ColorScheme) -> Color {
        DesignColors.Page.background(for: scheme)
    }

    static func foreground(_ scheme: ColorScheme) -> Color {
        DesignColors.Page.foreground(for: scheme)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        DesignColors.Page.secondary(for: scheme)
    }

    static func connected(_ scheme: ColorScheme) -> Color {
        DesignColors.Page.connected(for: scheme)
    }
}

struct SettingsPageStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(SettingsStyle.background(scheme))
            .foregroundStyle(SettingsStyle.foreground(scheme))
            .navigationBarTitleDisplayMode(.inline)
    }
}
