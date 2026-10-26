//
//  DesignTokenTests.swift
//  OpenCodeClientTests
//
//  Token-layer assertions for the Quiet Tech spec (PRY-13): colour hexes,
//  corner radii, spacing, the type scale, and the motion budget.
//
//  Values that currently deviate from the spec are asserted inside
//  `withKnownIssue` with the audit row that tracks them: the suite is green
//  today, fails the moment a conforming value regresses, and the known-issue
//  wrappers come off as the P2–P4 migrations land.
//

import Testing
import SwiftUI
@testable import OpenCodeClient
#if canImport(UIKit)
import UIKit
#endif

/// Resolve a Color to its sRGB hex for token-value assertions. The token
/// file declares colours as labelled components, so comparing through the
/// rendered value survives refactors of the declaration form.
private func hex(_ color: Color) -> String {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return "#??????"
    }
    return String(
        format: "#%02X%02X%02X",
        Int((red * 255).rounded()),
        Int((green * 255).rounded()),
        Int((blue * 255).rounded())
    )
}

struct DesignTokenTests {

    // MARK: Brand colour (POL-COLOR-05, QT-PALETTE)

    /// 2026-10-26: the app adopts the Warm Editorial palette — the single
    /// accent is terracotta, not blue (supersedes the Quiet Tech value and
    /// the 2026-10-25 A1 decision).
    @Test func brandPrimaryIsTheSingleTerracotta() {
        #expect(hex(DesignColors.Brand.primary) == "#C96442")
    }

    /// The accent step for small text: darkened on light surfaces, lifted on
    /// dark ones (terracotta on ivory is ≈3.3:1 — fine for icons, tight for
    /// body-size text).
    @Test func brandPrimaryTextAdaptsToColorScheme() {
        let ui = UIColor(DesignColors.Brand.primaryText)
        let light = UIColor(DesignColors.Brand.primaryText).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(hex(Color(uiColor: light)) == "#B4573A")
        #expect(hex(Color(uiColor: dark)) == "#D2704C")
    }

    @Test func brandGoldIsTheSessionPendingGold() {
        #expect(hex(DesignColors.Brand.gold) == "#D9A621")
    }

    // The light brand variant (#2563EB) has no token yet (audit POL-COLOR-05
    // PARTIAL); it is asserted here the day P2 adds `Brand.primaryLight`.

    // MARK: Page (QT-PALETTE, Warm Editorial)

    @Test func pageTokensAreTheWarmIvoryAndWarmNearBlack() {
        #expect(hex(DesignColors.Page.background(for: .light)) == "#FAF9F5")
        #expect(hex(DesignColors.Page.background(for: .dark)) == "#242422")
        #expect(hex(DesignColors.Page.foreground(for: .light)) == "#292823")
        #expect(hex(DesignColors.Page.foreground(for: .dark)) == "#EFEEE8")
    }

    // MARK: Neutral surfaces (POL-COLOR-02/03, QT-PALETTE)

    @Test func darkSurfaceTokensMatchTheSpecHexes() {
        #expect(hex(DesignColors.Neutral.surfaceDark) == "#1E1D1B")
        #expect(hex(DesignColors.Neutral.composerDark) == "#191816")
    }

    @Test func lightSurfaceTokensMatchTheirDocumentedValues() {
        #expect(hex(DesignColors.Neutral.surfaceLight) == "#F4F1EC")
        #expect(hex(DesignColors.Neutral.composerLight) == "#F1EDE6")
    }

    // MARK: Text tokens (POL-COLOR-04, QT-PALETTE)

    @Test func textTokensMatchTheSpecHexes() {
        withKnownIssue("POL-COLOR-04 (audit): the text tokens are still system colours; P2 swaps them to #ECEDEE / #9BA1A6 / #5A6066.") {
            #expect(hex(DesignColors.Neutral.text) == "#ECEDEE")
            #expect(hex(DesignColors.Neutral.textSecondary) == "#9BA1A6")
            #expect(hex(DesignColors.Neutral.textTertiary) == "#5A6066")
        }
    }

    // MARK: Corner radii (POL-COLOR-18, QT-CARD)

    @Test func cornerRadiiAreTheSpecSet() {
        #expect(DesignCorners.small == 6)
        #expect(DesignCorners.medium == 12)
        #expect(DesignCorners.large == 16)
    }

    // MARK: Spacing (QT-MESSAGE)

    @Test func messageVerticalIsTwentyPointsOnCompact() {
        #expect(DesignSpacing.messageVertical == 20)
    }

    @Test func cardPaddingMatchesTheGoverningClause() {
        withKnownIssue("POL-MESSAGE-05 (audit): cardPadding is 12; QT-MESSAGE specifies 14 pt (iPhone) / 18 pt (iPad).") {
            #expect(DesignSpacing.cardPadding == 14)
        }
    }

    // MARK: Type scale (POL-TYPE-01…06, QT-TYPE, decision D1 — PRY-22 gates the device check)

    /// The D1 target scale (QT-TYPE): exactly these four steps. P3 replaces
    /// the semantic system fonts with `Font.custom(..., relativeTo:)` at
    /// exactly these sizes; until then the roles pin to their documented
    /// system-font forms.
    private static let targetScale: [String: CGFloat] =
        ["display": 22, "body": 16, "meta": 13, "micro": 12]

    @Test func targetScaleIsTheSpecFourStepSet() {
        #expect(Set(DesignTokenTests.targetScale.values) == [22, 16, 13, 12])
    }

    @Test func typeRolesArePinnedToTheirDocumentedForms() {
        #expect(DesignTypography.display == .title3.weight(.semibold))
        #expect(DesignTypography.headline == .headline)
        #expect(DesignTypography.body == .callout)
        #expect(DesignTypography.bodyProminent == .callout.weight(.medium))
        #expect(DesignTypography.meta == .footnote)
        #expect(DesignTypography.micro == .caption)
        #expect(DesignTypography.microMono == .system(.caption, design: .monospaced))
    }

    @Test func displayUsesThe22PointSpecSize() {
        withKnownIssue("POL-TYPE-01/02 (audit): display is still title3 (20 pt) and headline sits outside the scale; the 22/16/13/12 D1 forms land with the P3 type migration.") {
            #expect(DesignTypography.display == .system(size: 22, weight: .semibold))
        }
    }

    // MARK: Motion budget (POL-MOTION-07, QT-MOTION)

    @Test func conformingPresetsStayWithinTheMotionBudget() {
        #expect(DesignAnimation.Timing.springResponse <= DesignAnimation.Timing.maxResponse)
        #expect(DesignAnimation.Timing.snappyResponse <= DesignAnimation.Timing.maxResponse)
        #expect(DesignAnimation.Timing.quickDuration <= DesignAnimation.Timing.maxDuration)
        #expect(DesignAnimation.Timing.standardDuration <= DesignAnimation.Timing.maxDuration)
    }

    @Test func gentleSpringStaysWithinTheResponseCeiling() {
        withKnownIssue("POL-MOTION-07 (audit): gentleSpring responds in 0.4 s, over the 0.35 s ceiling; it is retimed with the P4 motion work.") {
            #expect(DesignAnimation.Timing.gentleSpringResponse <= DesignAnimation.Timing.maxResponse)
        }
    }
}
