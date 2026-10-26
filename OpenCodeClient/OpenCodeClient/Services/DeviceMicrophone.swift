//
//  DeviceMicrophone.swift
//  OpenCodeClient
//

import Foundation
#if os(iOS) || os(visionOS)
@preconcurrency import AVFoundation
#endif

/// The app's own microphone capture.
///
/// PCM16 / 24 kHz / mono, a smoothed level for the waveform, and a WAV file
/// for the on-device transcriber. It replaced the hosted voice package's
/// recorder: that one existed to feed a cloud service, and the app no longer
/// has one.
@MainActor
final class DeviceMicrophone {
    /// The smoothed level, 0...1. A cold stream — the host has to iterate it
    /// to drive a waveform.
    let audioLevel: AsyncStream<Float>

    #if os(iOS) || os(visionOS)
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let engine = AVAudioEngine()
    private var smoother = DeviceLevelSmoother()
    private var recording: DeviceWAVWriter?
    private var chunkHandler: (@Sendable (Data) -> Void)?
    private var capturing = false
    #endif

    init() {
        var captured: AsyncStream<Float>.Continuation!
        audioLevel = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            captured = continuation
        }
        #if os(iOS) || os(visionOS)
        levelContinuation = captured
        #endif
    }

    /// Asks for the microphone permission.
    func requestPermission() async -> Bool {
        #if os(iOS) || os(visionOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return false
        #endif
    }

    #if os(iOS) || os(visionOS)
    /// Starts capturing.
    ///
    /// `onPCMChunk` is called on the capture queue with every chunk. The
    /// audio is also written to a WAV file, which the on-device transcriber
    /// reads when the recording stops.
    func start(onPCMChunk: (@Sendable (Data) -> Void)? = nil) async throws {
        guard !capturing else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DeviceMicrophoneError.unavailable
        }
        // The Speech framework reads 16 kHz mono PCM; the hardware gives
        // whatever it likes (usually 48 kHz), so the capture is converted.
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: format, to: target) else {
            throw DeviceMicrophoneError.unavailable
        }
        let writer = DeviceWAVWriter(sampleRate: Self.targetSampleRate)
        recording = writer
        chunkHandler = onPCMChunk

        let levelContinuation = levelContinuation
        let smoother = smoother
        input.installTap(onBus: 0, bufferSize: 960, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let data = Self.convert(buffer, with: converter, to: target) else { return }
            writer.append(data)
            onPCMChunk?(data)
            let raw = Self.level(of: data)
            Task {
                let smoothed = await smoother.advance(raw)
                levelContinuation.yield(smoothed)
            }
        }
        engine.prepare()
        try engine.start()
        capturing = true
    }

    /// Stops capturing and returns the WAV file, or nil when nothing was
    /// recorded.
    func stop() async throws -> URL? {
        #if os(iOS) || os(visionOS)
        guard capturing else { return nil }
        capturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = recording?.finish()
        recording = nil
        chunkHandler = nil
        return url
        #else
        return nil
        #endif
    }

    /// Throws the recording away.
    func discard() {
        #if os(iOS) || os(visionOS)
        guard capturing else { return }
        capturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recording?.discard()
        recording = nil
        chunkHandler = nil
        #endif
    }

    /// The sample rate the on-device recogniser reads.
    static let targetSampleRate: Double = 16_000

    /// Converts one captured buffer to the recogniser's format.
    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to target: AVAudioFormat
    ) -> Data? {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up))
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var error: NSError?
        nonisolated(unsafe) let captured = buffer
        converter.convert(to: output, error: &error) { _, status in
            status.pointee = .haveData
            return captured
        }
        guard error == nil, let channel = output.int16ChannelData?.pointee else { return nil }
        let count = Int(output.frameLength) * MemoryLayout<Int16>.size
        guard count > 0 else { return nil }
        return Data(bytes: channel, count: count)
    }

    /// The root-mean-square level of a PCM16 chunk, 0...1.
    private static func level(of data: Data) -> Float {
        let count = data.count / 2
        guard count > 0 else { return 0 }
        var sum: Double = 0
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for index in 0..<count {
                let low = Int16(base.load(fromByteOffset: index * 2, as: UInt8.self))
                let high = Int16(base.load(fromByteOffset: index * 2 + 1, as: UInt8.self))
                let sample = Double((high << 8) | (low & 0xFF)) / 32768.0
                sum += sample * sample
            }
        }
        return Float(min(1, (sum / Double(count)).squareRoot() * 4))
    }
    #endif
}

enum DeviceMicrophoneError: Error {
    case unavailable
}

/// The composer's microphone seam: stop the capture and hand back the file.
extension DeviceMicrophone: ChatSpeechMicrophoneControlling {}

/// Smooths the level: 30% of the new sample, 70% carried over.
actor DeviceLevelSmoother {
    private var current: Float = 0

    func advance(_ raw: Float) -> Float {
        current = current * 0.7 + raw * 0.3
        return current
    }
}

#if os(iOS) || os(visionOS)
/// Writes PCM16 chunks into a WAV file.
final class DeviceWAVWriter {
    private let sampleRate: Double
    private let channels: UInt16 = 1
    private var samples: [Int16] = []
    private let lock = NSLock()

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let count = data.count / 2
        guard count > 0 else { return }
        var values = [Int16](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for index in 0..<count {
                let low = Int16(base.load(fromByteOffset: index * 2, as: UInt8.self))
                let high = Int16(base.load(fromByteOffset: index * 2 + 1, as: UInt8.self))
                values[index] = (high << 8) | (low & 0xFF)
            }
        }
        samples.append(contentsOf: values)
    }

    /// Finishes the file and returns its URL.
    func finish() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).wav")
        do {
            var data = Data()
            data.append(Self.wavHeader(sampleRate: sampleRate, byteCount: UInt32(samples.count * 2)))
            samples.withUnsafeBytes { raw in
                data.append(raw.bindMemory(to: UInt8.self))
            }
            try data.write(to: url, options: .atomic)
            samples.removeAll()
            return url
        } catch {
            samples.removeAll()
            return nil
        }
    }

    /// A 44-byte canonical WAV header for PCM16 mono.
    static func wavHeader(sampleRate: Double, byteCount: UInt32) -> Data {
        let rate = UInt32(sampleRate)
        let byteRate = rate * 2
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [0x52, 0x49, 0x46, 0x46])                 // RIFF
        bytes.append(contentsOf: [0x24, 0x08, 0x00, 0x00])                 // size
        bytes.append(contentsOf: [0x57, 0x41, 0x56, 0x45])                 // WAVE
        bytes.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])                 // fmt
        bytes.append(contentsOf: [0x10, 0x00, 0x00, 0x00])                 // fmt size
        bytes.append(contentsOf: [0x01, 0x00])                             // PCM
        bytes.append(contentsOf: [0x01, 0x00])                             // mono
        bytes.append(contentsOf: littleEndian(rate))                       // sample rate
        bytes.append(contentsOf: littleEndian(byteRate))                   // byte rate
        bytes.append(contentsOf: [0x02, 0x00])                             // block align
        bytes.append(contentsOf: [0x10, 0x00])                             // bits
        bytes.append(contentsOf: [0x64, 0x61, 0x74, 0x61])                 // data
        bytes.append(contentsOf: littleEndian(byteCount))                  // data size
        return Data(bytes)
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}
#endif
