//
//  DeviceVoiceSourceGuards.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

/// Guards on the shape of the voice code, not on its behaviour.
///
/// Three invariants cannot be expressed in a unit test because they are
/// about what the source *is*:
///
/// 1. No credential for a hosted voice service survives anywhere in the app.
/// 2. The watch target never grows a speech-recognition import — watchOS
///    ships no `Speech.framework`, so such a build would not compile, and
///    the point is that nobody tries.
/// 3. The watch's `begin` reply carries the run id and nothing else, so no
///    credential can cross the WatchConnectivity boundary.
@Suite
struct DeviceVoiceSourceGuards {
    /// The repo root, three directories up from this file.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // OpenCodeClientTests
            .deletingLastPathComponent()  // OpenCodeClient
            .deletingLastPathComponent()  // repo root
    }

    /// The app's source tree.
    private static var appSources: URL {
        repoRoot.appendingPathComponent("OpenCodeClient/OpenCodeClient")
    }

    /// The watch's source tree.
    private static var watchSources: URL {
        repoRoot.appendingPathComponent("OpenCodeClient/OpenCodeWatch")
    }

    private static func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    /// No hosted voice credential survives in the app.
    @Test func noHostedVoiceCredentialSurvives() throws {
        let banned = ["aiBuilderToken", "aiBuilderBaseURL", "aiBuilderCustomPrompt", "aiBuilderTerminology"]
        var offenders: [String] = []
        for file in Self.swiftFiles(in: Self.appSources) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for name in banned where text.contains(name) {
                offenders.append("\(file.lastPathComponent): \(name)")
            }
        }
        #expect(offenders.isEmpty, "a hosted voice credential survived: \(offenders)")
    }

    /// The app does not link a cloud speech client.
    @Test func theAppLinksNoCloudSpeechClient() throws {
        let project = Self.repoRoot
            .appendingPathComponent("OpenCodeClient/OpenCodeClient.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: project, encoding: .utf8)
        #expect(!text.contains("VoiceFlowKit"), "the hosted voice package is still linked")
        #expect(!text.contains("einyx/voiceflow"), "the hosted voice package is still referenced")
    }

    /// The watch never grows a speech-recognition import.
    @Test func theWatchHasNoSpeechRecognitionImport() throws {
        var offenders: [String] = []
        for file in Self.swiftFiles(in: Self.watchSources) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for banned in ["import Speech", "import SpeechAnalyzer", "SFSpeechRecognizer", "SpeechAnalyzer"]
            where text.contains(banned) {
                offenders.append("\(file.lastPathComponent): \(banned)")
            }
        }
        #expect(offenders.isEmpty, "the watch grew a speech-recognition path: \(offenders)")
    }

    /// The watch's `begin` reply carries the run id and nothing else.
    @Test func theWatchBeginReplyCarriesNoCredential() throws {
        let bridge = Self.repoRoot
            .appendingPathComponent("OpenCodeClient/OpenCodeClient/Services/WatchPhoneBridge.swift")
        let text = try String(contentsOf: bridge, encoding: .utf8)
        // The `begin` reply is the one line that hands the watch its run.
        let beginReply = text
            .split(separator: "\n")
            .first { $0.contains("return [\"run\": id]") }
        #expect(beginReply != nil, "the bridge should answer `begin` with the run id")
        let reply = try #require(beginReply)
        #expect(!reply.contains("portal"))
        #expect(!reply.contains("token"))
        #expect(!reply.contains("url"))
    }
}
