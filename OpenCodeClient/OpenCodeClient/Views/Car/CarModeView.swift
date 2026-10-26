import SwiftUI


enum CarSpeechAttemptGate {
    static func accepts(
        _ attemptID: UUID,
        activeAttemptID: UUID?,
        generation: UUID,
        currentGeneration: UUID
    ) -> Bool {
        attemptID == activeAttemptID && generation == currentGeneration
    }
}

struct CarModeView: View {
    var state: AppState

    var body: some View {
        AmbientVoiceView(state: state)
    }
}
