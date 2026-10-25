//
//  GlassSurface.swift
//  OpenCodeClient
//
//  Liquid Glass surface with a material fallback for iOS 17–25.
//
//  Every floating surface in the chat goes through this modifier, so the
//  pre-iOS-26 fallback never drifts away from the glass design.
//

import SwiftUI

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    /// Interactive glass reacts to presses (buttons, the composer).
    var interactive: Bool = false
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0) }
                ?? (interactive ? Glass.regular.interactive() : Glass.regular)
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// Floating Liquid Glass surface. On iOS 17–25 this is a translucent
    /// material with a hairline edge.
    func glassSurface(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                interactive: interactive,
                tint: tint
            )
        )
    }
}
