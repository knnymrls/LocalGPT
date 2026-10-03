@preconcurrency import AVFoundation
import Foundation

/// Shared with SpeechAnalyzer: progressive text while listening, then one finalized utterance.
@MainActor
final class WhisperCapture {
    private let audio: WhisperAudioBuffer
    private var processing: Task<Void, Never>?
    private var ending = false
    let feed: @Sendable (AVAudioPCMBuffer) -> Void

    private init(audio: WhisperAudioBuffer, feed: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.audio = audio; self.feed = feed
    }

    static func make(format: AVAudioFormat, onText: @escaping @MainActor (String) -> Void,
                     onEnd: @escaping @MainActor () -> Void, onError: @escaping @MainActor (String) -> Void) async throws -> WhisperCapture {
        try await WhisperRuntime.shared.prepare()
        try Task.checkCancellation()
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw WorkspaceError.message("Could not prepare the local speech format.")
        }
        let converter = try SpeechBufferConverter(from: format, to: target)
        let audio = WhisperAudioBuffer()
        let capture = WhisperCapture(audio: audio, feed: { buffer in
            guard let converted = converter.convert(buffer), let floats = converted.floatChannelData?[0] else { return }
            audio.append(Array(UnsafeBufferPointer(start: floats, count: Int(converted.frameLength))))
        })
        capture.processing = Task { [weak capture] in
            var lastCount = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(550))
                    guard let capture, !capture.ending else { return }
                    let snapshot = audio.snapshot()
                    guard snapshot.heardSpeech, snapshot.samples.count > lastCount + 4000 else { continue }
                    lastCount = snapshot.samples.count
                    let text = try await WhisperRuntime.shared.transcribe(snapshot.samples)
                    try Task.checkCancellation()
                    guard !capture.ending else { return }
                    if !text.isEmpty { onText(text) }
                    // Audio silence, not a slow model callback, decides when the user finished.
                    if audio.snapshot().ended { capture.ending = true; onEnd(); return }
                } catch is CancellationError { return }
                catch { onError("Local speech could not finish: \(error.localizedDescription)"); return }
            }
        }
        return capture
    }

    func finish() async -> String? {
        ending = true
        processing?.cancel(); processing = nil
        let snapshot = audio.snapshot()
        guard snapshot.heardSpeech else { return nil }
        return try? await WhisperRuntime.shared.transcribe(snapshot.samples)
    }

    func cancel() { ending = true; processing?.cancel(); processing = nil; audio.clear() }
}

private final class WhisperAudioBuffer: @unchecked Sendable {
    struct Snapshot: Sendable { var samples: [Float]; var heardSpeech: Bool; var ended: Bool }
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastVoice = 0
    private var voicedSamples = 0

    func append(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        let rms = sqrt(chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count))
        lock.withLock {
            guard samples.count < 28 * 16000 else { return }
            samples.append(contentsOf: chunk)
            if rms > 0.008 { voicedSamples += chunk.count; lastVoice = samples.count }
        }
    }
    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(samples: samples, heardSpeech: voicedSamples > 1600,
                     ended: (voicedSamples > 1600 && samples.count - lastVoice > 16000 * 3 / 2) || samples.count >= 28 * 16000)
        }
    }
    func clear() { lock.withLock { samples.removeAll(keepingCapacity: false) } }
}
