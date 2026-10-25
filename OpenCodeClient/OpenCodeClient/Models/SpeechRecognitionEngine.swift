import Foundation
import VoiceFlowKit

/// Which recognizer turns a recording into text. Apple's on-device Speech
/// recognition needs no account, token, or network; the VoiceFlow strategies
/// stream through the AI Builder Space service and require a token.
enum SpeechRecognitionEngine: String, CaseIterable, Codable, Sendable {
    /// SFSpeechRecognizer with requiresOnDeviceRecognition. Default.
    case appleOnDevice
    case gptLiveTranscribe
    case openAIRealtime
    case grokBatch

    /// Whether starting a recording needs the AI Builder Space token.
    var usesVoiceFlowService: Bool {
        self != .appleOnDevice
    }

    /// Whether recording opens a realtime WebSocket session that streams
    /// partial transcripts while the user speaks.
    var usesRealtimeSession: Bool {
        self == .gptLiveTranscribe || self == .openAIRealtime
    }

    /// Whether partial transcripts render in the composer during capture.
    var showsLivePartials: Bool {
        self == .gptLiveTranscribe
    }

    /// The capture format handed to `VoiceFlowMicrophone`. Apple on-device
    /// reuses the lossless PCM16 WAV path of gptLiveTranscribe; the audio
    /// never leaves the device.
    var captureStrategy: VoiceFlowRecordingStrategy {
        switch self {
        case .appleOnDevice, .gptLiveTranscribe: .gptLiveTranscribe
        case .openAIRealtime: .openAIRealtime
        case .grokBatch: .grokBatch
        }
    }

    /// Resolves a persisted rawValue. Unknown values fall back to the
    /// tokenless default so a strategy removed in a later release cannot
    /// leave voice input permanently broken.
    static func resolved(fromRaw rawValue: String?) -> SpeechRecognitionEngine {
        guard let rawValue, !rawValue.isEmpty, let engine = SpeechRecognitionEngine(rawValue: rawValue) else {
            return .appleOnDevice
        }
        return engine
    }
}
