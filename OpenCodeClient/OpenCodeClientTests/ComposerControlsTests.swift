import Foundation
import Testing
@testable import OpenCodeClient

@MainActor
struct ComposerControlsTests {
    private func makeState(_ defaults: UserDefaults) -> AppState {
        AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
    }

    @Test func defaultsAreRightHandedWithImages() {
        let defaults = UserDefaults(suiteName: "composer-controls.\(UUID())")!
        let state = makeState(defaults)
        #expect(state.composerActionSide == .right)
        #expect(state.showImageAttachmentButton)
        // Fresh installs default to Apple on-device speech, which needs no
        // token — so voice is configured out of the box.
        #expect(state.speechRecognitionEngine == .appleOnDevice)
        #expect(state.isChatSpeechConfigured)
    }

    @Test func choicesPersistWithoutBecomingSessionOrHostScoped() {
        let defaults = UserDefaults(suiteName: "composer-controls.\(UUID())")!
        let state = makeState(defaults)
        state.composerActionSide = .left
        state.showImageAttachmentButton = false
        state.currentSessionID = "other-session"
        state.currentHostProfileID = UUID()
        #expect(state.composerActionSide == .left)
        #expect(!state.showImageAttachmentButton)
        let restored = makeState(defaults)
        #expect(restored.composerActionSide == .left)
        #expect(!restored.showImageAttachmentButton)
    }

    @Test func invalidSideFallsBackToRightAndExplicitFalseSurvives() {
        let defaults = UserDefaults(suiteName: "composer-controls.\(UUID())")!
        defaults.set("invalid", forKey: AppState.composerActionSideKey)
        defaults.set(false, forKey: AppState.showImageAttachmentButtonKey)
        let state = makeState(defaults)
        #expect(state.composerActionSide == .right)
        #expect(!state.showImageAttachmentButton)
    }

    @Test func speechConfigurationUsesTokenWithoutRequiringConnectionTest() {
        let defaults = UserDefaults(suiteName: "composer-controls.\(UUID())")!
        let state = makeState(defaults)
        // Cloud engines require the AI Builder token; the connection test is
        // not involved in the configured check.
        state.speechRecognitionEngine = .gptLiveTranscribe
        state._aiBuilderToken = " \n "
        #expect(!state.isChatSpeechConfigured)
        state._aiBuilderToken = "fixture-token"
        #expect(!state.aiBuilderConnectionOK)
        #expect(state.isChatSpeechConfigured)
        state._aiBuilderToken = ""
        #expect(!state.isChatSpeechConfigured)
        // A missing token does not discard the user's preference.
        state.voiceFirstInput = true
        #expect(state.voiceFirstInput)
    }
}
