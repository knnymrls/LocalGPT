import Foundation
import FoundationModels

/// Selected-source evidence gathering and grounded final writing are separate model sessions.
enum SourceResponder {
    static func respond(
        model: SystemLanguageModel, session: LanguageModelSession, request: ReplyRequest, sources: [Attachment],
        selected: [Attachment], memoryContext: String, prompt: String,
        service: WorkspaceToolService, scope: RequestScope,
        emit: (ReplyEvent) -> Void
    ) async throws -> (text: String, isVerified: Bool) {
        // Keep tool selection separate from final writing. Small local models otherwise
        // tend to repeat the last tool result instead of answering a revised question.
        let completeSources = selected.allSatisfy {
            !$0.previewText.isEmpty && $0.previewText.count <= 1200 && $0.fileURL?.pathExtension.lowercased() != "csv"
        }
        if !completeSources {
            let initialEvidenceCount = await service.collectedEvidence().count
            do {
                _ = try await session.respond(
                    to: prompt
                        + "\nGather the evidence needed for the current question using source tools if necessary. Do not write the final answer yet.",
                    options: GenerationOptions(maximumResponseTokens: 1200))
            } catch LanguageModelSession.GenerationError.decodingFailure {
                // Successful tool results are already validated and registered. The
                // gatherer's unused prose can fail to decode without losing those facts.
                guard await service.collectedEvidence().count > initialEvidenceCount else {
                    throw WorkspaceError.message("The local model could not read these sources. Please retry.")
                }
            }
        }
        try scope.check()
        let gathered = await service.collectedEvidence().map {
            "[\($0.number)] \($0.locator)\n\($0.excerpt)"
        }.joined(separator: "\n\n")
        let answerPrompt = try await ContextBuilder.build(
            request, sources: sources, memories: memoryContext, evidence: gathered, tools: [], sourceAnswer: true)
        let writer = LanguageModelSession(
            model: model, instructions: ContextBuilder.sourceAnswerInstructions(for: request))
        var answer = ""

        let sourceEvidence = await service.collectedEvidence()
        if request.prompt.contains(where: \.isNumber) {
            emit(.step("Checking source values"))
            if let comparison = try await SourceComparison.answer(
                question: request.prompt, evidence: sourceEvidence, sources: selected)
            {
                try scope.check()
                emit(.text(comparison))
                return (comparison, true)
            }
        }
        for try await snapshot in writer.streamResponse(
            to: answerPrompt, generating: SourceAnswer.self, options: GenerationOptions(maximumResponseTokens: 1200))
        {
            try scope.check()
            answer = SourceAnswer.markdown(snapshot.content)
            if !answer.isEmpty { emit(.text(answer)) }
        }
        return (answer, false)
    }
}
