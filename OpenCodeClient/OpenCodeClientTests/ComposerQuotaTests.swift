import Foundation
import Testing
@testable import OpenCodeClient

/// The composer's usage caption: what it says about a session that reported
/// usage, how it degrades when the host reported nothing, and where its
/// boundaries are.
struct ComposerQuotaTests {

    // MARK: - Known quantities

    @Test func tokensOnlyCaption() {
        #expect(ComposerQuota(sessionTokens: 12_300).caption == "12.3K tokens used")
    }

    @Test func tokensAndCostShareOneLine() {
        let quota = ComposerQuota(sessionTokens: 12_300, sessionCost: 0.42)
        #expect(quota.caption == "12.3K tokens · $0.42 used")
    }

    @Test func costOnlyCaptionWhenNoTokensWereReported() {
        #expect(ComposerQuota(sessionCost: 0.42).caption == "$0.42 used")
    }

    @Test func aSingleTokenIsNotPluralised() {
        #expect(ComposerQuota(sessionTokens: 1).caption == "1 token used")
    }

    @Test func tokenCountsUseTheAppWideCompactFormat() {
        // Same formatter as the session status line, so the composer and the
        // session list can never print one number two ways.
        #expect(ComposerQuota(sessionTokens: 999).caption == "999 tokens used")
        #expect(ComposerQuota(sessionTokens: 1_000).caption == "1K tokens used")
        #expect(ComposerQuota(sessionTokens: 999_999).caption == "1M tokens used")
    }

    // MARK: - Allowance

    @Test func allowanceCaptionLeadsWithWhatIsLeft() {
        let quota = ComposerQuota(allowance: .init(remaining: 74, unit: "credit"))
        #expect(quota.caption == "74 credits left")
    }

    @Test func allowanceNamesItsWindow() {
        let quota = ComposerQuota(allowance: .init(remaining: 74, unit: "credit", window: "5h"))
        #expect(quota.caption == "74 credits left · 5h")
    }

    @Test func aSingleAllowanceUnitIsNotPluralised() {
        let quota = ComposerQuota(allowance: .init(remaining: 1, unit: "credit"))
        #expect(quota.caption == "1 credit left")
    }

    @Test func anExhaustedAllowanceIsStillReported() {
        // Zero remaining is information, not an absence of it.
        let quota = ComposerQuota(allowance: .init(remaining: 0, unit: "credit"))
        #expect(quota.caption == "0 credits left")
    }

    @Test func theAllowanceOutranksTheSessionUsage() {
        let quota = ComposerQuota(
            sessionTokens: 12_300,
            sessionCost: 0.42,
            allowance: .init(remaining: 74, unit: "credit")
        )
        #expect(quota.caption == "74 credits left")
    }

    @Test func anAllowanceWithoutAUnitShowsTheBareCount() {
        let quota = ComposerQuota(allowance: .init(remaining: 74, unit: "  "))
        #expect(quota.caption == "74 left")
    }

    @Test func aNegativeAllowanceIsIgnored() {
        let quota = ComposerQuota(
            sessionTokens: 12_300,
            allowance: .init(remaining: -1, unit: "credit")
        )
        #expect(quota.caption == "12.3K tokens used")
    }

    // MARK: - No information

    @Test func noInformationHidesTheCaption() {
        let quota = ComposerQuota()
        #expect(quota.caption == nil)
        #expect(quota.accessibilityLabel == nil)
    }

    @Test func aFreshSessionHasNothingToReport() {
        let quota = ComposerQuota(sessionTokens: 0, sessionCost: 0)
        #expect(quota.caption == nil)
        #expect(quota.accessibilityLabel == nil)
    }

    @Test func negativeNumbersAreTreatedAsUnknown() {
        #expect(ComposerQuota(sessionTokens: -5).caption == nil)
        #expect(ComposerQuota(sessionCost: -1).caption == nil)
    }

    @Test func aNonFiniteCostIsTreatedAsUnknown() {
        #expect(ComposerQuota(sessionCost: .nan).caption == nil)
        #expect(ComposerQuota(sessionCost: .infinity).caption == nil)
    }

    // MARK: - Boundaries

    @Test func aTinyCostDoesNotClaimZero() {
        #expect(ComposerQuota(sessionCost: 0.004).caption == "<$0.01 used")
    }

    @Test func aCostJustUnderAThousandStaysInCents() {
        #expect(ComposerQuota(sessionCost: 999.99).caption == "$999.99 used")
    }

    @Test func aLargeCostIsAbbreviated() {
        #expect(ComposerQuota(sessionCost: 1_234.5).caption == "$1.2k used")
    }

    // MARK: - Accessibility

    @Test func theAllowanceReadsAsRemaining() {
        let quota = ComposerQuota(allowance: .init(remaining: 74, unit: "credit", window: "5h"))
        #expect(quota.accessibilityLabel == "74 credits remaining, 5h window")
    }

    @Test func theUsageReadsAsSessionUsage() {
        let quota = ComposerQuota(sessionTokens: 12_300, sessionCost: 0.42)
        #expect(quota.accessibilityLabel == "Session usage: 12.3K tokens, $0.42")
    }

    // MARK: - AppState adapter

    @Test @MainActor func theAdapterIsEmptyWithoutASession() {
        let state = makeState()
        #expect(state.composerQuota.caption == nil)
    }

    @Test @MainActor func theAdapterReportsWhatTheSessionConsumed() {
        let state = makeState()
        state.sessions = [makeSession(id: "s1", tokensJSON: """
        {"total":12300,"input":10000,"output":2000,"reasoning":300}
        """, cost: 0.42)]
        state.currentSessionID = "s1"
        #expect(state.composerQuota.caption == "12.3K tokens · $0.42 used")
    }

    @Test @MainActor func theAdapterCoversTheWholeConversationTree() {
        let state = makeState()
        state.sessions = [
            makeSession(id: "s1", tokensJSON: """
            {"total":12300,"input":10000,"output":2000,"reasoning":300}
            """, cost: 0.42),
            makeSession(id: "s2", parentID: "s1", tokensJSON: """
            {"total":2300,"input":2000,"output":300,"reasoning":0}
            """, cost: 0.08)
        ]
        state.currentSessionID = "s1"
        #expect(state.composerQuota.caption == "14.6K tokens · $0.50 used")
    }

    @Test @MainActor func theAdapterReportsNothingWhenTheHostKnowsNothing() {
        let state = makeState()
        state.sessions = [makeSession(id: "s1")]
        state.currentSessionID = "s1"
        #expect(state.composerQuota.caption == nil)
    }

    // MARK: - Fixtures

    /// `AppState` is main-actor isolated, and every suite here builds one on
    /// an isolated `UserDefaults` so the session store never leaks between
    /// runs.
    @MainActor
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "opencode.tests.composerquota.\(UUID().uuidString)")!
        return AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
    }

    private func makeSession(
        id: String,
        parentID: String? = nil,
        tokensJSON: String? = nil,
        cost: Double? = nil
    ) -> Session {
        var session = Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/work",
            parentID: parentID,
            title: "t",
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
        if let tokensJSON {
            session.tokens = try! JSONDecoder().decode(
                Message.TokenInfo.self,
                from: tokensJSON.data(using: .utf8)!
            )
        }
        session.cost = cost
        return session
    }
}
