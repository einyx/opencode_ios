//
//  GlassSurface.swift
//  OpenCodeClient
//
//  Liquid Glass surface with a material fallback for iOS 17–25 and visionOS.
//
//  Every floating surface in the chat goes through this modifier, so the
//  pre-iOS-26 fallback never drifts away from the glass design.
//

import SwiftUI

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat
    /// Interactive glass reacts to presses (buttons, the composer).
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                colorScheme == .dark ? DesignColors.Neutral.surfaceDark : DesignColors.Neutral.surfaceLight,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        } else {
        // `Glass` and `glassEffect(_:in:)` are API_UNAVAILABLE(visionos), so
        // the availability check alone is not enough: `#available(iOS 26, *)`
        // is true on visionOS 26 but the symbols still do not exist there.
        // Compile the glass path only on iOS and use the material fallback
        // everywhere else (visionOS, pre-26 iOS).
        #if os(iOS)
        if #available(iOS 26.0, *) {
            let glass: Glass = interactive ? Glass.regular.interactive() : Glass.regular
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.materialSurface(cornerRadius: cornerRadius)
        }
        #else
        content.materialSurface(cornerRadius: cornerRadius)
        #endif
        }
    }
}

private extension View {
    /// Translucent material with a hairline edge; the stand-in for Liquid
    /// Glass on every platform where the glass APIs do not exist.
    func materialSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Floating Liquid Glass surface. On iOS 17–25 this is a translucent
    /// material with a hairline edge.
    func glassSurface(
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}
