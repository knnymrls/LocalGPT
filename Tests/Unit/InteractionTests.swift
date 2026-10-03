import XCTest
@testable import PumaWorkspace

@MainActor
final class InteractionTests: XCTestCase {
    func testDictationKeepsTypedPrefixAndKeyboardHandoffRejectsLateTranscript() async throws {
        let speech = ControlledSpeech()
        let chat = ChatSessionStore(container: makeContainer(speech: speech))
        await chat.load()
        let voice = VoiceSessionController(speech: speech, chat: chat)
        chat.draft = "Already typed"
        voice.startDictation()
        await settle()
        speech.capture.yield(.partial("and spoken"))
        await settle()
        XCTAssertEqual(chat.draft, "Already typed and spoken")
        voice.handoffToKeyboard()
        speech.capture.yield(.final("late words"))
        await settle()
        XCTAssertEqual(chat.draft, "Already typed and spoken")
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testLeavingVoiceDoesNotCancelReplyAndMuteRejectsLateFinal() async throws {
        let speech = ControlledSpeech()
        let assistant = ControlledAssistant()
        let chat = ChatSessionStore(container: makeContainer(speech: speech, assistant: assistant))
        await chat.load()
        let voice = VoiceSessionController(speech: speech, chat: chat)
        chat.draft = "A typed question"
        chat.send()
        voice.start()
        await settle()
        voice.handoffToKeyboard()
        assistant.events.yield(.text("The reply continues"))
        assistant.events.yield(.finished)
        await settle()
        XCTAssertEqual(chat.messages.last?.text, "The reply continues")
        XCTAssertEqual(chat.messages.last?.status, .complete)
        voice.start()
        await settle()
        voice.toggleMute()
        speech.capture.yield(.final("must not send"))
        await settle()
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(voice.state, .muted)
        voice.exit()
    }

    func testReceiptsAreLinkedToSpecificMemoryAndSurviveReload() async throws {
        let repo = InMemoryConversationRepository([])
        let memory = InMemoryMemoryRepository([])
        let assistant = ControlledAssistant()
        let container = AppContainer(assistant: assistant, speech: ControlledSpeech(), conversations: repo,
                                     attachments: InMemoryAttachmentRepository([]), memories: memory, modelCatalog: FixtureModelCatalog())
        let chat = ChatSessionStore(container: container)
        await chat.load()
        chat.draft = "I prefer quiet rooms."
        chat.send()
        var saved = MemoryItem(text: "I prefer quiet rooms.", origin: "From this chat", state: .saved)
        saved.conversationID = chat.activeID
        saved.messageID = chat.messages.first?.id
        await memory.save(saved)
        assistant.events.yield(.memorySaved(saved))
        assistant.events.yield(.text("Hello"))
        assistant.events.yield(.finished)
        await settle()
        XCTAssertEqual(chat.messages.last?.savedMemoryIDs, [saved.id])
        let reopened = ChatSessionStore(container: container)
        await reopened.load()
        XCTAssertEqual(reopened.messages.last?.savedMemoryIDs, [saved.id])
        reopened.regenerate(try XCTUnwrap(reopened.messages.last?.id))
        XCTAssertEqual(reopened.messages.last?.savedMemoryIDs, [saved.id], "Retry retains the receipt for the originating user message")
        reopened.forgetMemory(saved.id)
        await settle()
        XCTAssertTrue(reopened.memories.isEmpty)
    }

    func testMemoryRequestHasNoArtifactTools() {
        let memory = ToolPolicy(prompt: "I prefer quiet venues. Please remember that and say hello.")
        XCTAssertFalse(memory.files)
        XCTAssertFalse(memory.charts)
        XCTAssertFalse(memory.diagrams)
        XCTAssertTrue(ToolPolicy(prompt: "Create a CSV file of these expenses").files)
        XCTAssertTrue(ToolPolicy(prompt: "Make a bar chart of attendance").charts)
        XCTAssertTrue(ToolPolicy(prompt: "Draw a flow diagram of our plan").diagrams)
    }

    func testPlaybackFailureKeepsReplyAndDoesNotResumeListening() async throws {
        let speech = ControlledSpeech(playbackFailure: "Audio interrupted")
        let assistant = ControlledAssistant()
        let chat = ChatSessionStore(container: makeContainer(speech: speech, assistant: assistant))
        await chat.load()
        let voice = VoiceSessionController(speech: speech, chat: chat)
        defer { voice.exit() }
        chat.draft = "A question"
        chat.send()
        voice.start()
        assistant.events.yield(.text("The answer remains readable"))
        assistant.events.yield(.finished)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(voice.state, .unavailable("Audio interrupted"))
        XCTAssertEqual(chat.messages.last?.status, .complete)
        XCTAssertEqual(chat.messages.last?.text, "The answer remains readable")
        voice.handoffToKeyboard()
        XCTAssertEqual(voice.state, .idle)
    }

    func testVoiceCallContinuesAcrossTwoRepliesQuietWindowAndMute() async throws {
        let speech = CallSpeech()
        let chat = ChatSessionStore(container: makeContainer(speech: speech, assistant: ImmediateAssistant()))
        await chat.load()
        let voice = VoiceSessionController(speech: speech, chat: chat)
        defer { voice.exit() }
        let conversation = chat.activeID
        voice.start()
        await settle()
        for (index, words) in ["First question", "Another question"].enumerated() {
            await speech.finishInput(words)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(voice.state, .speaking)
            let inputsDuringPlayback = await speech.inputs.count
            XCTAssertEqual(inputsDuringPlayback, index + 1, "Capture must wait until playback finishes")
            await speech.finishPlayback()
            await settle()
            XCTAssertEqual(voice.state, .listening)
            XCTAssertTrue(voice.isActive)
        }
        XCTAssertEqual(chat.activeID, conversation)
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.map(\.text), ["First question", "Another question"])
        await speech.finishInput(nil) // A quiet window expires, not the call.
        try await Task.sleep(for: .milliseconds(400))
        let inputsAfterQuiet = await speech.inputs.count
        XCTAssertEqual(inputsAfterQuiet, 4)
        XCTAssertEqual(chat.messages.count, 4, "Silence must never create a turn")
        await speech.partial("Unfinished thought")
        await settle()
        voice.toggleMute()
        await speech.finishInput("late words")
        await settle()
        XCTAssertEqual(voice.state, .muted)
        XCTAssertEqual(chat.messages.count, 4)
        voice.toggleMute()
        await settle()
        XCTAssertEqual(voice.state, .listening)
        voice.handoffToKeyboard()
        await settle()
        let lease = await speech.conversationID
        XCTAssertNil(lease)
        XCTAssertEqual(chat.draft, "Unfinished thought")
        XCTAssertEqual(chat.messages.count, 4)
    }

