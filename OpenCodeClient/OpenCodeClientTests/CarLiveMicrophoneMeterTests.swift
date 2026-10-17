import CoreGraphics
import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveMicrophoneMeterTests {
    @Test func zeroFiniteAndNonFiniteInputs() {
        #expect(CarLiveMicrophoneMeter.sanitized(0) == 0)
        #expect(CarLiveMicrophoneMeter.displayFill(inputLevel: 0) == 0)
        #expect(CarLiveMicrophoneMeter.sanitized(0.4) == 0.4)
        #expect(CarLiveMicrophoneMeter.sanitized(-0.2) == 0)
        #expect(CarLiveMicrophoneMeter.sanitized(1.4) == 1)
        #expect(CarLiveMicrophoneMeter.sanitized(.nan) == 0)
        #expect(CarLiveMicrophoneMeter.sanitized(.infinity) == 0)
        #expect(CarLiveMicrophoneMeter.sanitized(-.infinity) == 0)
        #expect(CarLiveMicrophoneMeter.displayFill(inputLevel: .nan) == 0)
        #expect(CarLiveMicrophoneMeter.displayFill(inputLevel: .infinity) == 0)
        #expect(CarLiveMicrophoneMeter.displayFill(inputLevel: -.infinity) == 0)
        #expect(CarLiveMicrophoneMeter.displayFill(inputLevel: -1) == 0)
    }

    @Test func displayMappingIsMonotonicAndSeparatesSpeechLevels() {
        let inputs = [0.0, 0.02, 0.08, 0.15, 0.25, 0.40, 1.0]
        let fills = inputs.map { CarLiveMicrophoneMeter.displayFill(inputLevel: $0) }
        for index in 1..<fills.count {
            #expect(fills[index] >= fills[index - 1])
        }
        #expect(fills[0] == 0)
        #expect(abs(fills[1] - 0.282842712474619) < 0.000_001)
        #expect(abs(fills[2] - 0.565685424949238) < 0.000_001)
        #expect(abs(fills[3] - 0.774596669241483) < 0.000_001)
        #expect(fills[1] != fills[2])
        #expect(fills[2] != fills[3])
        #expect(fills[4] == 1)
        #expect(fills[5] == 1)
        #expect(fills[6] == 1)
        #expect(CarLiveMicrophoneMeter.fullScaleInput == 0.25)
    }

    @Test func mappingDoesNotChangeRawInput() {
        var raw = 0.08
        let mapped = CarLiveMicrophoneMeter.displayFill(inputLevel: raw)
        let clamped = CarLiveMicrophoneMeter.sanitized(raw)
        #expect(raw == 0.08)
        #expect(clamped == raw)
        #expect(mapped != raw)
        #expect(CarLiveMicrophoneMeter.targetFill(inputLevel: raw, phase: .listening, isMuted: false) == mapped)
    }

    @Test func attackAndReleaseStayInsideRequestedWindows() {
        #expect(CarLiveMicrophoneMeter.attack >= 0.050)
        #expect(CarLiveMicrophoneMeter.attack <= 0.080)
        #expect(CarLiveMicrophoneMeter.release >= 0.250)
        #expect(CarLiveMicrophoneMeter.release <= 0.400)
        #expect(CarLiveMicrophoneMeter.attack == 0.065)
        #expect(CarLiveMicrophoneMeter.release == 0.320)
    }

    @Test func liveRiseUsesAttackAndFallUsesRelease() {
        let rise = CarLiveMicrophoneMeter.transition(
            from: 0.1,
            inputLevel: 0.08,
            phase: .listening,
            isMuted: false,
            reduceMotion: false
        )
        #expect(rise.motion == .attack)
        #expect(rise.duration == CarLiveMicrophoneMeter.attack)
        #expect(rise.fill == CarLiveMicrophoneMeter.displayFill(inputLevel: 0.08))

        let fall = CarLiveMicrophoneMeter.transition(
            from: 0.9,
            inputLevel: 0.02,
            phase: .speaking,
            isMuted: false,
            reduceMotion: false
        )
        #expect(fall.motion == .release)
        #expect(fall.duration == CarLiveMicrophoneMeter.release)
        #expect(fall.fill < 0.9)
    }

    @Test func reduceMotionSnapsWithoutContinuousDuration() {
        let transition = CarLiveMicrophoneMeter.transition(
            from: 0,
            inputLevel: 0.15,
            phase: .listening,
            isMuted: false,
            reduceMotion: true
        )
        #expect(transition.motion == .snap)
        #expect(transition.duration == 0)
        #expect(transition.fill == CarLiveMicrophoneMeter.displayFill(inputLevel: 0.15))
    }

    @Test func muteIdleConnectingClosingAndFailedClearImmediately() {
        let phases: [CarLivePhase] = [.idle, .connecting, .closing, .failed]
        for phase in phases {
            let transition = CarLiveMicrophoneMeter.transition(
                from: 0.8,
                inputLevel: 0.4,
                phase: phase,
                isMuted: false,
                reduceMotion: false
            )
            #expect(transition.fill == 0)
            #expect(transition.motion == .snap)
            #expect(transition.duration == 0)
            #expect(CarLiveMicrophoneMeter.isLive(phase: phase, isMuted: false) == false)
        }
        let muted = CarLiveMicrophoneMeter.transition(
            from: 0.8,
            inputLevel: 0.08,
            phase: .listening,
            isMuted: true,
            reduceMotion: false
        )
        #expect(muted.fill == 0)
        #expect(muted.motion == .snap)
        #expect(CarLiveMicrophoneMeter.displayFill(inputLevel: 0.08) > 0)
    }

    @Test func glyphFillStaysInsideOutlineAndRisesFromBottom() {
        let layout = CarLiveMicrophoneGlyphLayout()
        let compact = CarLiveMicrophoneGlyphLayout(side: 28)
        #expect(CarLiveMicrophoneMeter.iconSide == 48)
        #expect(layout.side == 48)
        #expect(layout.side < 72)
        #expect(abs(layout.stroke / layout.side - compact.stroke / compact.side) < 0.000_001)
        #expect(abs(layout.head.width / layout.side - compact.head.width / compact.side) < 0.000_001)
        #expect(compact.inkStaysInsideSide)
        #expect(layout.innerHead.width > 0)
        #expect(layout.innerHead.height > layout.innerHead.width)
        #expect(layout.innerHead.minX > layout.head.minX)
        #expect(layout.innerHead.maxX < layout.head.maxX)
        #expect(layout.innerHead.minY > layout.head.minY)
        #expect(layout.innerHead.maxY < layout.head.maxY)
        #expect(layout.armTop < layout.arcCenterY)
        #expect(layout.inkStaysInsideSide)

        let empty = layout.revealRect(fill: 0)
        #expect(empty.height == 0)
        #expect(empty.maxY == layout.innerHead.maxY)

        let mid = layout.revealRect(fill: 0.5)
        #expect(abs(mid.height - layout.innerHead.height * 0.5) < 0.001)
        #expect(mid.maxY == layout.innerHead.maxY)
        #expect(mid.minX == layout.innerHead.minX)

        let full = layout.revealRect(fill: 1)
        #expect(abs(full.height - layout.innerHead.height) < 0.001)
        #expect(full.maxX == layout.innerHead.maxX)
        #expect(layout.revealRect(fill: .nan).height == 0)
        #expect(layout.revealRect(fill: .infinity).height == 0)
    }

    @Test func meterPresetParserPrefersLaunchArgumentAndIgnoresUnknownEnvironment() {
        #expect(CarLiveMeterPreset.resolve(arguments: [], environment: [:]) == nil)
        #expect(CarLiveMeterPreset.resolve(arguments: ["UITEST_CAR_LIVE_METER_QUIET"], environment: [:]) == .quiet)
        #expect(CarLiveMeterPreset.resolve(arguments: [], environment: ["UITEST_CAR_LIVE_METER": "MID"]) == .mid)
        #expect(
            CarLiveMeterPreset.resolve(
                arguments: ["UITEST_CAR_LIVE_METER_HIGH"],
                environment: ["UITEST_CAR_LIVE_METER": "quiet"]
            ) == .high
        )
        #expect(CarLiveMeterPreset.resolve(arguments: [], environment: ["UITEST_CAR_LIVE_METER": "full"]) == nil)
        #expect(CarLiveMeterPreset.quiet.inputLevel == 0.02)
        #expect(CarLiveMeterPreset.mid.inputLevel == 0.08)
        #expect(CarLiveMeterPreset.high.inputLevel == 0.15)
        #expect(CarLiveMeterPreset.muted.inputLevel == 0.08)
        #expect(CarLiveMeterPreset.muted.isMuted)
        #expect(CarLiveMeterPreset.high.isMuted == false)
    }

    @Test func inactiveFixtureDoesNotRewriteRawLevel() {
        var snapshot = CarLiveSnapshot(phase: .listening, inputLevel: 0.40, outputLevel: 0.20, isMuted: false)
        let original = snapshot
        snapshot = CarLiveMeterPreset.applying(.quiet, active: false, to: snapshot)
        #expect(snapshot == original)
        let applied = CarLiveMeterPreset.applying(.muted, active: true, to: original)
        #expect(applied.inputLevel == 0.08)
        #expect(applied.isMuted)
        #expect(applied.phase == .listening)
        #expect(applied.outputLevel == original.outputLevel)
        #expect(applied.localEstimatedUSD == original.localEstimatedUSD)
        #expect(CarLiveFixture.connectedSnapshot().inputLevel == 0.40)
        #expect(CarLiveFixture.connectedSnapshot().isMuted == false)
    }
}
