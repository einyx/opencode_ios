//
//  DesignTokens.swift
//  OpenCodeClient
//
//  Centralized design system: colors, typography, spacing, corners, animations.
//  All visual values flow from here — no magic numbers in View files.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color System

enum DesignColors {

    // MARK: Brand

    enum Brand {
        /// Primary brand — the single identity color of the app. Terracotta
        /// #C96442 since the 2026-10-26 Warm Editorial adoption (it replaced
        /// electric blue #3B82F6); used for every interactive/branded element
        /// (send, selection, links, the user-message bar).
        static let primary = Color(red: 0.788, green: 0.392, blue: 0.259)
        /// The accent step for small text. Terracotta on ivory is ≈3.3:1 —
        /// fine for icons, borders and semibold labels, tight for body-size
        /// text — so small accent text darkens on light surfaces and lifts on
        /// dark ones.
        static let primaryText = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.824, green: 0.439, blue: 0.298, alpha: 1)   // #D2704C
                : UIColor(red: 0.706, green: 0.341, blue: 0.227, alpha: 1)   // #B4573A
        })
        /// Gold accent #D9A621. Session triage uses gold for pending user requests;
        /// execution uses the dedicated SessionIndicator.running token.
        static let gold = Color(red: 0.851, green: 0.651, blue: 0.129)

        /// The accent at surface strength — card fills and change surfaces.
        ///
        /// A View must not call `.opacity(` on the accent itself (POL-COLOR-09:
        /// opacity comes from `DesignColors.Opacity`), so the muted accent
        /// lives here as a token.
        @MainActor
        static func surface(for scheme: ColorScheme) -> Color {
            primary.opacity(DesignColors.surfaceFill(for: scheme))
        }

        /// The accent at selection strength — a selected row.
        @MainActor
        static func selection(for scheme: ColorScheme) -> Color {
            primary.opacity(DesignColors.Opacity.selectionFill)
        }

        /// The accent at dot strength — small indicators that must stay
        /// visible but quiet.
        static let primaryMuted = primary.opacity(0.5)
    }

    /// The warm page the app sits on. Before the Warm Editorial adoption the
    /// app inherited the system background; the audit tracked that absence as
    /// POL-COLOR-01 (no `bg.primary` token).
    enum Page {
        /// Warm ivory #FAF9F5 / warm near-black #242422 — the values the
        /// approved Settings refresh introduced, now shared.
        nonisolated static func background(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 36 / 255, green: 36 / 255, blue: 34 / 255)
                : Color(red: 250 / 255, green: 249 / 255, blue: 245 / 255)
        }

        /// Warm ink #292823 / #EFEEE8.
        nonisolated static func foreground(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 239 / 255, green: 238 / 255, blue: 232 / 255)
                : Color(red: 41 / 255, green: 40 / 255, blue: 35 / 255)
        }

        /// Secondary warm text #73716A / #AAA79E.
        nonisolated static func secondary(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 170 / 255, green: 167 / 255, blue: 158 / 255)
                : Color(red: 115 / 255, green: 113 / 255, blue: 106 / 255)
        }

        /// Sage #7A9B76 / #94B59C — "connected / ok".
        nonisolated static func connected(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 148 / 255, green: 181 / 255, blue: 156 / 255)
                : Color(red: 67 / 255, green: 116 / 255, blue: 90 / 255)
        }
    }

    // MARK: Semantic

    enum Semantic {
        static let error = Color.red
        static let success = Color(red: 0.20, green: 0.65, blue: 0.35)
        static let warning = Color.orange
        static let info = Color(red: 0.25, green: 0.47, blue: 0.85)
    }

    /// The live-capture accent. A dedicated token so the mic control and the
    /// voice rail share one recording colour instead of each reaching for a
    /// raw system red. It reuses `Semantic.error` — the same dynamic system
    /// red — so the indicator keeps its light/dark adaptation.
    enum Recording {
        static let active = Semantic.error
    }

    enum SessionIndicator {
        static let failed = Color(red: 229.0 / 255, green: 72.0 / 255, blue: 77.0 / 255)
        static let runningLight = Color(red: 22.0 / 255, green: 124.0 / 255, blue: 69.0 / 255)
        static let runningDark = Color(red: 76.0 / 255, green: 191.0 / 255, blue: 130.0 / 255)
    }

    // MARK: Neutral (warm-tinted gray scale, less blue than system grays)

    enum Neutral {
        /// Primary text
        static let text = Color.primary
        /// Secondary text, timestamps, labels
        static let textSecondary = Color.secondary
        /// Tertiary text, disabled labels
        #if canImport(UIKit)
        static let textTertiary = Color(UIColor.tertiaryLabel)
        #else
        static let textTertiary = Color.gray.opacity(0.4)
        #endif

        /// Subtle card / info surface background — light mode, warm stone (#F4F1EC)
        static let surfaceLight = Color(red: 0.957, green: 0.945, blue: 0.925)
        /// Subtle card / info surface background — dark mode, warm (#1E1D1B)
        static let surfaceDark = Color(red: 0.118, green: 0.114, blue: 0.106)
        /// Composer input background — light mode (#F1EDE6, the secondary bg)
        static let composerLight = Color(red: 0.945, green: 0.929, blue: 0.902)
        /// Composer input background — dark mode (#191816, the secondary bg)
        static let composerDark = Color(red: 0.098, green: 0.094, blue: 0.086)

        /// A barely-there neutral fill — diff rows, quiet containers.
        ///
        /// Kept as a token so a View never calls `.opacity(` itself
        /// (POL-COLOR-09).
        @MainActor
        static func subtleFill(for scheme: ColorScheme) -> Color {
            text.opacity(scheme == .dark ? 0.08 : 0.04)
        }
    }

    // MARK: Opacity Rules

    /// Unified opacity system. Use these instead of ad-hoc .opacity() values.
    enum Opacity {
        /// Card / info surface fill
        static let surfaceFill: Double = 0.06
        /// Card / info surface fill in dark mode
        static let surfaceFillDark: Double = 0.10
        /// Card / info border stroke
        static let borderStroke: Double = 0.12
        /// Card / info border stroke in dark mode
        static let borderStrokeDark: Double = 0.15
        /// User message border
        static let userMessageBorder: Double = 0.18
        /// Selected row / active highlight
        static let selectionFill: Double = 0.08
        /// Context usage ring track
        static let ringTrack: Double = 0.20
        /// Recording action button fill. Keeps the active state visibly red even when solid fills are softened by platform materials.
        static let recordingActionFill: Double = 0.16
        /// Recording action button border. Stronger than the default border because it carries active-state color.
        static let recordingActionBorder: Double = 0.36
        /// Inline chip/pill fill (e.g. the tool card status pill).
        static let chipFill: Double = 0.14
        /// A primary action that cannot run yet: the brand colour at a third
        /// of its strength.
        static let disabledFill: Double = 0.35
    }

    /// Returns the appropriate surface fill opacity for the current color scheme.
    @MainActor
    static func surfaceFill(for scheme: ColorScheme) -> Double {
        scheme == .dark ? Opacity.surfaceFillDark : Opacity.surfaceFill
    }

    /// The card / chip surface fill as a colour.
    ///
    /// The opacity lives here, not in the View: POL-COLOR-09 wants every
    /// `.opacity(` out of the View layer, and the thinking pill and the
    /// thinking card have to share one fill to look like one element.
    @MainActor
    static func surfaceFillColor(for scheme: ColorScheme) -> Color {
        Neutral.text.opacity(scheme == .dark ? Opacity.surfaceFillDark : Opacity.surfaceFill)
    }

    /// A fill dimmed to the "cannot run yet" strength.
    ///
    /// The opacity lives here rather than in the View: POL-COLOR-09 wants
    /// every `.opacity(` out of the View layer, so a View asks for a colour
    /// and never composes one.
    @MainActor
    static func dimmedFill(_ color: Color) -> Color {
        color.opacity(Opacity.disabledFill)
    }

    /// The quiet border stroke drawn over the given ink.
    @MainActor
    static func stroke(of ink: Color, scheme: ColorScheme) -> Color {
        ink.opacity(scheme == .dark ? Opacity.borderStrokeDark : Opacity.borderStroke)
    }

    /// Returns the appropriate border stroke opacity for the current color scheme.
    @MainActor
    static func borderStroke(for scheme: ColorScheme) -> Double {
        scheme == .dark ? Opacity.borderStrokeDark : Opacity.borderStroke
    }
}

