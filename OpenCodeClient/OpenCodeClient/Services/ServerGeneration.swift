import Foundation

/// Which OpenCode server API a host speaks.
///
/// The app talks V1 (`/global/health`, `/session`, …). A V2 server answers
/// those paths with the packaged SPA shell, so the generation has to be probed
/// before any request is routed. `auto` is the stored default: it means "probe
/// on connect". `unrecognized` is a probe result only — it is never stored on
/// a host profile.
nonisolated enum ServerGeneration: String, Codable, Equatable, Sendable {
    /// Stored on a host profile: probe the server to decide.
    case auto
    case v1
    case v2
    /// The server answered, but not as an OpenCode API.
    case unrecognized
}

/// Detection for the server generation.
///
/// The probe order is fixed: `GET /global/health` first, then
/// `GET /api/info`. A V1 server answers health with JSON; a V2 server answers
/// it with the SPA shell, which is *not* V1. Only then is `/api/info` tried,
/// and it is the V2 marker because it carries a string `version`.
///
/// Authentication failures (401/403) and transport failures never fall through
/// to the other probe — a wrong password must not be reported as an
/// unsupported server.
nonisolated enum ServerGenerationProbe {
    /// Classify a `GET /global/health` response.
    static func classify(healthStatus: Int, healthBody: Data) -> ServerGeneration {
        guard healthStatus == 200 else { return .unrecognized }
        guard let object = try? JSONSerialization.jsonObject(with: healthBody) as? [String: Any] else {
            // The V2 server answers every unknown path with the SPA shell.
            return .unrecognized
        }
        guard let version = object["version"] as? String, !version.isEmpty else { return .unrecognized }
        guard let healthy = object["healthy"] as? Bool, healthy else { return .unrecognized }
        return .v1
    }

    /// Classify a `GET /api/info` response.
    static func classify(infoStatus: Int, infoBody: Data) -> ServerGeneration {
        guard infoStatus == 200 else { return .unrecognized }
        guard let object = try? JSONSerialization.jsonObject(with: infoBody) as? [String: Any] else {
            return .unrecognized
        }
        guard let version = object["version"] as? String, !version.isEmpty else { return .unrecognized }
        return .v2
    }
}
