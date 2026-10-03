import XCTest
import FoundationModels
import PDFKit
import ImageIO
import AVFoundation
@testable import PumaWorkspace

/// Explicit opt-in suite: these checks call the real local system model, never a fixture assistant.
final class LiveModelTests: XCTestCase {
    private func workspace() throws -> (URL, WorkspaceDatabase, LocalAttachmentRepository, LocalMemoryRepository, ArtifactWriter) {
        guard SystemLanguageModel.default.isAvailable else { throw XCTSkip("On-device system model unavailable: \(SystemLanguageModel.default.availability)") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LiveChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let db = try WorkspaceDatabase(url: root.appendingPathComponent("workspace.sqlite"))
        let files = LocalAttachmentRepository(database: db, files: WorkspaceFiles(root: root))
        return (root, db, files, LocalMemoryRepository(database: db), ArtifactWriter(files: WorkspaceFiles(root: root), repository: files, database: db))
    }

    private struct Answer {
        var text = ""
        var citations: [Citation] = []
        var outputs: [Attachment] = []
        var steps: [String] = []
        var complete = false
    }

    func testFreshConversationMeaningCorrectionsAndIsolation() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        var history: [Message] = []
        func turn(_ prompt: String) async throws -> String {
            let result = try await answer(prompt, client: client, history: history)
            print("CORE_ACCEPTANCE \(prompt) => \(result.text)")
            history += [Message(role: .user, text: prompt), Message(role: .assistant, text: result.text)]
            XCTAssertLessThan(result.text.count, 2500, "These short requests should not produce runaway formatting")
            XCTAssertTrue(result.outputs.isEmpty)
            return result.text
        }
        _ = try await turn("Turn these notes into two action items: Maya sends the agenda Tuesday. Omar books the room Wednesday.")
        let changed = try await turn("Replace Omar's deadline with Friday. Give only the updated two-item list.")
        for word in ["Maya", "Tuesday", "agenda", "Omar", "Friday", "room"] {
            XCTAssertTrue(changed.localizedCaseInsensitiveContains(word), changed)
        }
        XCTAssertFalse(changed.localizedCaseInsensitiveContains("Wednesday"), changed)

        history = []
        _ = try await turn("For this chat only, my plant is named Miso and I water it on Sundays.")
        let recall = try await turn("What is my plant called, and when do I water it?")
        XCTAssertTrue(recall.localizedCaseInsensitiveContains("Miso"), recall)
        XCTAssertTrue(recall.localizedCaseInsensitiveContains("Sunday"), recall)
        history = []
        let isolated = try await turn("What is my plant called?")
        XCTAssertFalse(isolated.localizedCaseInsensitiveContains("Miso"), "A separate chat must not inherit an unsaved fact")
        XCTAssertTrue(["don't know", "do not know", "haven't", "have not", "not told", "not mentioned", "not shared", "no information", "no details", "don't have enough information", "do not have enough information"].contains { isolated.localizedCaseInsensitiveContains($0) }, "Do not invent missing personal facts: \(isolated)")

        history = []
        let sky = try await turn("Why does the sky look blue during the day? Explain in two sentences.")
        XCTAssertTrue(sky.localizedCaseInsensitiveContains("scatter"), sky)
        let sunset = try await turn("Then why can it look red at sunset instead? Explain the difference in two sentences.")
        XCTAssertTrue(sunset.localizedCaseInsensitiveContains("red") || sunset.localizedCaseInsensitiveContains("orange"), sunset)
        XCTAssertTrue(["longer", "more atmosphere", "more of the atmosphere", "thicker", "greater", "farther", "further", "more air"].contains { sunset.localizedCaseInsensitiveContains($0) }, sunset)

        history = []
        _ = try await turn("I'm winding down after a long day. I just want to chat, no tasks.")
        let fact = try await turn("Tell me a small interesting fact about octopuses.")
        XCTAssertTrue(["heart", "arm", "brain", "camouflage", "blood", "color", "colour", "intelligen", "sucker"].contains { fact.localizedCaseInsensitiveContains($0) }, fact)
        XCTAssertFalse(fact.localizedCaseInsensitiveContains("upload"), fact)
    }

