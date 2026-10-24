import Foundation
import os

/// Redeems an `opencode pair` code.
///
/// The pairing code is exchanged for a session token at
/// `GET /auth/connect/<code>`. The token is accepted anywhere the server
/// password is, so it becomes the host's Basic-auth password (username
/// `opencode`). The code is single-use and expires in five minutes.
actor PairingClient {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "PairingClient"
    )

    enum PairingError: LocalizedError {
        case expired
        case unreachable([String])
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .expired:
                return "This pairing link has expired or was already used. Run `opencode pair` again."
            case .unreachable:
                return "Could not reach the server at \(self.urls.joined(separator: ", "))."
            case .invalidResponse:
                return "The server did not return a pairing token."
            }
        }

        private var urls: [String] {
            if case .unreachable(let urls) = self { return urls }
            return []
        }
    }

    /// The result of a successful redemption.
    struct Pairing: Equatable {
        /// The server address the token belongs to.
        let url: String
        /// The session token, used as the Basic-auth password.
        let token: String
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Redeem a pairing code against the link's addresses.
    ///
    /// The code is single-use, so only the first address that answers can
    /// succeed. The addresses are tried in order, and the first reachable
    /// one wins.
    func redeem(_ link: PairingLink) async throws -> Pairing {
        var lastError: Error?
        for url in link.urls {
            do {
                let token = try await redeem(code: link.code, at: url)
                return Pairing(url: url, token: token)
            } catch let error as PairingError {
                // An expired code is the server's answer, not a transport
                // problem: stop trying the other addresses.
                if case .expired = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }
        if let error = lastError as? PairingError { throw error }
        throw PairingError.unreachable(link.urls)
    }

    /// Redeem one code against one address.
    private func redeem(code: String, at url: String) async throws -> String {
        let endpoint = "\(url)/auth/connect/\(code)"
        guard let built = URL(string: endpoint) else { throw PairingError.invalidResponse }
        var request = URLRequest(url: built)
        // A browser asks for HTML and gets a redirect; an API client asks for
        // JSON and gets the token.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["token"] as? String,
                  !token.isEmpty else {
                throw PairingError.invalidResponse
            }
            return token
        case 401, 403:
            throw PairingError.expired
        default:
            throw PairingError.invalidResponse
        }
    }
}
