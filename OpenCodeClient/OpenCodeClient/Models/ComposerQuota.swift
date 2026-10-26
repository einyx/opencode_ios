//
//  ComposerQuota.swift
//  OpenCodeClient
//

import Foundation

/// The composer's usage caption: what this conversation has consumed — or,
/// once the host reports one, how much of the provider's allowance is left.
///
/// What the OpenCode server exposes today:
///
/// - `Session.tokens`: the session's cumulative token usage
///   (`input` / `output` / `reasoning` / `cache`).
/// - `Session.cost`: the session's cumulative cost, in USD.
/// - `ProviderModel.limit`: the model's static context/output limits. Those
///   are capabilities, not a balance — they do not shrink while a session
///   runs, so they can never stand in for a remaining quota.
///
/// What it exposes nowhere (session payload, provider payload, SSE stream):
/// a provider allowance. No credits, no remaining requests, no subscription
/// balance, no reset time. So there is no honest "74 credits left" number to
/// show today, and this type never invents one — it shows what is known and
/// degrades to nothing when nothing is known.
///
/// The allowance is the one thing a future server payload would add, and it
/// plugs in at exactly one place: the `AppState` adapter at the bottom of
/// this file. The caption view and every call site stay as they are.
nonisolated struct ComposerQuota: Equatable, Sendable {

    // MARK: - Allowance

    /// A provider-side allowance: how much of a plan is left.
    struct Allowance: Equatable, Sendable {
        /// How much is left, counted in `unit`s.
        let remaining: Int
        /// The unit one allowance is counted in, **singular** ("credit").
        /// The caption pluralises it for the count it shows, so a provider
        /// that reports 1 must send the singular form it wants read.
        let unit: String
        /// The window the allowance is measured over ("5h", "Weekly"), when
        /// the provider names one.
        let window: String?
        /// The total the allowance is measured against, when the provider
        /// reports one. The caption does not need it; a meter does.
        let total: Int?

        init(remaining: Int, unit: String, window: String? = nil, total: Int? = nil) {
            self.remaining = remaining
            self.unit = unit
            self.window = window
            self.total = total
        }
    }

    // MARK: - Reported usage

    /// Cumulative tokens consumed by this conversation — the session and the
    /// subagent sessions below it. `nil` when the host has not reported a
    /// total the app can stand behind.
    let sessionTokens: Int?
    /// Cumulative cost of this conversation, in USD. `nil` when unknown.
    let sessionCost: Double?
    /// The provider allowance, when the host reports one.
    let allowance: Allowance?

    init(sessionTokens: Int? = nil, sessionCost: Double? = nil, allowance: Allowance? = nil) {
        self.sessionTokens = sessionTokens
        self.sessionCost = sessionCost
        self.allowance = allowance
    }

    // MARK: - Caption

    /// The one-line caption, or `nil` when there is nothing honest to show
    /// (no allowance and no measurable usage).
    ///
    /// An allowance outranks the consumption: "74 credits left" is the
    /// answer this caption exists for, and what the conversation consumed is
    /// already on screen in the session list and the context sheet.
    var caption: String? {
        if let allowanceText { return allowanceText }
        return usageText
    }

    /// The spoken form of the caption — VoiceOver reads the number, not the
    /// glyph next to it.
    var accessibilityLabel: String? {
        if let allowance, allowance.remaining >= 0 {
            let unit = Self.pluralUnit(allowance.unit, count: allowance.remaining)
            var text = unit.isEmpty
                ? "\(allowance.remaining) remaining"
                : "\(allowance.remaining) \(unit) remaining"
            if let window = allowance.window, !window.isEmpty {
                text += ", \(window) window"
            }
            return text
        }
        return usageAccessibilityLabel
    }

    /// "74 credits left · 5h", or `nil` when there is no allowance to show.
    private var allowanceText: String? {
        guard let allowance, allowance.remaining >= 0 else { return nil }
        let unit = Self.pluralUnit(allowance.unit, count: allowance.remaining)
        var text = unit.isEmpty
            ? "\(allowance.remaining) left"
            : "\(allowance.remaining) \(unit) left"
        if let window = allowance.window, !window.isEmpty {
            text += " · \(window)"
        }
        return text
    }

    /// What this conversation consumed: tokens and cost, each only when the
    /// host reported it.
    private var usageText: String? {
        let segments = usageSegments
        guard !segments.isEmpty else { return nil }
        return segments.joined(separator: " · ") + " used"
    }

    private var usageAccessibilityLabel: String? {
        let segments = usageSegments
        guard !segments.isEmpty else { return nil }
        return "Session usage: " + segments.joined(separator: ", ")
    }

    private var usageSegments: [String] {
        var segments: [String] = []
        if let tokens = reportableTokens {
            // The app's canonical compact token format — the one the session
            // status line uses. Reused (not copied) so the composer and the
            // session list can never print the same number two ways; its
            // canonical home would be `Message`, but moving it means editing
            // `MessageRowView.swift`, which this change does not touch.
            let count = MessageRowView.compactTokenCount(tokens)
            segments.append("\(count) \(tokens == 1 ? "token" : "tokens")")
        }
        if let cost = reportableCost {
            segments.append(Self.costText(cost))
        }
        return segments
    }

    /// Tokens the app can report. A negative count is a malformed payload
    /// rather than a measurement, so it is treated as unknown; zero means
    /// nothing was consumed, which is nothing worth a caption.
    private var reportableTokens: Int? {
        guard let tokens = sessionTokens, tokens > 0 else { return nil }
        return tokens
    }

    /// Cost the app can report. Negative or non-finite is malformed, zero
    /// means nothing was billed.
    private var reportableCost: Double? {
        guard let cost = sessionCost, cost.isFinite, cost > 0 else { return nil }
        return cost
    }

    // MARK: - Formatting

    /// Money in USD. A non-zero cost that rounds away shows "<$0.01":
    /// "$0.00 used" would claim the conversation was free.
    static func costText(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        if cost < 1_000 { return String(format: "$%.2f", cost) }
        return String(format: "$%.1fk", cost / 1_000)
    }

    /// The unit label for a count: "credit" + 1 → "credit", + 74 →
    /// "credits". English only — a localised unit needs its plural form
    /// from the provider. An empty unit yields an empty string, and the
    /// caption shows the bare count rather than inventing a unit.
    static func pluralUnit(_ unit: String, count: Int) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return count == 1 ? trimmed : trimmed + "s"
    }
}

// MARK: - AppState adapter

extension AppState {
    /// The composer caption's data, read from what the host already
    /// reported.
    ///
    /// This is the one place a provider allowance would enter the app. The
    /// OpenCode server sends none today, so `allowance` stays `nil` and the
    /// caption degrades to what the conversation consumed. When the server
    /// starts sending one, only this adapter changes: the caption view and
    /// its call sites do not move.
    ///
    /// Tokens and cost cover the whole conversation tree — the session and
    /// the subagent sessions below it — so the two numbers in the caption
    /// always describe the same scope.
    var composerQuota: ComposerQuota {
        guard let sessionID = currentSessionID else { return ComposerQuota() }
        let cost = sessionGroup(including: sessionID).compactMap(\.cost).reduce(0, +)
        return ComposerQuota(
            sessionTokens: sessionTotalTokens(sessionID: sessionID),
            sessionCost: cost > 0 ? cost : nil,
            allowance: nil
        )
    }
}
