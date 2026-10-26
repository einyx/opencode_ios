import Testing
@testable import OpenCodeClient

@MainActor
struct ConnectionPresentationTests {
    @Test func checkingPhasesAreProgressNotFailures() {
        for phase: ConnectionPhase in [.sshGateway, .sshAuth, .localTunnel, .health, .bootstrap] {
            #expect(phase.isChecking)
            #expect(phase.diagnosticSymbol == "arrow.triangle.2.circlepath")
        }
    }

    @Test func onlyAFailedCheckUsesTheWarningSymbol() {
        #expect(ConnectionPhase.failed.diagnosticSymbol == "exclamationmark.triangle")
        #expect(ConnectionPhase.connected.diagnosticSymbol == "checkmark.circle")
        #expect(ConnectionPhase.idle.diagnosticSymbol == "network")
        #expect(!ConnectionPhase.failed.isChecking)
        #expect(!ConnectionPhase.connected.isChecking)
        #expect(!ConnectionPhase.idle.isChecking)
    }
}
