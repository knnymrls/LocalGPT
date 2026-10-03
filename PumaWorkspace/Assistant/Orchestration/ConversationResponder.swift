import Foundation
import FoundationModels

@Generable
private struct ConversationRepair {
    @Guide(description: "A direct, natural reply to the user's latest message. Continue their conversation rather than repeating a greeting or offering generic assistance. Do not mention the retry.")
    var reply: String
}

/// One bounded model retry for a repeated conversational answer, never a scripted replacement.
enum ConversationResponder {
    static func respond(session: LanguageModelSession, context: ConversationContext, request: ReplyRequest,
                        scope: RequestScope, emit: (String) -> Void) async throws -> String {
        let previous = repetitionCandidates(for: request)
        var answer = ""
        for try await snapshot in session.streamResponse(to: context.prompt, options: GenerationOptions(maximumResponseTokens: 1200)) {
            try scope.check()
            answer = snapshot.content
            // Check the opening before displaying another copy of a short prior answer.
            let candidate = normalized(answer)
            if previous.isEmpty || (candidate.split(separator: " ").count > 30 && !previous.contains(where: { repeats(candidate, $0) })) { emit(answer) }
        }
        guard previous.contains(where: { repeats(normalized(answer), $0) }) else { return answer }

        try scope.check()
        // Retain the user's context but remove the assistant prose that is causing the loop.
        let instructions = ContextBuilder.conversationInstructions + "\nYour previous attempt repeated an earlier answer. Give a fresh, direct response to the latest message."
        let recovery = LanguageModelSession(instructions: instructions)
        let prompt = try await recoveryPrompt(request, latest: context.prompt, instructions: instructions)
        let repaired = try await recovery.respond(to: prompt, generating: ConversationRepair.self,
                                                   options: GenerationOptions(maximumResponseTokens: 1200))
        try scope.check()
        answer = repaired.content.reply
        guard !previous.contains(where: { repeats(normalized(answer), $0) }) else {
            throw WorkspaceError.message("The local model got stuck repeating an earlier answer. Please retry or start a new chat.")
        }
        return answer
    }

    private static func recoveryPrompt(_ request: ReplyRequest, latest: String, instructions: String) async throws -> String {
        var earlier = request.history.filter { $0.role == .user && $0.id != request.userMessageID }
            .suffix(4).map { String($0.text.prefix(1000)) }
        func prompt() -> String { earlier.isEmpty ? latest : "Earlier user messages, for context only:\n\(earlier.joined(separator: "\n"))\n\n\(latest)" }
        if #available(iOS 26.4, *) {
            let model = SystemLanguageModel.default
            let budget = model.contextSize - (try await model.tokenCount(for: instructions)) - 1600
            while try await model.tokenCount(for: prompt()) > budget {
                guard !earlier.isEmpty else { throw WorkspaceError.message("Please shorten this message for the local model.") }
                earlier.removeFirst()
            }
        } else {
            while prompt().count > 6000, !earlier.isEmpty { earlier.removeFirst() }
        }
        return prompt()
    }

    static func repeats(_ candidate: String, _ previous: String) -> Bool {
        let left = Set(candidate.split(separator: " ")), right = Set(previous.split(separator: " "))
        guard !left.isEmpty, !right.isEmpty else { return false }
        let polarity: Set<Substring> = ["no", "not", "never", "cannot", "can", "yes", "doesn", "isn", "won"]
        guard left.intersection(polarity) == right.intersection(polarity),
              left.filter({ $0.contains(where: \.isNumber) }) == right.filter({ $0.contains(where: \.isNumber) }) else { return false }
        let smaller = min(left.count, right.count), larger = max(left.count, right.count)
        return Double(smaller) / Double(larger) >= 0.65
            && Double(left.intersection(right).count) / Double(smaller) >= 0.9
    }

    static func repetitionCandidates(for request: ReplyRequest) -> Set<String> {
        // An explicit repetition request, or asking the same question again, can correctly give the same answer.
        let prompt = normalized(request.prompt)
        let prior = request.history.filter { $0.id != request.userMessageID && !$0.text.isEmpty }
        if prior.last(where: { $0.role == .user }).map({ normalized($0.text) == prompt }) == true { return [] }
        if request.prompt.range(of: #"\b(repeat|say (that|it) again|verbatim|exact (same )?(words|answer))\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return [] }
        return Set(prior.filter { $0.role == .assistant && $0.status == .complete }.suffix(3)
            .map { normalized($0.text) }.filter { $0.split(separator: " ").count >= 10 })
    }

    static func normalized(_ text: String) -> String {
        var words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if let first = words.first, ["hey", "hi", "hello"].contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }
}
