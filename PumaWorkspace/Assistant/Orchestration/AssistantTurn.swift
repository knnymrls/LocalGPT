import Foundation
import FoundationModels

/// Runs one request through context preparation, generation, and reference validation.
struct AssistantTurn {
    let request: ReplyRequest
    let service: WorkspaceToolService
    let memories: MemoryService
    let scope: RequestScope
    let attachments: any AttachmentRepository
    let emit: @Sendable (ReplyEvent) -> Void

    func run(model: SystemLanguageModel) async throws {
        let sources = try await attachments.all()
        let selected = sources.filter { request.selectedSourceIDs.contains($0.id) && $0.readiness == .ready }
        let policy = ToolPolicy(request: request)
        if !selected.isEmpty, selected.allSatisfy({ $0.kind == .image }),
            !policy.files, !policy.charts, !policy.diagrams,
            ImageInputSupport.needsVisualUnderstanding(request.prompt)
        {
            emit(.text(ImageInputSupport.explanation))
            emit(.finished)
            return
        }
        let tools = tools(for: selected, policy: policy)
        let memoryContext = try await memories.context(for: request.prompt)
        let evidenceContext = try await service.initialEvidence()
        let isConversation = tools.isEmpty && selected.isEmpty
        let conversation =
            isConversation ? try await ConversationContext.prepare(request, memories: memoryContext) : nil
        let prompt: String
        if let conversation {
            prompt = conversation.prompt
        } else {
            prompt = try await ContextBuilder.build(
                request, sources: sources, memories: memoryContext, evidence: evidenceContext, tools: tools)
        }
        try scope.check()
        if policy.charts || policy.diagrams {
            try await VisualOutputResponder.respond(
                model: model, policy: policy, prompt: prompt, service: service, scope: scope, emit: emit)
            return
        }
        if policy.files, let format = policy.fileFormat {
            try await DocumentResponder.respond(
                model: model, request: request, format: format, prompt: prompt,
                service: service, scope: scope, emit: emit)
            return
        }
        let instructions =
            tools.isEmpty && selected.isEmpty ? ContextBuilder.conversationInstructions : ContextBuilder.instructions
        let session: LanguageModelSession
        if let conversation {
            session = LanguageModelSession(model: model, transcript: conversation.transcript)
        } else {
            session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
        }
        let structuredAnswer = !selected.isEmpty && !policy.files && !policy.charts && !policy.diagrams
        var answer = ""
        if structuredAnswer {
            let result = try await SourceResponder.respond(
                model: model, session: session, request: request, sources: sources,
                selected: selected, memoryContext: memoryContext, prompt: prompt, service: service, scope: scope,
                emit: emit)
            answer = result.text
            if result.isVerified {
                emit(.finished)
                return
            }
        } else if let conversation {
            answer = try await ConversationResponder.respond(
                session: session, context: conversation, request: request, scope: scope
            ) {
                emit(.text($0))
            }
        } else {
            for try await snapshot in session.streamResponse(
                to: prompt, options: GenerationOptions(maximumResponseTokens: 1200))
            {
                try scope.check()
                answer = snapshot.content
                let outputs = await service.generatedOutputs()
                emit(.text(outputs.isEmpty ? answer : OutputReceipt.text(outputs)))
            }
        }
        try scope.check()
        let outputs = await service.generatedOutputs()
        if !outputs.isEmpty {
            emit(.text(OutputReceipt.text(outputs)))
            emit(.finished)
            return
        }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceError.message(
                "The local model returned an empty answer. Please retry or simplify the question.")
        }
        let evidence = await service.collectedEvidence()
        let cited = ReplyValidation.referenceNumbers(in: answer)
        if !structuredAnswer, !evidence.isEmpty, cited.isEmpty {
            let revision = try await session.respond(
                to:
                    "Add inline square-bracket citations to your last answer using the supplied passage numbers. Preserve the answer to this current question: \(request.prompt)\nDo not call tools again or revive an earlier question.",
                options: GenerationOptions(maximumResponseTokens: 1200))
            try scope.check()
            answer = revision.content
        }
        let validated = try ReplyValidation.validate(answer, evidence: evidence)
        emit(.text(validated))
        emit(.finished)
    }

    private func tools(for selected: [Attachment], policy: ToolPolicy) -> [any Tool] {
        var tools: [any Tool] = []
        if !selected.isEmpty { tools += [SearchSourcesTool(service: service), ReadSourceTool(service: service)] }
        if selected.contains(where: { $0.fileURL?.pathExtension.lowercased() == "csv" }) {
            tools.append(QueryTableTool(service: service))
        }
        if policy.files { tools.append(CreateFileTool(service: service)) }
        if policy.charts { tools.append(CreateChartTool(service: service)) }
        if policy.diagrams { tools.append(CreateDiagramTool(service: service)) }
        return tools
    }
}
