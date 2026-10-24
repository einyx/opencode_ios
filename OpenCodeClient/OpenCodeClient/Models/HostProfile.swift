import Foundation

enum HostTransport: String, Codable, Equatable, CaseIterable, Identifiable {
    case direct
    case sshTunnel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .direct: return L10n.t(.hostTransportDirect)
        case .sshTunnel: return L10n.t(.hostSSHTunnel)
        }
    }
}

enum ConnectionPhase: String, Codable, Equatable {
    case idle
    case sshGateway
    case sshAuth
    case localTunnel
    case health
    case bootstrap
    case connected
    case failed

    var label: String {
        switch self {
        case .idle: return L10n.t(.connectionPhaseIdle)
        case .sshGateway: return L10n.t(.connectionPhaseSSHGateway)
        case .sshAuth: return L10n.t(.connectionPhaseSSHAuth)
        case .localTunnel: return L10n.t(.connectionPhaseLocalTunnel)
        case .health: return L10n.t(.connectionPhaseHealth)
        case .bootstrap: return L10n.t(.connectionPhaseBootstrap)
        case .connected: return L10n.t(.connectionPhaseConnected)
        case .failed: return L10n.t(.connectionPhaseFailed)
        }
    }
}

struct ConnectionDiagnostic: Codable, Equatable {
    var hostProfileID: UUID?
    var phase: ConnectionPhase
    var message: String
    var recoveryHint: String?
    var timestamp: Date
}

struct BasicAuthConfig: Codable, Equatable {
    var username: String
    var keychainPasswordID: String
}

struct HostProfile: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var transport: HostTransport
    var serverURL: String
    var basicAuth: BasicAuthConfig?
    var ssh: SSHTunnelConfig?
    var lastUsedAt: Date?
    /// Which OpenCode API this host speaks. `auto` probes on connect. The
    /// value is bound to `serverURL`: changing the URL clears it.
    var apiGeneration: ServerGeneration = .auto

    private enum CodingKeys: String, CodingKey {
        case id, name, transport, serverURL, basicAuth, ssh, lastUsedAt, apiGeneration
    }

    init(
        id: UUID = UUID(),
        name: String,
        transport: HostTransport,
        serverURL: String,
        basicAuth: BasicAuthConfig? = nil,
        ssh: SSHTunnelConfig? = nil,
        lastUsedAt: Date? = nil,
        apiGeneration: ServerGeneration = .auto
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.serverURL = serverURL
        self.basicAuth = basicAuth
        self.ssh = ssh
        self.lastUsedAt = lastUsedAt
        self.apiGeneration = apiGeneration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        transport = try c.decode(HostTransport.self, forKey: .transport)
        serverURL = try c.decode(String.self, forKey: .serverURL)
        basicAuth = try c.decodeIfPresent(BasicAuthConfig.self, forKey: .basicAuth)
        ssh = try c.decodeIfPresent(SSHTunnelConfig.self, forKey: .ssh)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        // Hosts saved before V2 support have no generation stored.
        apiGeneration = try c.decodeIfPresent(ServerGeneration.self, forKey: .apiGeneration) ?? .auto
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.t(.hostUntitled) : trimmed
    }

    var connectionSummary: String {
        switch transport {
        case .direct:
            return serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        case .sshTunnel:
            guard let ssh else { return L10n.t(.hostSSHTunnel) }
            let host = ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(host):\(ssh.port) -> :\(ssh.remotePort)"
        }
    }

    static func defaultProfile(serverURL: String = APIClient.defaultServer) -> HostProfile {
        HostProfile(
            name: L10n.t(.hostDefaultLocalName),
            transport: .direct,
            serverURL: serverURL,
            basicAuth: nil,
            ssh: nil,
            lastUsedAt: Date()
        )
    }
}

struct HostProfileImportPayload: Codable {
    var version: Int?
    var name: String
    var transport: HostTransport
    var serverURL: String?
    var ssh: SSHTunnelConfig?

    func makeProfile() throws -> HostProfile {
        switch transport {
        case .direct:
            guard let serverURL, !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HostProfileError.invalidImport(L10n.t(.hostImportErrorDirectRequiresServerURL))
            }
            return HostProfile(name: name, transport: .direct, serverURL: serverURL, basicAuth: nil, ssh: nil)
        case .sshTunnel:
            guard var ssh else {
                throw HostProfileError.invalidImport(L10n.t(.hostImportErrorSSHTunnelRequiresSSHSettings))
            }
            ssh.isEnabled = true
            if let error = ssh.validationError {
                throw HostProfileError.invalidImport(error)
            }
            return HostProfile(
                name: name,
                transport: .sshTunnel,
                serverURL: serverURL ?? APIClient.defaultServer,
                basicAuth: nil,
                ssh: ssh
            )
        }
    }
}

struct HostProfileExportPayload: Codable, Equatable {
    var version = 1
    var name: String
    var transport: HostTransport
    var serverURL: String?
    var ssh: HostProfileExportSSH?
}

struct HostProfileExportSSH: Codable, Equatable {
    var host: String
    var port: Int
    var username: String
    var remotePort: Int
}

enum HostProfileError: LocalizedError, Equatable {
    case invalidImport(String)
    case cannotDeleteOnlyHost

    var errorDescription: String? {
        switch self {
        case .invalidImport(let message): return message
        case .cannotDeleteOnlyHost: return L10n.t(.hostDeleteOnlyHostError)
        }
    }
}
