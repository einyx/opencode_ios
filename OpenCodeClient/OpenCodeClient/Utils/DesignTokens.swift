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
        /// Primary brand — the single identity color of the "Quiet Tech" design
        /// language. Electric blue #3B82F6, used for every interactive/branded
        /// element (send, selection, links, the user-message left bar).
        static let primary = Color(red: 0.231, green: 0.510, blue: 0.965)
        /// Gold accent #D9A621. Session triage uses gold for pending user requests;
        /// execution uses the dedicated SessionIndicator.running token.
        static let gold = Color(red: 0.851, green: 0.651, blue: 0.129)
    }

    // MARK: Semantic

    enum Semantic {
        static let error = Color.red
        static let success = Color(red: 0.20, green: 0.65, blue: 0.35)
        static let warning = Color.orange
        static let info = Color(red: 0.25, green: 0.47, blue: 0.85)
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

        /// Subtle card / info surface background — light mode (#F0F1F3)
        static let surfaceLight = Color(red: 0.941, green: 0.945, blue: 0.953)
        /// Subtle card / info surface background — dark mode (#1A1D21)
        static let surfaceDark = Color(red: 0.102, green: 0.114, blue: 0.129)
        /// Composer input background — light mode (#F4F5F6, the secondary bg)
        static let composerLight = Color(red: 0.957, green: 0.961, blue: 0.965)
        /// Composer input background — dark mode (#141619, the secondary bg)
        static let composerDark = Color(red: 0.078, green: 0.086, blue: 0.098)
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
    }

    /// Returns the appropriate surface fill opacity for the current color scheme.
    @MainActor
    static func surfaceFill(for scheme: ColorScheme) -> Double {
        scheme == .dark ? Opacity.surfaceFillDark : Opacity.surfaceFill
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