    func testQuietSpeechBufferStillAcceptsSpeechAfterLongPause() {
        let buffer = WhisperAudioBuffer()
        for _ in 0..<640 { buffer.append(Array(repeating: 0, count: 1024)) }
        XCTAssertFalse(buffer.snapshot().heardSpeech)
        XCTAssertLessThanOrEqual(buffer.snapshot().samples.count, 16000)
        buffer.append(Array(repeating: 0.05, count: 3200))
        XCTAssertTrue(buffer.snapshot().heardSpeech)
        XCTAssertFalse(buffer.snapshot().ended)
        buffer.append(Array(repeating: 0, count: 26000))
        XCTAssertTrue(buffer.snapshot().ended)
    }

    private func makeContainer(speech: any SpeechClient, assistant: any AssistantClient = ControlledAssistant()) -> AppContainer {
        AppContainer(assistant: assistant, speech: speech, conversations: InMemoryConversationRepository([]),
                     attachments: InMemoryAttachmentRepository([]), memories: InMemoryMemoryRepository([]), modelCatalog: FixtureModelCatalog())
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(70)) }
}

private actor CallSpeech: SpeechClient {
    private(set) var inputs: [AsyncStream<TranscriptEvent>.Continuation] = []
    private var playback: AsyncStream<PlaybackEvent>.Continuation?
    private(set) var conversationID: UUID?
    func beginConversation(id: UUID) { conversationID = id }
    func endConversation(id: UUID) { if conversationID == id { conversationID = nil } }
    nonisolated func listen() -> AsyncStream<TranscriptEvent> {
        AsyncStream { stream in Task { await self.addInput(stream) } }
    }
    private func addInput(_ stream: AsyncStream<TranscriptEvent>.Continuation) { inputs.append(stream); stream.yield(.ready) }
    func partial(_ text: String) { inputs.last?.yield(.partial(text)) }
    func finishInput(_ text: String?) { if let text { inputs.last?.yield(.final(text)) }; inputs.last?.finish() }
    nonisolated func speak(_ text: String) -> AsyncStream<PlaybackEvent> {
        AsyncStream { stream in Task { await self.setPlayback(stream) } }
    }
    private func setPlayback(_ stream: AsyncStream<PlaybackEvent>.Continuation) { playback = stream }
    func finishPlayback() { playback?.yield(.finished); playback?.finish(); playback = nil }
}

private struct ImmediateAssistant: AssistantClient {
    func send(_ request: ReplyRequest) -> AsyncStream<ReplyEvent> {
        AsyncStream { $0.yield(.text("A short answer")); $0.yield(.finished); $0.finish() }
    }
}

private struct ControlledSpeech: SpeechClient {
    let stream: AsyncStream<TranscriptEvent>
    let capture: AsyncStream<TranscriptEvent>.Continuation
    let playbackFailure: String?
    init(playbackFailure: String? = nil) {
        self.playbackFailure = playbackFailure
        (stream, capture) = AsyncStream.makeStream(of: TranscriptEvent.self)
    }
    func listen() -> AsyncStream<TranscriptEvent> { stream }
    func speak(_ text: String) -> AsyncStream<PlaybackEvent> {
        AsyncStream {
            if let playbackFailure { $0.yield(.failed(playbackFailure)) }
            else { $0.yield(.finished) }
            $0.finish()
        }
    }
}

private struct ControlledAssistant: AssistantClient {
    let stream: AsyncStream<ReplyEvent>
    let events: AsyncStream<ReplyEvent>.Continuation
    init() { (stream, events) = AsyncStream.makeStream(of: ReplyEvent.self) }
    func send(_ request: ReplyRequest) -> AsyncStream<ReplyEvent> { stream }
}