// MARK: - Typography Scale

enum DesignTypography {

    /// Display — session titles, empty state headlines
    static let display: Font = .title3.weight(.semibold)

    /// Headline — section headers, card titles
    static let headline: Font = .headline

    /// Body — chat message text (AI replies). Apple's Callout (16pt), not the
    /// 17pt Body: a transcript is dense text, and 16pt is the size Apple's
    /// own chat-style content uses.
    static let body: Font = .callout

    /// Body prominent — user messages. Same size as the body, distinguished by
    /// weight, the way the type scale specifies it.
    static let bodyProminent: Font = .callout.weight(.medium)

    /// Meta — timestamps, status labels, tool names
    static let meta: Font = .footnote

    /// Micro — tool input/output, code paths, detailed info
    static let micro: Font = .caption

    /// Micro monospaced — code, file paths
    static let microMono: Font = .system(.caption, design: .monospaced)
}

// MARK: - Spacing Scale

enum DesignSpacing {

    /// Extra small — tight internal padding (4pt)
    static let xs: CGFloat = 4
    /// Small — compact gaps (8pt)
    static let sm: CGFloat = 8
    /// Medium — standard gaps (12pt)
    static let md: CGFloat = 12
    /// Large — comfortable gaps (16pt)
    static let lg: CGFloat = 16
    /// Extra large — section separation (20pt)
    static let xl: CGFloat = 20
    /// Double extra large — major section breaks (24pt)
    static let xxl: CGFloat = 24

