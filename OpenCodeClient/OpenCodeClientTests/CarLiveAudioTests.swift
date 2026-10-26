import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveAudioTests {
    @Test func newReaderIsNotReusableAfterFinish() async {
        let first = CarLiveFrameStream(generation: 1)
        #expect(first.yield(Data([1, 2]), generation: 1))
        first.finish()
        #expect(first.yield(Data([3, 4]), generation: 1) == false)
        let second = CarLiveFrameStream(generation: 2)
        #expect(second.yield(Data([5, 6]), generation: 2))
        #expect(second.yield(Data([7, 8]), generation: 1) == false)
        var firstValues: [Data] = []
        for await frame in first.frames {
            firstValues.append(frame)
        }
        #expect(firstValues == [Data([1, 2])])
        let reader = Task { () -> [Data] in
            var values: [Data] = []
            for await frame in second.frames {
                values.append(frame)
                if values.count == 1 { break }
            }
            return values
        }
        #expect(second.yield(Data([9, 10]), generation: 2))
        let read = await reader.value
        #expect(read.contains(Data([9, 10])) || read.contains(Data([5, 6])))
        #expect(firstValues.contains(Data([9, 10])) == false)
        second.finish()
    }

    @Test func oldCaptureRejectedAndClearPlaybackKeepsCaptureGeneration() {
        var gate = CarLiveCaptureGate()
        let first = gate.open()
        #expect(gate.accepts(first))
        gate.clearPlayback()
        #expect(gate.accepts(first))
        #expect(gate.generation == first)
        #expect(gate.playbackGeneration == 1)
        gate.finishStream()
        #expect(gate.accepts(first) == false)
        let second = gate.open()
        #expect(second != first)
        #expect(gate.accepts(first) == false)
        #expect(gate.accepts(second))
        let playback = gate.playbackGeneration
        let firstSlice = gate.noteScheduled(token: playback)
        let secondSlice = gate.noteScheduled(token: playback)
        let stillPlaying = gate.finishScheduled(token: playback, stagingEmpty: true)
        let idle = gate.finishScheduled(token: playback, stagingEmpty: true)
        #expect(firstSlice)
        #expect(secondSlice)
        #expect(stillPlaying == false)
        #expect(idle == true)
        let stale = gate.playbackGeneration
        gate.clearPlayback()
        let staleCompletion = gate.finishScheduled(token: stale, stagingEmpty: true)
        #expect(staleCompletion == nil)
        #expect(gate.generation == second)
    }

    @Test func headsetSkipsVoiceProcessingAndSpeakerEnablesIt() {
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["Headphones", "Headphones"]) == false)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["BluetoothHFP"]) == false)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["Speaker"]) == true)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["BuiltInReceiver"]) == true)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: []) == false)
        #expect(CarLiveAudioRoute.isHeadset("USBAudio") == false)
        #expect(CarLiveAudioRoute.isHeadset("AirPlay") == false)
        #expect(CarLiveAudioRoute.isHeadset("CarAudio") == false)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["USBAudio"]) == false)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["AirPlay"]) == false)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["CarAudio"]) == false)
        #expect(CarLiveAudioRoute.usesVoiceProcessing(portTypes: ["Speaker", "USBAudio"]) == true)
        #expect(CarLiveAudioRoute.isExternalOutputDisconnect("USBAudio"))
        #expect(CarLiveAudioRoute.isExternalOutputDisconnect("AirPlay"))
        #expect(CarLiveAudioRoute.isExternalOutputDisconnect("CarAudio"))
        #expect(CarLiveAudioRoute.isExternalOutputDisconnect("Headphones"))
        #expect(CarLiveAudioRoute.isExternalOutputDisconnect("Speaker") == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["USBAudio"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["AirPlay"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["CarAudio"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["BuiltInReceiver"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: false, previousPorts: ["USBAudio", "BuiltInSpeaker"]) == false)
    }

    @Test func silenceFramesAreEvenZerosAndLevelIsTenHertz() {
        let silence = CarLivePCM.silence(byteCount: 4801)
        #expect(silence.count == 4800)
        #expect(silence.allSatisfy { $0 == 0 })
        #expect(CarLivePCM.silence(byteCount: 1).isEmpty)
        var gate = CarLiveLevelGate()
        let first = gate.allow(now: 1)
        let early = gate.allow(now: 1.05)
        let next = gate.allow(now: 1.1)
        #expect(first)
        #expect(early == false)
        #expect(next)
    }


    @Test func stoppedEngineDoesNotRestartPlayback() {
        let same = CarLivePlaybackRestart(
            queuedCapture: 4, currentCapture: 4, queuedPlayback: 2, currentPlayback: 2,
            intendedRunning: true, engineRunning: true, playerAttached: true, hasAudio: true
        )
        let stopped = CarLivePlaybackRestart(
            queuedCapture: 4, currentCapture: 4, queuedPlayback: 2, currentPlayback: 2,
            intendedRunning: true, engineRunning: false, playerAttached: true, hasAudio: true
        )
        let stale = CarLivePlaybackRestart(
            queuedCapture: 4, currentCapture: 5, queuedPlayback: 2, currentPlayback: 3,
            intendedRunning: true, engineRunning: true, playerAttached: true, hasAudio: true
        )
        let empty = CarLivePlaybackRestart(
            queuedCapture: 4, currentCapture: 4, queuedPlayback: 2, currentPlayback: 2,
            intendedRunning: true, engineRunning: true, playerAttached: true, hasAudio: false
        )
        #expect(same.ownsQueuedClear)
        #expect(same.shouldRestartFromClear == false)
        #expect(same.shouldPlayScheduled)
        #expect(stopped.shouldPlayScheduled == false)
        #expect(stopped.shouldRestartFromClear == false)
        #expect(stale.ownsQueuedClear == false)
        #expect(stale.shouldPlayScheduled == false)
        #expect(empty.shouldPlayScheduled == false)
    }
}