    @MainActor
    func testLiveConversationSurvivesReloadAndKeepsDraft() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let repository = LocalConversationRepository(database: db)
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        let container = AppContainer(assistant: client, speech: MockSpeechClient(), conversations: repository,
                                     attachments: files, memories: memory, modelCatalog: SystemModelCatalog())
        func finish(_ store: ChatSessionStore) async throws {
            let deadline = Date.now.addingTimeInterval(80)
            while store.isStreaming, Date.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertEqual(store.messages.last?.status, .complete, store.messages.last?.errorDescription ?? "Reply did not complete")
        }
        let first = ChatSessionStore(container: container)
        await first.load()
        first.draft = "For this conversation, our project is called Cedar and its release day is Monday."
        first.send()
        try await finish(first)
        first.draft = "Keep this unsent draft"
        first.flush()
        let deadline = Date.now.addingTimeInterval(5)
        var stored: Conversation?
        repeat {
            stored = try await repository.all().first { $0.id == first.activeID }
            if stored?.draft == first.draft && stored?.messages.last?.status == .complete { break }
            try await Task.sleep(for: .milliseconds(50))
        } while Date.now < deadline
        XCTAssertEqual(stored?.draft, "Keep this unsent draft")
        let reopened = ChatSessionStore(container: container)
        await reopened.load()
        XCTAssertEqual(reopened.activeID, first.activeID)
        XCTAssertEqual(reopened.messages, first.messages)
        XCTAssertEqual(reopened.draft, first.draft)
        reopened.draft = "Change the release day to Thursday. What is the project called, and what is its release day now? Give only the current details."
        reopened.send()
        try await finish(reopened)
        let text = try XCTUnwrap(reopened.messages.last?.text)
        print("CORE_RELOAD \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Cedar"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Thursday"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Monday"), text)
    }

    func testCasualConversationDoesNotRepeatGreeting() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        var history: [Message] = []
        var previous = ""
        for prompt in ["Hey, I'm just asking this if this works.", "Nothing I was just trying to have conversation.", "What are you doing?"] {
            let result = try await answer(prompt, client: client, history: history)
            print("CONVERSATION_CHECK \(prompt) => \(result.text)")
            let normalized = result.text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            XCTAssertNotEqual(normalized, prompt.lowercased(), "Must respond as assistant, not echo the user")
            XCTAssertNotEqual(normalized, previous, "The next turn must not repeat the previous greeting")
            history += [Message(role: .user, text: prompt), Message(role: .assistant, text: result.text)]
            previous = normalized
        }
        let fact = "For this chat, the imaginary spaceship is named Juniper."
        let acknowledgment = try await answer(fact, client: client, history: history)
        print("CONVERSATION_FACT \(acknowledgment.text)")
        history += [Message(role: .user, text: fact), Message(role: .assistant, text: acknowledgment.text)]
        let recalled = try await answer("What did I name it?", client: client, history: history)
        print("CONVERSATION_RECALL \(recalled.text)")
        XCTAssertFalse(recalled.text.localizedCaseInsensitiveContains("I named"), "The user, not the assistant, named the ship")
        XCTAssertTrue(recalled.text.localizedCaseInsensitiveContains("Juniper"), "Follow-ups must retain user context")
    }

    func testConversationRecoversFromRepeatedReplies() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        let repeated = "I'm here to help you with whatever you need. What's on your mind?"
        let history = [
            Message(role: .user, text: "Hey, I'm just asking this if this works."),
            Message(role: .assistant, text: "Hey! " + repeated),
            Message(role: .user, text: "Nothing I was just trying to have conversation."),
            Message(role: .assistant, text: repeated)
        ]
        let result = try await answer("What are you doing?", client: client, history: history)
        print("CONVERSATION_RECOVERY \(result.text)")
        XCTAssertFalse(ConversationResponder.repeats(ConversationResponder.normalized(result.text), ConversationResponder.normalized(repeated)), "Must move beyond the repeated answer: \(result.text)")
    }

    private func answer(_ prompt: String, client: LocalAssistantClient, sources: Set<UUID> = [], history: [Message] = []) async throws -> Answer {
        let start = Date()
        var firstToken: TimeInterval?
        var result = Answer()
        let current = Message(role: .user, text: prompt)
        let request = ReplyRequest(conversationID: UUID(), prompt: prompt,
                                   history: history + [current, Message(role: .assistant, text: "", status: .streaming)],
                                   modelID: SystemModelCatalog.modelID, selectedSourceIDs: sources, userMessageID: current.id)
        for await event in client.send(request) {
            switch event {
            case .text(let text):
                if firstToken == nil { firstToken = Date().timeIntervalSince(start) }
                result.text = text
            case .citations(let citations): result.citations = citations
            case .output(let output): result.outputs.append(output)
            case .step(let step): result.steps.append(step)
            case .failed(let error): XCTFail(error)
            case .finished: result.complete = true
            default: break
            }
        }
        let total = Date().timeIntervalSince(start)
        print("LIVE_MODEL first_text=\(firstToken ?? -1) total=\(total) steps=\(result.steps.count) outputs=\(result.outputs.count)")
        let evidence = XCTAttachment(string: "Prompt: \(prompt)\nFirst text: \(firstToken ?? -1)s; total: \(total)s\n\(result.text)\nSteps: \(result.steps)\nCitations: \(result.citations)")
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertTrue(result.complete)
        XCTAssertFalse(result.text.isEmpty)
        return result
    }

    func testLocalMemoryExtractionRecallAndNoUnsolicitedOutputs() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let service = MemoryService(repository: memory)
        let prompt = "I prefer quiet venues and my event budget is 4200 dollars."
        let request = ReplyRequest(conversationID: UUID(), prompt: prompt, history: [], modelID: SystemModelCatalog.modelID, selectedSourceIDs: [])
        try await service.capture(request, scope: RequestScope()) { _ in }
        let saved = try await memory.all()
        XCTAssertFalse(saved.isEmpty)
        XCTAssertTrue(saved.allSatisfy { prompt.contains($0.sourceQuote) })
        let client = LocalAssistantClient(database: db, attachments: files, memories: service, writer: writer)
        let result = try await answer("What kind of venue do I prefer, and what is my event budget?", client: client)
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("quiet"), "Saved: \(saved.map(\.text)); answer: \(result.text)")
        XCTAssertFalse(saved.contains { $0.text.contains("4200") }, "The event budget belongs in chat history, not long-term memory")
        XCTAssertTrue(result.outputs.isEmpty)
    }

    func testSourceBackedComparisonAndRevision() async throws {
        let (root, db, files, memory, writer) = try workspace()
        let importer = LocalDocumentImporter(files: WorkspaceFiles(root: root), database: db, repository: files)
        let documents = [
            ("Harbor.txt", "Harbor venue proposal. Seated capacity: 120 guests. Total hire price: $3200. Wheelchair access: step-free entrance and accessible restroom."),
            ("Riverside.txt", "Riverside venue proposal. Seated capacity: 160 guests. Total hire price: $4100. Wheelchair access: not specified; ask the venue.")
        ]
        var selected = Set<UUID>()
        for (name, text) in documents {
            let url = root.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            let file = try await importer.prepare(Attachment(name: name, kind: .text, readiness: .importing, fileURL: url))
            selected.insert(file.id)
        }
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        let question = "Compare Harbor and Riverside in a table: seated capacity, price, and wheelchair access. Cite the sources."
        let comparison = try await answer(question, client: client, sources: selected)
        XCTAssertTrue(comparison.text.contains("120"))
        XCTAssertTrue(comparison.text.contains("160"))
        XCTAssertTrue(comparison.text.contains("|"), "The requested comparison table must render")
        XCTAssertLessThan(comparison.text.count, 4000, "Reject malformed or runaway table formatting")
        XCTAssertEqual(Set(comparison.citations.map(\.sourceID)), selected)
        XCTAssertTrue(comparison.text.contains("[1]") || comparison.text.contains("[2]"))
        let revision = try await answer("Now we need seating for 140 guests. Which venue qualifies, and what accessibility information still needs checking?", client: client, sources: selected,
                                        history: [Message(role: .user, text: question), Message(role: .assistant, text: comparison.text)])
        XCTAssertTrue(revision.text.localizedCaseInsensitiveContains("Riverside"))
        XCTAssertTrue(revision.text.localizedCaseInsensitiveContains("Harbor"))
        XCTAssertTrue(revision.text.localizedCaseInsensitiveContains("access"))
        XCTAssertTrue(revision.text.contains("140"), "Must apply the latest requirement, not a source capacity: \(revision.text)")
        let normalized = revision.text.lowercased()
        XCTAssertFalse(normalized.contains("requirement of 120"), revision.text)
        XCTAssertTrue(normalized.contains("does not") || normalized.contains("doesn't") || normalized.contains("cannot") || normalized.contains("can't") || normalized.contains("insufficient") || normalized.contains("falls short") || normalized.contains("too small"), "Must explicitly rule out the undersized venue: \(revision.text)")
        XCTAssertNotNil(normalized.range(of: #"riverside[^.!?\n]{0,100}(qualifies|meets|accommodate|suitable|enough|can seat)"#, options: .regularExpression), "Must identify the venue that meets the revised capacity: \(revision.text)")
        let report = try await answer("Create a PDF named Venue Decision with our 140-guests requirement, the qualifying venue, and the accessibility detail we still need to confirm.", client: client, sources: selected,
                                      history: [Message(role: .user, text: question), Message(role: .assistant, text: comparison.text), Message(role: .assistant, text: revision.text)])
        let pdf = try XCTUnwrap(report.outputs.first { $0.kind == .pdf })
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(pdf.fileURL)))
        let reportText = try XCTUnwrap(document.string).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        XCTAssertTrue(reportText.contains("Harbor does not meet"))
        XCTAssertTrue(reportText.contains("120 guests"))
        XCTAssertTrue(reportText.contains("Riverside meets"))
        XCTAssertTrue(reportText.contains("not specified"))
        XCTAssertFalse(report.text.contains("|"), "A file receipt must not invent a second table")
    }

    func testCreatesRealPDFCSVAndRFiles() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        for (format, prompt) in [
            ("pdf", "Create a PDF file named Event Plan with a short three-step event planning checklist."),
            ("csv", "Create a CSV file named costs with exactly these rows: item,amount then room,3200 then catering,800."),
            ("r", "Create an R script file named costs that defines costs as c(3200, 800) and prints their sum. Do not execute it.")
        ] {
            let result = try await answer(prompt, client: client)
            let file = try XCTUnwrap(result.outputs.first { $0.fileURL?.pathExtension.lowercased() == format })
            let url = try XCTUnwrap(file.fileURL)
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
            if format == "pdf" { XCTAssertNotNil(PDFDocument(url: url)) }
            if format == "csv" {
                let csv = try CSVTable.parse(String(contentsOf: url, encoding: .utf8))
                XCTAssertEqual(try csv.summary(column: "amount", operation: "sum"), "4000.0")
            }
        }
    }

    func testLocalSpeechFromRecordedAudio() async throws {
        let samples = try recordedSamples()
        let start = Date()
        let result = try await WhisperRuntime.shared.transcribe(samples)
        print("LIVE_SPEECH total=\(Date().timeIntervalSince(start)) transcript=\(result)")
        XCTAssertTrue(result.localizedCaseInsensitiveContains("quiet"))
        XCTAssertTrue(result.localizedCaseInsensitiveContains("garden"))
    }

    private func recordedSamples() throws -> [Float] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "quiet-gardens", withExtension: "aiff"))
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let converter = try SpeechBufferConverter(from: file.processingFormat, to: target)
        let converted = try XCTUnwrap(converter.convert(buffer))
        let floats = try XCTUnwrap(converted.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: floats, count: Int(converted.frameLength)))
    }

    func testCreatesChartAndDiagramImages() async throws {
        let (_, db, files, memory, writer) = try workspace()
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        for prompt in ["Create a bar chart comparing Harbor at 3200 dollars and Riverside at 4100 dollars.",
                       "Create a flow diagram with three steps: inspect venues, compare prices, book the venue."] {
            let result = try await answer(prompt, client: client)
            let output = try XCTUnwrap(result.outputs.first)
            let url = try XCTUnwrap(output.fileURL)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
    }

    func testSimpleContextGetsBriefAcknowledgment() async throws {
        let (_, db, files, memory, writer) = try workspace()
        try await memory.save(MemoryItem(text: "I prefer quiet venues.", origin: "Test", state: .saved))
        try await memory.save(MemoryItem(text: "I prefer venues with step-free entrances.", origin: "Test", state: .saved))
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        let result = try await answer("I prefer venues with step-free entrances.", client: client)
        XCTAssertLessThan(result.text.count, 500)
        XCTAssertFalse(result.text.contains("|"))
        XCTAssertTrue(result.outputs.isEmpty)
    }

    func testTemporaryRequirementsAreNotMemories() async throws {
        let (_, _, _, memory, _) = try workspace()
        let service = MemoryService(repository: memory)
        let request = ReplyRequest(conversationID: UUID(), prompt: "Now we need seating for 140 guests. Which venue qualifies, and what accessibility information still needs checking?", history: [], modelID: SystemModelCatalog.modelID, selectedSourceIDs: [])
        try await service.capture(request, scope: RequestScope()) { _ in }
        let saved = try await memory.all()
        XCTAssertTrue(saved.isEmpty, "A changed guest count and a question must stay in the conversation")
    }

    func testExplicitRememberAndEnduringContextRemainEligible() async throws {
        let (_, _, _, memory, _) = try workspace()
        let service = MemoryService(repository: memory)
        for prompt in ["I live in Portland and work as a mobile engineer.", "Please remember that my event budget is 4200 dollars."] {
            let request = ReplyRequest(conversationID: UUID(), prompt: prompt, history: [], modelID: SystemModelCatalog.modelID, selectedSourceIDs: [])
            try await service.capture(request, scope: RequestScope()) { _ in }
        }
        let saved = try await memory.all()
        XCTAssertTrue(saved.contains { $0.text.contains("Portland") })
        XCTAssertTrue(saved.contains { $0.text.contains("4200") })
    }

    func testCSVCalculationUsesLocalToolEvidence() async throws {
        let (root, db, files, memory, writer) = try workspace()
        let url = root.appendingPathComponent("expenses.csv")
        try "item,amount\nroom,3200\ncatering,800\n".write(to: url, atomically: true, encoding: .utf8)
        let importer = LocalDocumentImporter(files: WorkspaceFiles(root: root), database: db, repository: files)
        let source = try await importer.prepare(Attachment(name: "expenses.csv", kind: .spreadsheet, readiness: .importing, fileURL: url))
        let client = LocalAssistantClient(database: db, attachments: files, memories: MemoryService(repository: memory), writer: writer)
        let result = try await answer("Use the calculation tool to sum the amount column in expenses.csv and report the total with its source.", client: client, sources: [source.id])
        XCTAssertTrue(result.text.contains("4,000") || result.text.contains("4000"))
        XCTAssertTrue(result.citations.contains { $0.locator.contains("Calculated:") })
        XCTAssertLessThan(result.text.count, 1500, "A simple sum should not produce a verbose or malformed table")
    }

    @MainActor
    func testRecordedVoiceCallContinuesThroughTwoTurns() async throws {
        let (_, db, files, memory, writer) = try workspace()
        try await WhisperRuntime.shared.prepare()
        let service = MemoryService(repository: memory)
        let speech = RecordedSpeechInput(samples: try recordedSamples())
        let assistant = LocalAssistantClient(database: db, attachments: files, memories: service, writer: writer)
        let container = AppContainer(assistant: assistant, speech: speech,
                                     conversations: LocalConversationRepository(database: db), attachments: files,
                                     memories: memory, modelCatalog: SystemModelCatalog(), memoryCapture: service)
        let chat = ChatSessionStore(container: container)
        await chat.load()
        let voice = VoiceSessionController(speech: speech, chat: chat)
        defer { voice.exit() }
        voice.start()
        let deadline = Date().addingTimeInterval(65)
        while Date() < deadline {
            if await speech.probe.playbackCount == 2, await speech.probe.inputCount >= 3, voice.state == .listening, !chat.memories.isEmpty { break }
            if chat.messages.last?.status == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(voice.state, .listening, "After two spoken replies, the same call must still be listening")
        let inputCount = await speech.probe.inputCount
        XCTAssertGreaterThanOrEqual(inputCount, 3)
        voice.handoffToKeyboard()
        try await Task.sleep(for: .milliseconds(150)) // Drain canceled capture/playback callbacks before teardown.
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 2)
        XCTAssertTrue(chat.messages.first?.text.localizedCaseInsensitiveContains("quiet gardens") == true)
        XCTAssertEqual(chat.messages.last?.status, .complete)
        let receiptIDs = chat.messages.filter { $0.role == .assistant }.flatMap(\.savedMemoryIDs)
        XCTAssertFalse(receiptIDs.isEmpty, "The originating reply must carry the committed memory receipt")
        XCTAssertTrue(receiptIDs.allSatisfy { id in chat.memories.contains { $0.id == id } })
        XCTAssertTrue(chat.messages.last?.savedMemoryIDs.isEmpty == true, "Repeating the same fact must not claim another memory was saved")
        let played = await speech.probe.playbackCount
        let spoke = await speech.probe.sawSpeechRange
        XCTAssertEqual(played, 2, "Both real synthesis passes must finish before returning to listening")
        XCTAssertTrue(spoke, "A synthesis delegate callback must confirm speech started")
        XCTAssertEqual(voice.state, .idle)
    }

    /// Isolates audio continuity when the independent Foundation Models runtime is unavailable.
    @MainActor
    func testTwoRecordedSpeechTurnsWithScriptedReplies() async throws {
        try await WhisperRuntime.shared.prepare() // First-install download is setup, not conversational latency.
        let speech = RecordedSpeechInput(samples: try recordedSamples())
        let container = AppContainer(assistant: ScriptedVoiceReplies(), speech: speech,
                                     conversations: InMemoryConversationRepository([]), attachments: InMemoryAttachmentRepository([]),
                                     memories: InMemoryMemoryRepository([]), modelCatalog: FixtureModelCatalog())
        let chat = ChatSessionStore(container: container)
        await chat.load()
        let voice = VoiceSessionController(speech: speech, chat: chat)
        defer { voice.exit() }
        voice.start()
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if await speech.probe.playbackCount == 2, await speech.probe.inputCount >= 3, voice.state == .listening { break }
            if case .unavailable = voice.state { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let played = await speech.probe.playbackCount
        XCTAssertEqual(played, 2)
        XCTAssertEqual(voice.state, .listening)
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 2)
        XCTAssertTrue(chat.messages.filter { $0.role == .user }.allSatisfy { $0.text.localizedCaseInsensitiveContains("quiet gardens") })
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playAndRecord, "The call must retain its duplex audio route between turns")
        voice.handoffToKeyboard()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(voice.state, .idle)
    }

    func testInstalledSpeechVoiceSelection() throws {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let selected = try XCTUnwrap(LocalSpeechVoice.preferred(language: language))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        print("LOCAL_VOICE selected=\(selected.name) language=\(selected.language) quality=\(selected.quality.rawValue)")
        for voice in voices { print("LOCAL_VOICE available=\(voice.name) quality=\(voice.quality.rawValue)") }
        XCTAssertFalse(selected.voiceTraits.contains(.isNoveltyVoice))
        XCTAssertFalse(selected.voiceTraits.contains(.isPersonalVoice))
        XCTAssertEqual(selected.language, language)
        XCTAssertEqual(selected.quality.rawValue, voices.map { $0.quality.rawValue }.max())
    }

    @MainActor
    func testReadAloudPlaysTwoRepliesInSequence() async throws {
        let reader = SpeechReader()
        defer { reader.stop() }
        for text in ["Your draft stays here until you send it.", "The second reply can be read aloud too."] {
            reader.toggle(UUID(), text: text)
            let deadline = Date().addingTimeInterval(20)
            while reader.speakingID != nil, Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertNil(reader.failure)
            XCTAssertGreaterThan(reader.spokenRangeCount, 0, "A real synthesizer callback must confirm playback")
            XCTAssertNil(reader.speakingID, "Playback should finish and clear the player")
        }
    }

    @MainActor
    func testFinishingRecordedDictationFlushesRemainingAudio() async throws {
        let samples = try recordedSamples()
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        let capture = try await WhisperCapture.make(format: format, onText: { _ in }, onEnd: {}, onError: { XCTFail($0) })
        defer { capture.cancel() }
        capture.feed(buffer)
        // Finish before the periodic recognition loop: the final flush must recover the words.
        let result = await capture.finish()
        let final = try XCTUnwrap(result)
        XCTAssertTrue(final.localizedCaseInsensitiveContains("quiet gardens"), final)
    }
}

