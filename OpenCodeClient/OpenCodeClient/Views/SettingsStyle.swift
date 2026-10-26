import SwiftUI

/// The approved Settings palette is local to this screen family.
/// It does not change transcript colors or system-wide appearance preferences.
enum SettingsStyle {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 36 / 255, green: 36 / 255, blue: 34 / 255)
            : Color(red: 250 / 255, green: 249 / 255, blue: 245 / 255)
    }

    static func foreground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 239 / 255, green: 238 / 255, blue: 232 / 255)
            : Color(red: 41 / 255, green: 40 / 255, blue: 35 / 255)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 170 / 255, green: 167 / 255, blue: 158 / 255)
            : Color(red: 115 / 255, green: 113 / 255, blue: 106 / 255)
    }

    static func connected(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 148 / 255, green: 181 / 255, blue: 156 / 255)
            : Color(red: 67 / 255, green: 116 / 255, blue: 90 / 255)
    }
}

struct SettingsPageStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(SettingsStyle.background(scheme))
            .foregroundStyle(SettingsStyle.foreground(scheme))
            .tint(SettingsStyle.foreground(scheme))
            .navigationBarTitleDisplayMode(.inline)
    }
}
