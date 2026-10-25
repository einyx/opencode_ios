import Foundation

/// A pairing link printed by `opencode pair`.
///
/// The command prints one link per reachable server address
/// (`http://<host>:<port>/auth/connect/<code>`) and a QR code carrying the
/// same code with every reachable address as `{"code":…,"urls":[…]}`.
///
/// The code is single-use and expires in five minutes.
/// Whether a redeemed pairing may replace the address of a host without
/// asking the user.
///
/// A pairing code names the server it belongs to, and the host it lands in can
/// already point somewhere else. Replacing that address silently would let a
/// scanned code repoint a host the user named themselves, so the user has to
/// confirm it.
enum PairingReplacementPolicy {
    static func needsConfirmation(currentURL: String, pairedURL: String) -> Bool {
        let current = currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        return current != pairedURL
    }
}

nonisolated struct PairingLink: Equatable {
    let code: String
    let urls: [String]

    /// Parse a scanned QR payload or a pasted pairing link.
    ///
    /// Only a pairing link is accepted. A bare server address is not one: the
    /// path has to be exactly `/auth/connect/<code>`, so a host the user typed
    /// by mistake is never redeemed as a code.
    static func parse(_ value: String) -> PairingLink? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{") {
            return parsePayload(trimmed)
        }
        return parseURL(trimmed)
    }

    /// The QR payload: `{"code":…,"urls":[…]}`.
    private static func parsePayload(_ value: String) -> PairingLink? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
              let code = object["code"] as? String,
              isValidCode(code),
              let rawURLs = object["urls"] as? [Any] else {
            return nil
        }
        var urls: [String] = []
        for raw in rawURLs {
            guard let string = raw as? String, let address = serverAddress(string) else { return nil }
            guard !urls.contains(address) else { continue }
            urls.append(address)
        }
        guard !urls.isEmpty else { return nil }
        return PairingLink(code: code, urls: urls)
    }

    /// The printed link: `http://<host>:<port>/auth/connect/<code>`.
    private static func parseURL(_ value: String) -> PairingLink? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let code = connectPathCode(components.path),
              isValidCode(code),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        var authority = host
        if let port = components.port {
            authority += ":\(port)"
        }
        return PairingLink(code: code, urls: ["\(scheme)://\(authority)"])
    }

    /// The last path segment of `/auth/connect/<code>`, and nothing else.
    private static func connectPathCode(_ path: String) -> String? {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // "/auth/connect/<code>" splits into ["", "auth", "connect", "<code>"].
        guard segments.count == 4,
              segments[0].isEmpty,
              segments[1] == "auth",
              segments[2] == "connect",
              !segments[3].isEmpty else {
            return nil
        }
        return segments[3]
    }

    /// A server address the app can talk to.
    private static func serverAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        var authority = host
        if let port = components.port {
            authority += ":\(port)"
        }
        return "\(scheme)://\(authority)"
    }

    /// The server issues base64url codes: letters, digits, `_` and `-`.
    /// A code is only usable once it is complete.
    ///
    /// The server issues `randomBytes(16).toString("base64url")` codes, which
    /// are 22 characters long. A shorter prefix is what the field contains
    /// while a link is still being typed, and redeeming it would spend the
    /// single-use code on a typo.
    private static func isValidCode(_ code: String) -> Bool {
        guard code.count >= 16, code.count <= 128 else { return false }
        return code.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }
}