private struct ScriptedVoiceReplies: AssistantClient {
    func send(_ request: ReplyRequest) -> AsyncStream<ReplyEvent> {
        AsyncStream { $0.yield(.text("Quiet gardens. Understood.")); $0.yield(.finished); $0.finish() }
    }
}

/// Only the microphone source is replaced. Recognition, agent, storage and synthesis are real.
private struct RecordedSpeechInput: SpeechClient {
    let samples: [Float]
    let probe = RecordedSpeechProbe()
    func beginConversation(id: UUID) async { await LocalSpeechClient().beginConversation(id: id) }
    func endConversation(id: UUID) async { await LocalSpeechClient().endConversation(id: id) }
    func listen() -> AsyncStream<TranscriptEvent> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.ready)
                guard await probe.takeInput() else { return }
                do {
                    let text = try await WhisperRuntime.shared.transcribe(samples)
                    try Task.checkCancellation()
                    continuation.yield(.final(text))
                } catch { continuation.yield(.unavailable(error.localizedDescription)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func speak(_ text: String) -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await event in LocalSpeechClient().speak(text) {
                    switch event {
                    case .level(let level): if level > 0 { await probe.spoke() }
                    case .finished: await probe.played()
                    case .failed: break
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor RecordedSpeechProbe {
    private(set) var inputCount = 0
    private(set) var playbackCount = 0
    private(set) var sawSpeechRange = false
    func takeInput() -> Bool {
        inputCount += 1
        return inputCount <= 2
    }
    func played() { playbackCount += 1 }
    func spoke() { sawSpeechRange = true }
}
