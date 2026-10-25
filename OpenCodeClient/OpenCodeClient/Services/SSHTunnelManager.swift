//
//  SSHTunnelManager.swift
//  OpenCodeClient
//

import Foundation
import Combine
#if os(visionOS)
import CryptoKit
#else
import Citadel
import NIOCore
import Crypto
import NIOSSH
import Network
#endif

enum SSHConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    static func == (lhs: SSHConnectionStatus, rhs: SSHConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum SSHKnownHostStore {
    private static let userDefaultsKey = "sshKnownHosts.openSSH"

    static func trustedOpenSSHKey(host: String, port: Int) -> String? {
        loadMap()[identity(host: host, port: port)]
    }

    static func trust(host: String, port: Int, openSSHKey: String) {
        var map = loadMap()
        map[identity(host: host, port: port)] = openSSHKey
        UserDefaults.standard.set(map, forKey: userDefaultsKey)
    }

    static func clear(host: String, port: Int) {
        var map = loadMap()
        map.removeValue(forKey: identity(host: host, port: port))
        UserDefaults.standard.set(map, forKey: userDefaultsKey)
    }

    static func fingerprint(host: String, port: Int) -> String? {
        guard let key = trustedOpenSSHKey(host: host, port: port) else { return nil }
        return fingerprint(openSSHKey: key)
    }

    static func fingerprint(openSSHKey: String) -> String {
        let components = openSSHKey.split(separator: " ")
        guard components.count >= 2, let keyData = Data(base64Encoded: String(components[1])) else {
            return "SHA256:invalid"
        }
        let digest = SHA256.hash(data: keyData)
        return "SHA256:\(Data(digest).base64EncodedString())"
    }

    private static func loadMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
    }

    private static func identity(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }
}

struct SSHHostKeyMismatch: Equatable {
    let host: String
    let port: Int
    let expectedFingerprint: String
    let presentedFingerprint: String
    let presentedOpenSSHKey: String
}

#if !os(visionOS)
private final class SSHTOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        if let trusted = SSHKnownHostStore.trustedOpenSSHKey(host: host, port: port) {
            if trusted == presented {
                validationCompletePromise.succeed(())
                return
            }
            validationCompletePromise.fail(
                SSHError.hostKeyMismatch(
                    expected: SSHKnownHostStore.fingerprint(openSSHKey: trusted),
                    got: SSHKnownHostStore.fingerprint(openSSHKey: presented),
                    presentedOpenSSHKey: presented
                )
            )
            return
        }

        // TOFU: trust the first successful host key for this host:port.
        SSHKnownHostStore.trust(host: host, port: port, openSSHKey: presented)
        validationCompletePromise.succeed(())
    }
}
#endif

struct SSHTunnelConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var host: String = ""
    var port: Int = 8006
    var username: String = "opencode"
    var remotePort: Int = 19001

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case host
        case port
        case username
        case remotePort
    }

    init(isEnabled: Bool = false, host: String = "", port: Int = 8006, username: String = "opencode", remotePort: Int = 19001) {
        self.isEnabled = isEnabled
        self.host = host
        self.port = port
        self.username = username
        self.remotePort = remotePort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8006
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? "opencode"
        remotePort = try container.decodeIfPresent(Int.self, forKey: .remotePort) ?? 19001
    }
    
    var isValid: Bool {
        !host.isEmpty && !username.isEmpty && port > 0 && remotePort > 0
    }

    var validationError: String? {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.t(.hostValidationVPSHostRequired)
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.t(.hostValidationSSHUsernameRequired)
        }
        if port <= 0 {
            return L10n.t(.hostValidationSSHPortPositive)
        }
        if remotePort <= 0 {
            return L10n.t(.hostValidationAssignedRemotePortPositive)
        }
        return nil
    }
    
    static let `default` = SSHTunnelConfig()
}

struct SSHOpenedTunnel {
    var id = UUID()
    var remotePort: Int
    var close: @MainActor () -> Void
}

nonisolated final class ListenerWait: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var resumed = false

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume() -> Bool {
        finish(nil)
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        finish(error)
    }

    private func finish(_ error: Error?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed, let continuation else { return false }
        resumed = true
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
        return true
    }
}

