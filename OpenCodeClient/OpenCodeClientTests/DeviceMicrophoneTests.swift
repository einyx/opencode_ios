//
//  DeviceMicrophoneTests.swift
//  OpenCodeClientTests
//

import AVFoundation
import Foundation
import Testing
@testable import OpenCodeClient

/// The app's own recorder: PCM16 mono at the recogniser's rate, a smoothed
/// level for the waveform, and a WAV file the on-device transcriber reads.
@Suite
struct DeviceMicrophoneTests {
    /// The WAV header is the canonical 44-byte PCM16 mono header.
    @Test func theWAVHeaderDescribesPCM16Mono() throws {
        let data = DeviceWAVWriter.wavHeader(sampleRate: 16_000, byteCount: 32_000)
        let bytes = [UInt8](data)
        #expect(bytes.count == 44)
        #expect(bytes[0..<4] == [0x52, 0x49, 0x46, 0x46])   // RIFF
        #expect(bytes[8..<12] == [0x57, 0x41, 0x56, 0x45])  // WAVE
        #expect(bytes[12..<16] == [0x66, 0x6D, 0x74, 0x20]) // fmt
        #expect(bytes[20] == 1)                             // PCM
        #expect(bytes[22] == 1)                             // mono
        // 16 000 Hz little-endian.
        #expect(bytes[24] == 0x80)
        #expect(bytes[25] == 0x3E)
        // 16 000 samples/second × 2 bytes = 32 000 bytes/second.
        #expect(bytes[28] == 0x00)
        #expect(bytes[29] == 0x7D)
        #expect(bytes[32] == 0x02)                           // block align
        #expect(bytes[34] == 0x10)                           // bits per sample
        #expect(bytes[36..<40] == [0x64, 0x61, 0x74, 0x61]) // data
    }

    @Test func theRecorderWritesTheSamplesItWasGiven() throws {
        let writer = DeviceWAVWriter(sampleRate: 16_000)
        writer.append(Data([0x01, 0x00, 0x02, 0x00]))
        let url = try #require(writer.finish())
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        #expect(data.count == 44 + 4)
        // The header, then the samples as they were given.
        #expect([UInt8](data.suffix(4)) == [0x01, 0x00, 0x02, 0x00])
    }

    @Test func anEmptyRecordingProducesNoFile() {
        let writer = DeviceWAVWriter(sampleRate: 16_000)
        #expect(writer.finish() == nil)
    }

    /// The level meter smooths: a sudden loud sound does not jump the meter.
    @Test func theLevelIsSmoothed() async throws {
        let smoother = DeviceLevelSmoother()
        let first = await smoother.advance(1.0)
        #expect(first > 0)
        #expect(first < 1.0)
        let second = await smoother.advance(1.0)
        #expect(second > first)
    }
}
