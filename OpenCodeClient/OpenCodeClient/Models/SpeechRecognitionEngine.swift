import Foundation

/// Which recognizer turns a recording into text.
///
/// The app has one: Apple's on-device Speech recognition. It needs no
/// account, no token and no network — the audio never leaves the device. The
/// cloud strategies that needed an access token are gone.
enum SpeechRecognitionEngine: String, CaseIterable, Codable, Sendable {
    /// `SFSpeechRecognizer` with `requiresOnDeviceRecognition`. The default.
    case appleOnDevice

    /// Whether starting a recording needs a service credential. Nothing does.
    var usesVoiceFlowService: Bool { false }

    /// Whether recording opens a realtime session that streams partial
    /// transcripts while the user speaks. Nothing does.
    var usesRealtimeSession: Bool { false }

    /// Whether partial transcripts render in the composer during capture.
    var showsLivePartials: Bool { false }

    /// Resolves a persisted rawValue. Unknown values fall back to the
    /// tokenless default so a strategy removed in a later release cannot
    /// leave voice input permanently broken.
    static func resolved(fromRaw rawValue: String?) -> SpeechRecognitionEngine {
        guard let rawValue, !rawValue.isEmpty,
              SpeechRecognitionEngine(rawValue: rawValue) != nil else {
            return .appleOnDevice
        }
        return SpeechRecognitionEngine(rawValue: rawValue) ?? .appleOnDevice
    }
}