#if os(visionOS)
@MainActor
final class SSHTunnelManager: ObservableObject {
    @Published private(set) var status: SSHConnectionStatus = .disconnected
    @Published private(set) var trustedHostFingerprint: String?
    @Published private(set) var pendingHostKeyMismatch: SSHHostKeyMismatch?
    @Published var config: SSHTunnelConfig {
        didSet { saveConfig() }
    }

    private let configDefaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        configDefaults = defaults
        if let data = defaults.data(forKey: "sshTunnelConfig"),
           let decoded = try? JSONDecoder().decode(SSHTunnelConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        configDefaults.set(data, forKey: "sshTunnelConfig")
    }

    var reverseTunnelCommand: String? {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !username.isEmpty, config.remotePort > 0, config.port > 0 else { return nil }

        let portArg = config.port == 22 ? "" : " -p \(config.port)"
        return "ssh -N -T -R 127.0.0.1:\(config.remotePort):127.0.0.1:4096\(portArg) \(username)@\(host)"
    }

    func connect() async {
        status = .error(L10n.t(.hostSSHTunnelUnavailableVisionOS))
    }

    func disconnect(updateStatus: Bool = true) {
        if updateStatus {
            status = .disconnected
        }
    }

    func getPublicKey() -> String? {
        SSHKeyManager.getPublicKey()
    }

    func readPublicKey() throws -> String {
        try SSHKeyManager.getKeyPair()
    }

    func rotateKey() throws -> String {
        try SSHKeyManager.rotateKey()
    }

    func clearTrustedHost() {
        trustedHostFingerprint = nil
        pendingHostKeyMismatch = nil
    }

    func trustPendingHostKey() {
    }
}
#else
struct ListenerAttempt: Equatable, Sendable {
    var id: UUID
    var generation: UInt64
    var remotePort: Int
}

