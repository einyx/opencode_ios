import SwiftUI
import VoiceFlowKit

enum PendingCarAudio {
    case file(URL, strategy: VoiceFlowRecordingStrategy)
    case preserved(VoiceFlowPreservedAudio)

    var strategy: VoiceFlowRecordingStrategy {
        switch self {
        case .file(_, let strategy): strategy
        case .preserved(let audio): audio.strategy
        }
    }
}

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
