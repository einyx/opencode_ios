//
//  ChatArtworkPlaceholders.swift
//  OpenCodeClient
//

import SwiftUI

/// Region placeholder for the chat's tool/activity area.
///
/// The chat's transcript is where the agent's tool output lands: tool cards,
/// thinking cards and turn-activity rows all render inside it. While the
/// session has produced turns but the agent has not run a single tool yet,
/// that region is empty — the wrench marks it, and it leaves the transcript as
/// soon as the first tool card arrives.
///
/// The drawing is decorative: it repeats no information the surrounding copy
/// does not already carry, so it stays out of the accessibility tree.
struct ToolActivityArtwork: View {
    /// A region placeholder, not a hero. The drawing must not compete with
    /// the conversation it sits in.
    static let side: CGFloat = 96

    var body: some View {
        Image("ToolsArt")
            .resizable()
            .scaledToFit()
            .frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }
}

/// Region placeholder for a session whose history holds no turns yet.
///
/// The transcript is a session's history, so an empty transcript is an empty
/// timeline — the clock says there is no time in it yet.
///
/// Decorative, like the rest of the artwork set.
struct SessionHistoryArtwork: View {
    /// The hero of an empty screen: big enough to read as a scene, small
    /// enough to stay a placeholder.
    static let side: CGFloat = 120

    var body: some View {
        Image("HistoryArt")
            .resizable()
            .scaledToFit()
            .frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }
}
