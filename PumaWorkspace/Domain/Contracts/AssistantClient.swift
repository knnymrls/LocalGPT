import Foundation

/// What the assistant needs to produce one reply.
struct ReplyRequest: Sendable {
    var conversationID: UUID
    var prompt: String
    var history: [Message]
    var modelID: String
    var selectedSourceIDs: Set<UUID>
    var userMessageID: UUID? = nil
    var notes: String = ""
}

enum ReplyEvent: Sendable {
    /// One thing the assistant is doing before it answers.
    case step(String)
    /// The sources the reply draws on.
    case documents([UUID])
    case token(String)
    case text(String)
    case memorySaved(MemoryItem)
    case output(Attachment)
    case citations([Citation])
    case artifact(Comparison)
    case memoryProposal(MemoryItem)
    case failed(String)
    case finished
}

/// Produces reply events. Stopping is cancellation: terminating the stream
/// (cancelling the consuming task) must stop the producer.
protocol AssistantClient: Sendable {
    func send(_ request: ReplyRequest) -> AsyncStream<ReplyEvent>
}
