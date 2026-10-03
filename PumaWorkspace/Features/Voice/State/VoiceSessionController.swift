import Foundation
import Observation

/// Voice capture and playback state. Transcript text is written into the
/// shared chat draft so keyboard and voice edit the same text.
@MainActor
@Observable
final class VoiceSessionController {
    enum State: Equatable {
        case idle
        case listening
        case muted
        case finalizing
        case speaking
        case unavailable(String)
    }

    enum Speaker { case user, assistant }

    private(set) var state: State = .idle
    /// Smoothed 0...1 energy for the aura (attack 0.06 s, release 0.28 s, idle 0.5 floor applied by the view).
    private(set) var energy: Double = 0
    /// The current utterance only (floating transcript).
    private(set) var liveTranscript = ""
    /// Dictation: speech goes into the draft, the composer stays in text mode,
    /// and nothing is sent.
    private(set) var isDictating = false

    var isActive: Bool { state != .idle }
    var isMuted: Bool { state == .muted }
    var speaker: Speaker { state == .speaking ? .assistant : .user }
    var unavailableReason: String? {
        if case .unavailable(let reason) = state { reason } else { nil }
    }

    @ObservationIgnored private let speech: any SpeechClient
    @ObservationIgnored private let chat: ChatSessionStore
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var envelopeTask: Task<Void, Never>?
    @ObservationIgnored private var targetLevel: Double = 0
    @ObservationIgnored private var draftPrefix = ""
    @ObservationIgnored private var session = UUID()

    init(speech: any SpeechClient, chat: ChatSessionStore) {
        self.speech = speech
        self.chat = chat
    }

    // MARK: Lifecycle

    func start() {
        guard !isActive else { return }
        stopDictation()
        session = UUID()
        SpeechReader.shared.stop()
        startEnvelope()
        if chat.isStreaming { awaitReply() } else { listen() }
    }

    /// Leaves voice mode; transcript stays in the draft and is never sent.
    func exit() {
        isDictating = false
        session = UUID()
        captureTask?.cancel(); captureTask = nil
        playbackTask?.cancel(); playbackTask = nil
        envelopeTask?.cancel(); envelopeTask = nil
        state = .idle
        liveTranscript = ""
        targetLevel = 0
        energy = 0
    }

    /// Keyboard handoff: same as exit, the draft keeps the transcript for editing.
    func handoffToKeyboard() { exit() }

    /// Navigation or a sheet pauses capture and retains the draft.
    func pause() { if isActive || isDictating { exit() } }

    // MARK: Dictation

    func startDictation() {
        guard !isActive, !isDictating else { return }
        SpeechReader.shared.stop()
        session = UUID()
        isDictating = true
        startEnvelope()
        let current = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draftPrefix = current.isEmpty ? "" : current + " "
        let stream = speech.listen()
        let token = session
        captureTask = Task { [weak self] in
            for await event in stream {
                guard let self, self.session == token else { return }
                self.handle(event)
            }
        }
    }

    /// Ends dictation and keeps whatever was transcribed in the draft.
    func stopDictation() {
        guard isDictating else { return }
        exit()
    }

    func toggleMute() {
        switch state {
        case .listening, .finalizing, .speaking:
            session = UUID()
            captureTask?.cancel(); captureTask = nil
            playbackTask?.cancel(); playbackTask = nil
            targetLevel = 0
            state = .muted
        case .muted, .unavailable:
            if chat.isStreaming { awaitReply() } else { listen() }
        default:
            break
        }
    }

    // MARK: Capture

    private func listen() {
        captureTask?.cancel()
        session = UUID()
        let current = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draftPrefix = current.isEmpty ? "" : current + " "
        liveTranscript = ""
        state = .listening
        let stream = speech.listen()
        let token = session
        captureTask = Task { [weak self] in
            for await event in stream {
                guard let self, self.session == token else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: TranscriptEvent) {
        if isDictating {
            switch event {
            case .preparing(let text): liveTranscript = text
            case .ready: liveTranscript = ""
            case .level(let level): targetLevel = level
            case .partial(let text): chat.draft = draftPrefix + text
            case .final(let text):
                chat.draft = draftPrefix + text
                stopDictation()
            case .unavailable(let reason): stopDictation(); chat.operationError = reason
            }
            return
        }
        switch event {
        case .preparing(let text): liveTranscript = text
        case .ready: liveTranscript = ""
        case .level(let level):
            targetLevel = level
        case .partial(let text):
            liveTranscript = text
            chat.draft = draftPrefix + text
        case .final(let text):
            liveTranscript = text
            chat.draft = draftPrefix + text
            state = .finalizing
            targetLevel = 0
            submitUtterance()
        case .unavailable(let reason):
            targetLevel = 0
            state = .unavailable(reason)
        }
    }

    /// End of an utterance in voice mode sends the turn, then speaks the reply.
    private func submitUtterance() {
        captureTask?.cancel()
        chat.send()
        awaitReply()
    }

    private func awaitReply() {
        let token = session
        state = .speaking
        liveTranscript = ""
        playbackTask = Task { [weak self] in
            // Wait for the reply to finish streaming.
            while let self, !Task.isCancelled, self.session == token, self.chat.isStreaming {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard let self, !Task.isCancelled, self.session == token, let reply = self.chat.messages.last, reply.role == .assistant else { return }
            guard reply.status == .complete else { self.state = .unavailable(reply.errorDescription ?? "The reply did not finish. Continue in text mode or try again."); return }
            for await level in self.speech.speak(MarkdownText.plain(reply.text)) {
                guard self.session == token else { return }
                self.targetLevel = level
            }
            guard self.session == token else { return }
            self.targetLevel = 0
            self.listen()
        }
    }

    // MARK: Energy envelope

    private func startEnvelope() {
        envelopeTask?.cancel()
        envelopeTask = Task { [weak self] in
            let dt = 1.0 / 60
            while !Task.isCancelled {
                guard let self else { return }
                let target = self.targetLevel
                let tau = target > self.energy ? 0.06 : 0.28
                self.energy += (target - self.energy) * (1 - exp(-dt / tau))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    #if DEBUG
    /// Freezes a representative listening frame for screenshots.
    func debugShowListening(transcript: String, energy: Double) {
        start()
        captureTask?.cancel(); captureTask = nil
        liveTranscript = transcript
        chat.draft = transcript
        targetLevel = energy
        self.energy = energy
    }

    /// Freezes the assistant-speaking look for screenshots.
    func debugShowSpeaking(energy: Double) {
        start()
        captureTask?.cancel(); captureTask = nil
        state = .speaking
        liveTranscript = ""
        targetLevel = energy
        self.energy = energy
    }
    #endif
}
