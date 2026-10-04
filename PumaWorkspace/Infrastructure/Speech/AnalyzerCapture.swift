@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

/// Modern on-device transcription. The audio engine owns the converter's serial callback;
/// only fresh, immutable output buffers are passed into SpeechAnalyzer.
@MainActor
final class AnalyzerCapture {
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private var results: Task<Void, Never>?
    private struct Fragment {
        let start: Double
        let end: Double
        let text: String
    }
    private var fragments: [Fragment] = []
    let feed: @Sendable (AVAudioPCMBuffer) -> Void

    private init(analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation,
                 feed: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.analyzer = analyzer; self.input = input; self.feed = feed
    }

    static func make(format: AVAudioFormat, onText: @escaping @MainActor (String) -> Void,
                     onError: @escaping @MainActor (String) -> Void,
                     onPreparing: @escaping @MainActor () -> Void) async throws -> AnalyzerCapture? {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { return nil }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onPreparing()
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format) else {
            throw WorkspaceError.message("This microphone format is not supported by on-device transcription.")
        }
        let converter = try SpeechBufferConverter(from: format, to: target)
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .bufferingNewest(100))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: target)
        let capture = AnalyzerCapture(analyzer: analyzer, input: input, feed: { buffer in
            if let converted = converter.convert(buffer) { input.yield(AnalyzerInput(buffer: converted)) }
        })
        capture.results = Task { [weak capture] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled, let capture else { return }
                    let start = result.range.start.seconds
                    let end = start + result.range.duration.seconds
                    // Progressive results revise an audio range, whose start can shift.
                    // Replace overlapping hypotheses instead of appending the same speech.
                    capture.fragments.removeAll {
                        $0.start == start || ($0.start < end && start < $0.end)
                    }
                    capture.fragments.append(Fragment(start: start, end: end, text: String(result.text.characters)))
                    let text = capture.fragments.sorted { $0.start < $1.start }.map(\.text).joined(separator: " ")
                    onText(text)
                }
            } catch is CancellationError {} catch { onError(error.localizedDescription) }
        }
        do { try await analyzer.start(inputSequence: stream) }
        catch { capture.cancel(); throw error }
        return capture
    }

    func finish() async {
        input.finish()
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
        catch { await analyzer.cancelAndFinishNow() }
        await results?.value
    }

    func cancel() {
        input.finish()
        results?.cancel(); results = nil
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

/// Accessed only from a single AVAudioEngine input tap, never from UI or analysis tasks.
final class SpeechBufferConverter: @unchecked Sendable {
    let converter: AVAudioConverter
    let target: AVAudioFormat
    init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else { throw WorkspaceError.message("Audio conversion is unavailable.") }
        self.converter = converter; self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let input = OneShotAudioInput(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard let buffer = input.take() else { state.pointee = .noDataNow; return nil }
            state.pointee = .haveData
            return buffer
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}

/// AVAudioConverter may invoke its callback from a nonisolated executor.
/// The source buffer stays immutable and can be supplied exactly once.
private final class OneShotAudioInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        let result = buffer
        buffer = nil
        return result
    }
}
