import Foundation

/// Concrete dependencies for the app. The UI phase wires mocks only.
struct AppContainer: Sendable {
    var assistant: any AssistantClient
    var speech: any SpeechClient
    var conversations: any ConversationRepository
    var attachments: any AttachmentRepository
    var memories: any MemoryRepository
    var modelCatalog: any ModelCatalog

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppContainer {
        #if DEBUG
        return .mock(micUnavailable: arguments.contains("-micUnavailable"))
        #else
        // Real inference, speech, and persistence are later integration work.
        fatalError("Release services are not implemented in the UI phase.")
        #endif
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
