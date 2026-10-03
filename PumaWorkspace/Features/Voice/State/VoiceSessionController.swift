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
    private(set) var isFinishingDictation = false

    var isActive: Bool { state != .idle }
    var isMuted: Bool { state == .muted }
    var speaker: Speaker { state == .speaking ? .assistant : .user }
    var unavailableReason: String? {
        if case .unavailable(let reason) = state { reason } else { nil }
    }

    @ObservationIgnored private let stopReading: @MainActor () -> Void
    @ObservationIgnored private let speech: any SpeechClient
    @ObservationIgnored private let chat: ChatSessionStore
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var envelopeTask: Task<Void, Never>?
    @ObservationIgnored private var targetLevel: Double = 0
    @ObservationIgnored private var draftPrefix = ""
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var conversationID: UUID?
    @ObservationIgnored private var conversationTask: Task<Void, Never>?
    @ObservationIgnored private var dictationFinishTask: Task<Void, Never>?

    init(speech: any SpeechClient, chat: ChatSessionStore, stopReading: @escaping @MainActor () -> Void = {}) {
        self.stopReading = stopReading
        self.speech = speech
        self.chat = chat
    }

    // MARK: Lifecycle

    func start() {
        guard !isActive else { return }
        if isDictating { exit() }
        session = UUID()
        stopReading()
        startEnvelope()
        let id = UUID()
        conversationID = id
        state = .listening
        conversationTask = Task { [weak self, speech] in
            await speech.beginConversation(id: id)
            guard let self, self.conversationID == id, !Task.isCancelled else {
                await speech.endConversation(id: id)
                return
            }
            guard self.state == .listening else { return }
            if self.chat.isStreaming { self.awaitReply() } else { self.listen() }
        }
    }

    /// Leaves voice mode; transcript stays in the draft and is never sent.
    func exit() {
        isDictating = false
        isFinishingDictation = false
        dictationFinishTask?.cancel(); dictationFinishTask = nil
        conversationTask?.cancel(); conversationTask = nil
        if let id = conversationID {
            conversationID = nil
            Task { [speech] in await speech.endConversation(id: id) }
        }
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

    /// Leaving this conversation or backgrounding pauses capture and retains the draft.
    func pause() { if isActive || isDictating { exit() } }

    // MARK: Dictation

    func startDictation() {
        guard !isActive, !isDictating else { return }
        stopReading()
        session = UUID()
        isDictating = true
        startEnvelope()
        listenForDictation()
    }

    private func listenForDictation() {
        captureTask?.cancel()
        session = UUID()
        let current = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draftPrefix = current.isEmpty ? "" : current + " "
        let stream = speech.listen()
        let token = session
        captureTask = Task { [weak self] in
            for await event in stream {
                guard let self, self.session == token, !Task.isCancelled else { return }
                self.handle(event)
            }
            guard let self, self.session == token, self.isDictating, !Task.isCancelled else { return }
            if self.isFinishingDictation { self.exit(); return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard self.session == token, self.isDictating else { return }
            if self.isFinishingDictation { self.exit() } else { self.listenForDictation() }
        }
    }

    /// Finish flushes the last audio; sentence boundaries and quiet windows never stop dictation.
    func stopDictation() {
        guard isDictating, !isFinishingDictation else { return }
        isFinishingDictation = true
        let token = session
        dictationFinishTask = Task { [weak self, speech] in
            guard !Task.isCancelled else { return }
            let flushing = await speech.finishListening()
            guard let self, self.session == token, self.isDictating, !Task.isCancelled else { return }
            if !flushing { self.exit(); return }
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard self.session == token, self.isFinishingDictation else { return }
            self.exit()
            self.chat.operationError = "Dictation could not finish the remaining audio. The text already transcribed is still in your draft."
        }
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
                guard let self, self.session == token, !Task.isCancelled else { return }
                self.handle(event)
            }
            // A recognizer is per utterance, while the call is ongoing. Empty completion
            // (for example a quiet capture window) starts another window without sending.
            guard let self, self.session == token, self.state == .listening, !Task.isCancelled else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard self.session == token, self.state == .listening else { return }
            self.listen()
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
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chat.draft = draftPrefix + text }
            case .unavailable(let reason): exit(); chat.operationError = reason
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
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
        state = .finalizing
        liveTranscript = ""
        playbackTask = Task { [weak self] in
            // Wait for the reply to finish streaming.
            while let self, !Task.isCancelled, self.session == token, self.chat.isStreaming {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard let self, !Task.isCancelled, self.session == token else { return }
            guard let reply = self.chat.messages.last, reply.role == .assistant else { self.listen(); return }
            guard reply.status == .complete else { self.state = .unavailable(reply.errorDescription ?? "The reply did not finish. Continue in text mode or try again."); return }
            self.state = .speaking
            var finished = false
            for await event in self.speech.speak(MarkdownText.plain(reply.text)) {
                guard self.session == token, !Task.isCancelled else { return }
                switch event {
                case .level(let level): self.targetLevel = level
                case .finished: finished = true
                case .failed(let reason):
                    self.targetLevel = 0
                    self.state = .unavailable(reason)
                    return
                }
            }
            guard self.session == token, !Task.isCancelled else { return }
            self.targetLevel = 0
            guard finished else {
                self.state = .unavailable("Spoken playback did not finish. Your reply is still available in the chat.")
                return
            }
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
