import Foundation

/// Live services by default; deterministic fixtures require an explicit debug launch flag.
struct AppContainer: Sendable {
    var assistant: any AssistantClient
    var speech: any SpeechClient
    var conversations: any ConversationRepository
    var attachments: any AttachmentRepository
    var memories: any MemoryRepository
    var modelCatalog: any ModelCatalog
    var importer: (any DocumentImporter)? = nil
    var memoryCapture: MemoryService? = nil

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppContainer {
        #if DEBUG
        if arguments.contains("-preview") || arguments.contains("-uiState") {
            return .mock(micUnavailable: arguments.contains("-micUnavailable"))
        }
        #endif
        let files = WorkspaceFiles(root: WorkspaceFiles.applicationRoot)
        let database = try WorkspaceDatabase(url: files.root.appendingPathComponent("workspace.sqlite"))
        let attachments = LocalAttachmentRepository(database: database)
        let memories = LocalMemoryRepository(database: database)
        let memoryCapture = MemoryService(repository: memories)
        let writer = ArtifactWriter(files: files, repository: attachments, database: database)
        return AppContainer(
            assistant: LocalAssistantClient(database: database, attachments: attachments,
                                            memories: memoryCapture, writer: writer),
            speech: LocalSpeechClient(),
            conversations: LocalConversationRepository(database: database),
            attachments: attachments, memories: memories, modelCatalog: SystemModelCatalog(),
            importer: LocalDocumentImporter(files: files, database: database, repository: attachments),
            memoryCapture: memoryCapture
        )
    }

    #if DEBUG
    static func mock(micUnavailable: Bool = false) -> AppContainer {
        AppContainer(
            assistant: MockAssistantClient(),
            speech: MockSpeechClient(unavailable: micUnavailable),
            conversations: InMemoryConversationRepository(Fixtures.conversations()),
            attachments: InMemoryAttachmentRepository(Fixtures.attachments),
            memories: InMemoryMemoryRepository(Fixtures.savedMemories),
            modelCatalog: FixtureModelCatalog()
        )
    }
    #endif
}
