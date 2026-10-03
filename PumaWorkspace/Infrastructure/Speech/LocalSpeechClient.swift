@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

/// Recognition explicitly requires the device recognizer; there is no server fallback.
struct LocalSpeechClient: SpeechClient {
    func listen() -> AsyncStream<TranscriptEvent> {
        let id = UUID()
        return AsyncStream { stream in
            let task = Task { @MainActor in await LocalAudioSession.shared.listen(id: id, stream: stream) }
            stream.onTermination = { _ in
                task.cancel()
                Task { @MainActor in LocalAudioSession.shared.stopCapture(id: id) }
            }
        }
    }

    func speak(_ text: String) -> AsyncStream<Double> {
        let id = UUID()
        return AsyncStream { stream in
            let task = Task { @MainActor in LocalAudioSession.shared.speak(id: id, text: text, stream: stream) }
            stream.onTermination = { _ in
                task.cancel()
                Task { @MainActor in LocalAudioSession.shared.stopPlayback(id: id) }
            }
        }
    }
}

/// Single audio owner for agent capture and playback. IDs reject callbacks from replaced sessions.
@MainActor
final class LocalAudioSession: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = LocalAudioSession()
    private var engine: AVAudioEngine?
    private var whisper: WhisperCapture?
    private var modern: AnalyzerCapture?
    private var finalizing = false
    private var interrupted = false
    private var interruptionObserver: NSObjectProtocol?
    private var captureID: UUID?
    private var capture: AsyncStream<TranscriptEvent>.Continuation?
    private var silence: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var playbackID: UUID?
    private var playback: AsyncStream<Double>.Continuation?
    private var lastText = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { @Sendable [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in
                guard let self else { return }
                self.interrupted = began
                if began {
                    if let id = self.captureID { self.fail("Audio was interrupted. Tap voice when you are ready to continue.", id: id) }
                    self.stopPlayback()
                }
            }
        }
    }

    func listen(id: UUID, stream: AsyncStream<TranscriptEvent>.Continuation) async {
        stopCapture()
        stopPlayback()
        SpeechReader.shared.stop()
        captureID = id
        capture = stream
        let mic = await AVAudioApplication.requestRecordPermission()
        guard captureID == id, !Task.isCancelled else { return }
        guard mic else { fail("Allow microphone access in Settings to use voice.", id: id); return }
        guard !interrupted else { fail("Audio is in use by another session. Try voice again shortly.", id: id); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw WorkspaceError.message("No microphone input is available.") }
            let modern: AnalyzerCapture?
            do { modern = try await AnalyzerCapture.make(format: format, onText: { [weak self] text in
                self?.received(text: text, final: false, error: nil, id: id)
            }, onError: { [weak self] error in self?.fail(error, id: id) }, onPreparing: {
                stream.yield(.preparing("Preparing on-device speech assets…"))
            }) } catch is CancellationError { throw CancellationError() }
            catch { modern = nil } // Older local recognizer is still strictly on-device.
            guard captureID == id, !Task.isCancelled else { modern?.cancel(); return }
            self.modern = modern
            finalizing = false
            if modern == nil {
                stream.yield(.preparing("Preparing local speech. The first use downloads model assets; your audio stays here."))
                let fallback = try await WhisperCapture.make(format: format, onText: { [weak self] text in
                    self?.received(text: text, final: false, error: nil, id: id, scheduleSilence: false)
                }, onEnd: { [weak self] in self?.finish(id: id) }, onError: { [weak self] reason in self?.fail(reason, id: id) })
                guard captureID == id, !Task.isCancelled else { fallback.cancel(); return }
                whisper = fallback
            }
            let feed = modern?.feed ?? whisper?.feed
            stream.yield(.ready)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                feed?(buffer)
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                let level = min(1, Double(sqrt(sum / Float(buffer.frameLength))) * 8)
                stream.yield(.level(level))
            }
            self.engine = engine
            lastText = ""
            engine.prepare()
            try engine.start()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(50)) } catch { return }
                guard let self, self.captureID == id else { return }
                if self.lastText.isEmpty { self.fail("No speech detected. Tap voice to try again.", id: id) }
                else { self.finish(id: id) }
            }
        } catch { fail(error.localizedDescription, id: id) }
    }

    private func received(text: String?, final: Bool, error: String?, id: UUID, scheduleSilence: Bool = true) {
        guard captureID == id else { return }
        if let text, !text.isEmpty {
            if lastText != text {
                lastText = text
                capture?.yield(.partial(text))
                silence?.cancel()
                if finalizing || !scheduleSilence { return }
                silence = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
                    self?.finish(id: id)
                }
            }
            if final { finish(id: id); return }
        }
        if let error { fail(error, id: id) }
    }

    private func finish(id: UUID) {
        guard captureID == id else { return }
        guard !finalizing else { return }
        finalizing = true
        engine?.stop()
        if let modern {
            Task { [weak self] in
                await modern.finish()
                self?.emitFinal(id: id)
            }
        } else if let whisper {
            Task { [weak self] in
                let text = await whisper.finish()
                guard let self, self.captureID == id else { return }
                if let text, !text.isEmpty { self.lastText = text }
                self.emitFinal(id: id)
            }
        } else { emitFinal(id: id) }
    }

    private func emitFinal(id: UUID) {
        guard captureID == id else { return }
        let stream = capture
        let text = lastText
        stopCapture(id: id, finishStream: false)
        if !text.isEmpty { stream?.yield(.final(text)) }
        stream?.finish()
    }

    private func fail(_ reason: String, id: UUID) {
        guard captureID == id else { return }
        capture?.yield(.unavailable(reason))
        stopCapture(id: id)
    }

    func stopCapture(id: UUID? = nil, finishStream: Bool = true) {
        if let id, id != captureID { return }
        captureID = nil
        silence?.cancel(); silence = nil
        timeout?.cancel(); timeout = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        modern?.cancel(); modern = nil
        whisper?.cancel(); whisper = nil
        if finishStream { capture?.finish() }
        capture = nil
        releaseAudioIfIdle()
    }

    func speak(id: UUID, text: String, stream: AsyncStream<Double>.Continuation) {
        stopCapture()
        stopPlayback()
        guard !Task.isCancelled, !text.isEmpty else { stream.finish(); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch { stream.finish(); return }
        playbackID = id
        playback = stream
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        self.utterance = utterance
        synthesizer.speak(utterance)
    }

    func stopPlayback(id: UUID? = nil) {
        if let id, playbackID != id { return }
        playbackID = nil
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        playback?.finish(); playback = nil
        releaseAudioIfIdle()
    }

    /// Wait until any immediate capture/playback handoff has claimed the session.
    func releaseAudioIfIdle() {
        Task { @MainActor in
            await Task.yield()
            guard self.captureID == nil, self.playbackID == nil,
                  SpeechReader.shared.speakingID == nil else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.utterance, ObjectIdentifier(current) == identity else { return }
            self.playback?.yield(0)
            self.stopPlayback()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.utterance, ObjectIdentifier(current) == identity else { return }
            self.playback?.yield(0.45)
        }
    }
}
