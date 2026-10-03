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

    private func answer(_ prompt: String, client: LocalAssistantClient, sources: Set<UUID> = [], history: [Message] = []) async throws -> Answer {
        let start = Date()
        var firstToken: TimeInterval?
        var result = Answer()
        let request = ReplyRequest(conversationID: UUID(), prompt: prompt, history: history, modelID: SystemModelCatalog.modelID, selectedSourceIDs: sources)
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
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("quiet"))
        XCTAssertTrue(result.text.contains("4,200") || result.text.contains("4200"))
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

    func testMixedContextAndQuestionSavesOnlyTheContext() async throws {
        let (_, _, _, memory, _) = try workspace()
        let service = MemoryService(repository: memory)
        let request = ReplyRequest(conversationID: UUID(), prompt: "Now we need seating for 140 guests. Which venue qualifies, and what accessibility information still needs checking?", history: [], modelID: SystemModelCatalog.modelID, selectedSourceIDs: [])
        try await service.capture(request, scope: RequestScope()) { _ in }
        let saved = try await memory.all()
        XCTAssertFalse(saved.isEmpty)
        XCTAssertTrue(saved.contains { $0.text.contains("140") })
        XCTAssertFalse(saved.contains { $0.text.localizedCaseInsensitiveContains("which venue") || $0.text.contains("?") })
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
    func testRecordedVoiceTurnCreatesReplyMemoryAndSpeechPlayback() async throws {
        let (_, db, files, memory, writer) = try workspace()
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
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if await speech.probe.finishedPlayback, !chat.memories.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        voice.handoffToKeyboard()
        try await Task.sleep(for: .milliseconds(150)) // Drain canceled capture/playback callbacks before teardown.
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 1)
        XCTAssertTrue(chat.messages.first?.text.localizedCaseInsensitiveContains("quiet gardens") == true)
        XCTAssertEqual(chat.messages.last?.status, .complete)
        XCTAssertFalse(chat.messages.last?.savedMemoryIDs.isEmpty ?? true)
        let played = await speech.probe.finishedPlayback
        let spoke = await speech.probe.sawSpeechRange
        XCTAssertTrue(played, "Real synthesis should finish before returning to listening")
        XCTAssertTrue(spoke, "A synthesis delegate callback must confirm speech started")
        XCTAssertEqual(voice.state, .idle)
    }
}

/// Only the microphone source is replaced. Recognition, agent, storage and synthesis are real.
private struct RecordedSpeechInput: SpeechClient {
    let samples: [Float]
    let probe = RecordedSpeechProbe()
    func listen() -> AsyncStream<TranscriptEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard await probe.takeInput() else { continuation.finish(); return }
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
    private var inputUsed = false
    private(set) var finishedPlayback = false
    private(set) var sawSpeechRange = false
    func takeInput() -> Bool {
        guard !inputUsed else { return false }
        inputUsed = true
        return true
    }
    func played() { finishedPlayback = true }
    func spoke() { sawSpeechRange = true }
}