@MainActor
final class SSHTunnelManager: ObservableObject {
    @Published private(set) var status: SSHConnectionStatus = .disconnected
    @Published private(set) var trustedHostFingerprint: String?
    @Published private(set) var pendingHostKeyMismatch: SSHHostKeyMismatch?
    @Published var config: SSHTunnelConfig {
        didSet {
            saveConfig()
            trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: config.host, port: config.port)
        }
    }
    
    private var sshClient: SSHClient?
    private var listener: NWListener?
    private var connectTask: Task<Void, Never>?
    private var connectGeneration: UInt64 = 0
    private var listenerWait: ListenerWait?
    private var listenerAttempt: ListenerAttempt?
    private var connectedRemotePort: Int?
    private var activeTunnel: SSHOpenedTunnel?
    var tunnelConnector: (@MainActor (SSHTunnelConfig) async throws -> SSHOpenedTunnel)?
    var listenerReadyHook: (@MainActor () async throws -> Void)?
    private let localPort: NWEndpoint.Port = 4096
    private let configDefaults: UserDefaults

    var connectedRemotePortForTesting: Int? { connectedRemotePort }
    
    init(defaults: UserDefaults = .standard) {
        configDefaults = defaults
        if let data = defaults.data(forKey: "sshTunnelConfig"),
           let decoded = try? JSONDecoder().decode(SSHTunnelConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
        self.trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: self.config.host, port: self.config.port)
    }
    
    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        configDefaults.set(data, forKey: "sshTunnelConfig")
    }

    var reverseTunnelCommand: String? {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !username.isEmpty, config.remotePort > 0, config.port > 0 else { return nil }

        let portArg = config.port == 22 ? "" : " -p \(config.port)"
        return "ssh -N -T -R 127.0.0.1:\(config.remotePort):127.0.0.1:4096\(portArg) \(username)@\(host)"
    }
    
    nonisolated static func listenerWaitShouldResume(_ state: NWListener.State) -> Bool {
        switch state {
        case .ready, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    func connect() async {
        if let err = config.validationError {
            status = .error(err)
            return
        }

        let snapshot = config
        invalidateInFlightConnect(updateStatus: false)
        let generation = connectGeneration
        status = .connecting
        pendingHostKeyMismatch = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performConnect(generation: generation, snapshot: snapshot)
        }
        connectTask = task
        await task.value
        if connectTask == task {
            connectTask = nil
        }
    }

    func suspendListenerWaitForTesting(onInstalled: @MainActor () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listenerWait = ListenerWait(continuation)
            onInstalled()
        }
    }

    private func performConnect(generation: UInt64, snapshot: SSHTunnelConfig) async {
        do {
            if let tunnelConnector {
                let opened = try await tunnelConnector(snapshot)
                guard adopt(opened, generation: generation) else { return }
                if let listenerReadyHook {
                    try await listenerReadyHook()
                }
                guard generation == connectGeneration, !Task.isCancelled else {
                    closeIfStillActive(opened)
                    return
                }
                connectedRemotePort = snapshot.remotePort
                status = .connected
                return
            }
            try await establishTunnel(generation: generation, snapshot: snapshot)
            guard generation == connectGeneration, !Task.isCancelled else { return }
            connectedRemotePort = snapshot.remotePort
            status = .connected
        } catch {
            guard generation == connectGeneration, !Task.isCancelled else { return }
            if case let SSHError.hostKeyMismatch(expected, got, presentedOpenSSHKey) = error {
                pendingHostKeyMismatch = SSHHostKeyMismatch(
                    host: snapshot.host,
                    port: snapshot.port,
                    expectedFingerprint: expected,
                    presentedFingerprint: got,
                    presentedOpenSSHKey: presentedOpenSSHKey
                )
            }
            invalidateInFlightConnect(updateStatus: false)
            status = .error(error.localizedDescription)
        }
    }

    private func adopt(_ opened: SSHOpenedTunnel, generation: UInt64) -> Bool {
        guard generation == connectGeneration, !Task.isCancelled else {
            opened.close()
            return false
        }
        activeTunnel = opened
        return true
    }

    private func closeIfStillActive(_ opened: SSHOpenedTunnel) {
        let current = activeTunnel
        opened.close()
        if current?.remotePort == opened.remotePort && current?.id == opened.id {
            activeTunnel = nil
            connectedRemotePort = nil
        }
    }

    private func establishTunnel(generation: UInt64, snapshot: SSHTunnelConfig) async throws {
        _ = try SSHKeyManager.ensureKeyPair()
        guard let privateKeyData = try SSHKeyManager.loadPrivateKey() else {
            throw SSHError.keyNotFound
        }
        guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            throw SSHError.invalidKeyFormat
        }
        let settings = SSHClientSettings(
            host: snapshot.host,
            port: snapshot.port,
            authenticationMethod: { .ed25519(username: snapshot.username, privateKey: privateKey) },
            hostKeyValidator: .custom(SSHTOFUHostKeyValidator(host: snapshot.host, port: snapshot.port))
        )
        let client = try await SSHClient.connect(to: settings)
        guard generation == connectGeneration, !Task.isCancelled else {
            Task { try? await client.close() }
            throw CancellationError()
        }
        sshClient = client
        trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: snapshot.host, port: snapshot.port)
        pendingHostKeyMismatch = nil
        do {
            try await startLocalListener(sshClient: client, generation: generation, remotePort: snapshot.remotePort)
        } catch {
            if generation != connectGeneration || Task.isCancelled {
                Task { try? await client.close() }
                throw CancellationError()
            }
            throw error
        }
        guard generation == connectGeneration, !Task.isCancelled else {
            Task { try? await client.close() }
            throw CancellationError()
        }
    }

    @discardableResult
    func beginListenerAttempt(remotePort: Int) -> ListenerAttempt {
        let attempt = ListenerAttempt(id: UUID(), generation: connectGeneration, remotePort: remotePort)
        listenerAttempt = attempt
        return attempt
    }

    func isCurrentListenerAttempt(generation: UInt64, attemptID: UUID) -> Bool {
        generation == connectGeneration && listenerAttempt?.id == attemptID
    }

    func deliverDeferredListenerFailure(generation: UInt64, attemptID: UUID, message: String) {
        guard isCurrentListenerAttempt(generation: generation, attemptID: attemptID) else { return }
        status = .error(message)
        invalidateInFlightConnect(updateStatus: false)
    }

    func acceptLocalForward<T>(
        generation: UInt64,
        attemptID: UUID,
        remotePort: Int,
        openChannel: (Int) async throws -> T,
        cancelConnection: () -> Void,
        startForward: (T) -> Void,
        abandonForward: (T) -> Void
    ) async {
        guard isCurrentListenerAttempt(generation: generation, attemptID: attemptID) else {
            cancelConnection()
            return
        }
        do {
            let opened = try await openChannel(remotePort)
            guard isCurrentListenerAttempt(generation: generation, attemptID: attemptID) else {
                cancelConnection()
                abandonForward(opened)
                return
            }
            startForward(opened)
        } catch {
            cancelConnection()
            recordForwardErrorIfCurrent(generation, attemptID, error.localizedDescription)
        }
    }

    private func startLocalListener(sshClient: SSHClient, generation: UInt64, remotePort: Int) async throws {
        if let listener {
            listener.cancel()
            self.listener = nil
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback

        let listener = try NWListener(using: params, on: localPort)
        self.listener = listener
        let attempt = beginListenerAttempt(remotePort: remotePort)
        let installedListener = listener
        let localPortNumber = Int(localPort.rawValue)

        let queue = DispatchQueue(label: "com.opencode.ssh.tunnel.listener")
        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in
                guard let self else {
                    conn.cancel()
                    return
                }
                await self.handleLocalConnection(
                    conn,
                    sshClient: sshClient,
                    generation: generation,
                    attemptID: attempt.id,
                    remotePort: attempt.remotePort,
                    localPort: localPortNumber
                )
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let wait = ListenerWait(continuation)
            self.listenerWait = wait
            listener.stateUpdateHandler = { [weak self] newState in
                guard Self.listenerWaitShouldResume(newState) else { return }
                switch newState {
                case .ready:
                    _ = wait.resume()
                case .cancelled:
                    _ = wait.resume(throwing: CancellationError())
                case .failed(let err):
                    let detail = err.localizedDescription
                    Task { @MainActor [weak self] in
                        let listenerDetail = L10n.t(.hostDiagnosticLocalListenerFailed, detail)
                        let message = L10n.t(.sshErrorTunnelFailed, listenerDetail)
                        let first = wait.resume(throwing: SSHError.tunnelFailed(listenerDetail))
                        guard !first, let self, self.listener === installedListener else { return }
                        self.deliverDeferredListenerFailure(generation: generation, attemptID: attempt.id, message: message)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func handleLocalConnection(
        _ conn: NWConnection,
        sshClient: SSHClient,
        generation: UInt64,
        attemptID: UUID,
        remotePort: Int,
        localPort: Int
    ) async {
        let queue = DispatchQueue(label: "com.opencode.ssh.tunnel.conn")
        conn.stateUpdateHandler = { state in
            switch state {
            case .failed:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)

        await acceptLocalForward(
            generation: generation,
            attemptID: attemptID,
            remotePort: remotePort,
            openChannel: { capturedPort in
                let originator = try SocketAddress(ipAddress: "127.0.0.1", port: localPort)
                return try await sshClient.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(
                        targetHost: "127.0.0.1",
                        targetPort: capturedPort,
                        originatorAddress: originator
                    )
                ) { channel in
                    channel.pipeline.addHandler(NIOToNWConnectionHandler(nwConnection: conn))
                }
            },
            cancelConnection: { conn.cancel() },
            startForward: { channel in
                Self.startReceiveLoop(from: conn, to: channel)
            },
            abandonForward: { channel in
                channel.close(promise: nil)
            }
        )
    }

    nonisolated private static func startReceiveLoop(from conn: NWConnection, to channel: Channel) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                channel.eventLoop.execute {
                    var buffer = channel.allocator.buffer(capacity: data.count)
                    buffer.writeBytes(data)
                    channel.writeAndFlush(buffer, promise: nil)
                }
            }

            if isComplete || error != nil {
                channel.eventLoop.execute {
                    channel.close(promise: nil)
                }
                conn.cancel()
                return
            }

            Self.startReceiveLoop(from: conn, to: channel)
        }
    }
    
    func disconnect(updateStatus: Bool = true) {
        invalidateInFlightConnect(updateStatus: updateStatus)
    }

    private func invalidateInFlightConnect(updateStatus: Bool) {
        connectGeneration &+= 1
        connectTask?.cancel()
        connectTask = nil
        listenerWait?.resume(throwing: CancellationError())
        listenerWait = nil
        listener?.cancel()
        listener = nil
        activeTunnel?.close()
        activeTunnel = nil
        listenerAttempt = nil
        connectedRemotePort = nil
        if let client = sshClient {
            Task {
                try? await client.close()
            }
        }
        sshClient = nil
        if updateStatus {
            status = .disconnected
        }
    }
    
    func getPublicKey() -> String? {
        SSHKeyManager.getPublicKey()
    }
    
    func readPublicKey() throws -> String {
        try SSHKeyManager.getKeyPair()
    }

    func rotateKey() throws -> String {
        try SSHKeyManager.rotateKey()
    }

    func clearTrustedHost() {
        SSHKnownHostStore.clear(host: config.host, port: config.port)
        trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: config.host, port: config.port)
        pendingHostKeyMismatch = nil
    }

    func trustPendingHostKey() {
        guard let pending = pendingHostKeyMismatch else { return }
        SSHKnownHostStore.trust(host: pending.host, port: pending.port, openSSHKey: pending.presentedOpenSSHKey)
        trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: pending.host, port: pending.port)
        pendingHostKeyMismatch = nil
    }

    private func recordForwardErrorIfCurrent(_ generation: UInt64, _ attemptID: UUID, _ description: String) {
        guard isCurrentListenerAttempt(generation: generation, attemptID: attemptID), status == .connected else { return }
        status = .error(description)
    }
}

