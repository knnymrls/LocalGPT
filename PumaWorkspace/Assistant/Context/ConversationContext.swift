import Foundation
import FoundationModels

/// Restores real speaker roles instead of asking the model to interpret a pasted chat log.
/// Rebuilt per request so cancellation, retries and chat switching cannot share stale state.
struct ConversationContext {
    let transcript: Transcript
    let prompt: String

    static func completedTurns(in request: ReplyRequest) -> [[Transcript.Entry]] {
        var turns: [[Transcript.Entry]] = []
        var pending: Message?
        for message in request.history {
            if message.id == request.userMessageID { break }
            guard !message.text.isEmpty else { continue }
            if message.role == .user {
                pending = message
            } else if let user = pending {
                if message.status == .complete {
                    turns.append([
                        .prompt(.init(id: user.id.uuidString, segments: [.text(.init(content: user.text))])),
                        .response(.init(id: message.id.uuidString, assetIDs: [], segments: [.text(.init(content: message.text))]))
                    ])
                }
                pending = nil
            }
        }
        return Array(turns.suffix(4))
    }

    static func prepare(_ request: ReplyRequest, memories: String) async throws -> Self {
        let instructions = Transcript.Entry.instructions(.init(
            segments: [.text(.init(content: ContextBuilder.conversationInstructions))], toolDefinitions: []
        ))
        let background = [String(memories.prefix(1600)), String(request.notes.prefix(1000))]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        // User-authored context stays in the user prompt, never in system instructions.
        let prompt = background.isEmpty ? request.prompt : """
            Known facts about the user:
            \(background)

            Use these facts when answering the question below. If a requested fact is missing, say it is unknown rather than asking the user to repeat facts supplied above.
            Latest user message:
            \(request.prompt)
            """
        var turns = completedTurns(in: request)
        if #available(iOS 26.4, *) {
            let model = SystemLanguageModel.default
            let promptTokens = try await model.tokenCount(for: prompt)
            let budget = model.contextSize - promptTokens - 1800
            while try await model.tokenCount(for: [instructions] + turns.flatMap { $0 }) > budget {
                guard !turns.isEmpty else {
                    throw WorkspaceError.message("This message is too long for the local model. Please shorten it or attach the text as a file.")
                }
                turns.removeFirst()
            }
        } else {
            // Conservative fallback on systems without the runtime token counter.
            while prompt.count + String(describing: turns).count > 6000, !turns.isEmpty { turns.removeFirst() }
            guard prompt.count <= 6000 else { throw WorkspaceError.message("Please shorten this message for the local model.") }
        }
        return Self(transcript: Transcript(entries: [instructions] + turns.flatMap { $0 }), prompt: prompt)
    }
}
