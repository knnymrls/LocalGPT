import Foundation

actor WorkspaceToolService {
    let request: ReplyRequest
    let scope: RequestScope
    let database: WorkspaceDatabase
    let attachments: any AttachmentRepository
    let writer: ArtifactWriter
    let emit: @Sendable (ReplyEvent) -> Void
    private var evidence: [Citation] = []
    private var operations = 0
    private var outputs: [Attachment] = []

    init(request:ReplyRequest,scope:RequestScope,database:WorkspaceDatabase,attachments:any AttachmentRepository,
         writer:ArtifactWriter,emit:@escaping @Sendable (ReplyEvent)->Void) {
        self.request=request;self.scope=scope;self.database=database;self.attachments=attachments;self.writer=writer;self.emit=emit
    }

    func initialEvidence() async throws -> String {
        let sources = try await readableSources().sorted { $0.name < $1.name }
        guard sources.count <= 6 else { throw WorkspaceError.message("Select up to six sources for one local-model request.") }
        guard !sources.isEmpty else { return "" }
        try begin("Reading selected sources")
        let allowance = max(400, 3600 / sources.count)
        var context: [String] = []
        for source in sources {
            let matches = try await database.search(request.prompt, sourceIDs: [source.id], limit: 1)
            let passages = matches.isEmpty ? try await database.search("", sourceIDs: [source.id], limit: 1) : matches
            let bounded = passages.map { SourcePassage(sourceID: $0.sourceID, locator: $0.locator, text: String($0.text.prefix(allowance))) }
            context.append("Document: \(source.name)\n" + (try register(bounded)))
        }
        return context.joined(separator: "\n\n")
    }

    func collectedEvidence() -> [Citation] { evidence }
    func generatedOutputs() -> [Attachment] { outputs }

    private func begin(_ step:String) throws {
        try scope.check()
        operations += 1
        guard operations <= 10 else { throw WorkspaceError.message("The tool limit for this reply was reached. Please narrow the request.") }
        emit(.step(step))
    }

    private func readableSources() async throws -> [Attachment] {
        try await attachments.all().filter { request.selectedSourceIDs.contains($0.id) && $0.readiness == .ready }
    }

    func search(_ query:String) async throws -> String {
        try begin("Searching selected sources")
        let sources = try await readableSources()
        let passages = try await database.search(query,sourceIDs:Set(sources.map(\.id)),limit:4)
        return try register(passages)
    }

    func read(_ sourceID:String) async throws -> String {
        try begin("Reading a source")
        guard let id = UUID(uuidString:sourceID), try await readableSources().contains(where:{$0.id == id}) else {
            throw WorkspaceError.message("This source is not selected or is unavailable.")
        }
        return try register(await database.search("",sourceIDs:[id],limit:4))
    }

    private func register(_ passages:[SourcePassage]) throws -> String {
        try scope.check()
        var result:[String]=[]
        for passage in passages {
            if let index = evidence.firstIndex(where: { $0.sourceID == passage.sourceID && $0.locator == passage.locator }),
               passage.text.count > evidence[index].excerpt.count {
                evidence[index].excerpt = passage.text
                evidence[index].range = 0..<passage.text.utf16.count
            }
            let existing = evidence.first { $0.sourceID == passage.sourceID && $0.locator == passage.locator }
            let citation = existing ?? Citation(number:evidence.count+1,sourceID:passage.sourceID,
                                                locator:passage.locator,excerpt:passage.text,range:0..<passage.text.utf16.count)
            if existing == nil { evidence.append(citation) }
            result.append("[\(citation.number)] Source \(passage.sourceID) · \(passage.locator)\n\(passage.text)")
        }
        emit(.documents(Array(Set(evidence.map(\.sourceID)))))
        emit(.citations(evidence))
        return result.isEmpty ? "No matching passages in the selected sources." : result.joined(separator:"\n\n")
    }

    func createFile(name:String,format:String,content:String) async throws -> String {
        try begin("Creating \(format.uppercased()) file")
        var body = content
        if ["pdf", "txt", "md", "text", "markdown"].contains(format.lowercased()),
           !request.selectedSourceIDs.isEmpty, request.prompt.contains(where: \.isNumber),
           let report = try await SourceComparison.answer(question: request.prompt, evidence: evidence, sources: readableSources()) {
            body = format.lowercased() == "pdf" ? report.replacingOccurrences(of: "\n\n> ", with: "\n\n") : report
        }
        let item = try await writer.document(name:name,format:format,content:body,conversationID:request.conversationID,scope:scope)
        outputs.append(item)
        emit(.output(item))
        return "Created \(item.name). Output ID: \(item.id). It is available in Outputs."
    }

    func createChart(name:String,labels:[String],values:[Double]) async throws -> String {
        try begin("Rendering a chart")
        let item = try await writer.chart(name:name,labels:labels,values:values,conversationID:request.conversationID,scope:scope)
        outputs.append(item)
        emit(.output(item));return "Created \(item.name) in Outputs."
    }

    func createDiagram(name:String,steps:[String]) async throws -> String {
        try begin("Rendering a diagram")
        let item = try await writer.diagram(name:name,steps:steps,conversationID:request.conversationID,scope:scope)
        outputs.append(item)
        emit(.output(item));return "Created \(item.name) in Outputs."
    }

    func table(sourceID:String,column:String,operation:String) async throws -> String {
        try begin("Calculating from a table")
        guard let id = UUID(uuidString:sourceID),
              let source = try await readableSources().first(where:{$0.id == id}),
              let url = source.fileURL, url.pathExtension.lowercased() == "csv" else {
            throw WorkspaceError.message("Choose a selected CSV file.")
        }
        let text = try String(contentsOf:url,encoding:.utf8)
        let result = try CSVTable.parse(text).summary(column:column,operation:operation)
        try scope.check()
        return try register([SourcePassage(sourceID: id, locator: "Calculated: \(operation) of \(column)",
                                          text: "\(operation) of \(column) in \(source.name): \(result)")])
    }
}