    /// Inline chip padding — the thinking pill and the tool card header.
    /// A chip is tighter than a card: it hugs its one-line label.
    static let chipHorizontal: CGFloat = 10
    static let chipVertical: CGFloat = 6
    /// Chat message vertical spacing
    static let messageVertical: CGFloat = 20
    /// Card internal padding
    static let cardPadding: CGFloat = 12
    /// Card to context gap
    static let cardGap: CGFloat = 16
}

// MARK: - Control Sizes

enum DesignControls {
    static let indicatorSize: CGFloat = 6

    /// Longest user message bubble. Keeps the bubble reading as a bubble
    /// instead of a full-width band, on phones and on the iPad chat column.
    static let userBubbleMaxWidth: CGFloat = 320
    static let indicatorSizeEmphasis: CGFloat = 8
    static let indicatorColumnWidth: CGFloat = DesignSpacing.md
    static let indicatorColumnWidthMaximum: CGFloat = 18
    static let indicatorSizeMaximum: CGFloat = 9
    static let indicatorSizeEmphasisMaximum: CGFloat = 12

    #if os(visionOS)
    /// Larger chat composer action buttons for gaze interaction on Apple Vision Pro.
    static let composerActionButtonSize: CGFloat = 48
    static let composerPrimaryActionButtonSize: CGFloat = 56
    static let composerActionButtonSpacing: CGFloat = 18
    static let composerActionIconFont: Font = .title3
    static let composerContainerHorizontalPadding: CGFloat = 32
    static let composerContainerVerticalPadding: CGFloat = 20
    static let composerTextMinHeight: CGFloat = 48
    static let composerTextMaxHeight: CGFloat = 160
    static let toolOpenFileIconFont: Font = .title3
    static let toolOpenFileButtonSize: CGFloat = 44
    #else
    /// Compact chat composer action buttons for iPhone and iPad.
    static let composerActionButtonSize: CGFloat = 32
    static let composerPrimaryActionButtonSize: CGFloat = 32
    static let composerActionButtonSpacing: CGFloat = DesignSpacing.sm
    static let composerActionIconFont: Font = .callout
    static let composerContainerHorizontalPadding: CGFloat = 16
    static let composerContainerVerticalPadding: CGFloat = 10
    static let composerTextMinHeight: CGFloat = 32
    /// ~4 body-text lines: the composer block is always visible and does not
    /// collapse, so the input caps lower than it used to (~5 lines).
    static let composerTextMaxHeight: CGFloat = 80
    static let toolOpenFileIconFont: Font = DesignTypography.micro
    static let toolOpenFileButtonSize: CGFloat = 24
    #endif
}

// MARK: - Corner Radius

enum DesignCorners {

    /// Small radius — tags, inline elements (6pt)
    static let small: CGFloat = 6
    /// Medium radius — cards, buttons (12pt)
    static let medium: CGFloat = 12
    /// Large radius — message bubbles, sheets (16pt)
    static let large: CGFloat = 16
    /// Capsule — pill-shaped elements (system)
    static let capsule: CGFloat = .infinity
}

// MARK: - Animation Presets

enum DesignAnimation {

    /// Named timing constants for every preset. The budget (QT-MOTION):
    /// springs respond in ≤ 0.35 s and transitions run ≤ 0.30 s — asserted
    /// by `DesignTokenTests`, which reads these values directly (`Animation`
    /// itself is opaque and cannot be introspected).
    enum Timing {
        static let maxResponse: TimeInterval = 0.35
        static let maxDuration: TimeInterval = 0.30

        static let quickDuration: TimeInterval = 0.15
        static let standardDuration: TimeInterval = 0.25
        static let springResponse: TimeInterval = 0.35
        static let springDamping: Double = 0.80
        /// Known deviation: exceeds the 0.35 s response ceiling (POL-MOTION-07).
        static let gentleSpringResponse: TimeInterval = 0.40
        static let gentleSpringDamping: Double = 0.85
        static let snappyResponse: TimeInterval = 0.25
        static let snappyDamping: Double = 0.70
    }

    /// Quick fade (0.15s) — status changes, minor updates
    static let quick = Animation.easeOut(duration: Timing.quickDuration)

    /// Standard transition (0.25s) — content appearance
    static let standard = Animation.easeOut(duration: Timing.standardDuration)

    /// Smooth spring — card expand/collapse, sheet interactions
    static let spring = Animation.spring(response: Timing.springResponse, dampingFraction: Timing.springDamping)

    /// Gentle spring — message appearance
    static let gentleSpring = Animation.spring(response: Timing.gentleSpringResponse, dampingFraction: Timing.gentleSpringDamping)

    /// Snappy spring — button presses, micro-interactions
    static let snappy = Animation.spring(response: Timing.snappyResponse, dampingFraction: Timing.snappyDamping)

    /// Breathing animation for empty state logo — a 3 s ambient loop, exempt
    /// from the transition budget (QT-EMPTY / POL-STATE-02).
    static let breathing = Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
}

// MARK: - Shadow Presets

enum DesignShadow {

    /// Subtle elevation for action cards
    static let subtle = Color.black.opacity(0.04)

    /// Medium elevation for modals / sheets
    static let medium = Color.black.opacity(0.08)

    /// Strong elevation for floating elements
    static let strong = Color.black.opacity(0.12)
}