private final class NIOToNWConnectionHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let nwConnection: NWConnection

    nonisolated init(nwConnection: NWConnection) {
        self.nwConnection = nwConnection
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        guard !bytes.isEmpty else { return }

        // NIO's `ChannelHandlerContext` isn't Sendable but is thread-confined
        // to its event loop. We capture it here and immediately schedule
        // `context.close` back onto that event loop, which is the correct NIO
        // pattern. Swift 6 strict concurrency still flags the capture; the
        // fix lives upstream in NIO. See
        // https://forums.swift.org/t/nio-channelhandlercontext-sendable
        let boxedContext = SendableBox(value: context)
        nwConnection.send(content: Data(bytes), completion: .contentProcessed { error in
            if let error {
                #if DEBUG
                print("[SSH Tunnel] send failed: \(error)")
                #endif
                boxedContext.value.eventLoop.execute {
                    boxedContext.value.close(promise: nil)
                }
            }
        })
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        #if DEBUG
        print("[SSH Tunnel] channel error: \(error)")
        #endif
        context.close(promise: nil)
        nwConnection.cancel()
    }
}
#endif

enum SSHError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case keyNotFound
    case keyUnavailable
    case invalidKeyFormat
    case tunnelFailed(String)
    case hostKeyMismatch(expected: String, got: String, presentedOpenSSHKey: String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return L10n.t(.sshErrorConnectionFailed, reason)
        case .authenticationFailed:
            return L10n.t(.sshErrorAuthenticationFailed)
        case .keyNotFound:
            return L10n.t(.sshErrorKeyNotFound)
        case .keyUnavailable:
            return L10n.t(.sshErrorKeyUnavailable)
        case .invalidKeyFormat:
            return L10n.t(.sshErrorInvalidKeyFormat)
        case .tunnelFailed(let reason):
            return L10n.t(.sshErrorTunnelFailed, reason)
        case .hostKeyMismatch(let expected, let got, _):
            return L10n.t(.sshErrorHostKeyMismatch, expected, got)
        }
    }
}

/// A minimal Sendable wrapper for values whose thread-safety is guaranteed by
/// their own semantics (e.g. NIO's ChannelHandlerContext, whose eventLoop
/// execute() closure always runs on the context's own loop).
private struct SendableBox<Value>: @unchecked Sendable {
    let value: Value
}
