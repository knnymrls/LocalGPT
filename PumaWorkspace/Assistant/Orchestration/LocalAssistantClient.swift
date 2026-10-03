import Foundation
import FoundationModels

struct LocalAssistantClient: AssistantClient {
    let database: WorkspaceDatabase
    let attachments: any AttachmentRepository
    let memories: MemoryService
    let writer: ArtifactWriter

    func send(_ request:ReplyRequest) -> AsyncStream<ReplyEvent> {
        let scope = RequestScope()
        return AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                var toolService: WorkspaceToolService?
                do {
                    let model = SystemLanguageModel.default
                    guard model.isAvailable else {
                        let status = await SystemModelCatalog().models().first?.availability
                        throw WorkspaceError.message(status?.explanation ?? "The on-device model is unavailable.")
                    }
                    let service = WorkspaceToolService(request:request,scope:scope,database:database,
                                                       attachments:attachments,writer:writer,emit:{continuation.yield($0)})
                    toolService = service
                    let sources = try await attachments.all()
                    let selected = sources.filter { request.selectedSourceIDs.contains($0.id) && $0.readiness == .ready }
                    let policy = ToolPolicy(prompt: request.prompt)
                    var tools: [any Tool] = []
                    if !selected.isEmpty { tools += [SearchSourcesTool(service: service), ReadSourceTool(service: service)] }
                    if selected.contains(where: { $0.fileURL?.pathExtension.lowercased() == "csv" }) { tools.append(QueryTableTool(service: service)) }
                    if policy.files { tools.append(CreateFileTool(service: service)) }
                    if policy.charts { tools.append(CreateChartTool(service: service)) }
                    if policy.diagrams { tools.append(CreateDiagramTool(service: service)) }
                    let memoryContext = try await memories.context(for: request.prompt)
                    let evidenceContext = try await service.initialEvidence()
                    let isConversation = tools.isEmpty && selected.isEmpty
                    let conversation = isConversation ? try await ConversationContext.prepare(request, memories: memoryContext) : nil
                    let prompt: String
                    if let conversation { prompt = conversation.prompt }
                    else { prompt = try await ContextBuilder.build(request,sources:sources,memories:memoryContext,evidence:evidenceContext,tools:tools) }
                    try scope.check()
                    let instructions = tools.isEmpty && selected.isEmpty ? ContextBuilder.conversationInstructions : ContextBuilder.instructions
                    var session: LanguageModelSession
                    if let conversation { session = LanguageModelSession(model: model, transcript: conversation.transcript) }
                    else { session = LanguageModelSession(model:model,tools:tools,instructions:instructions) }
                    var answerPrompt = prompt
                    let structuredAnswer = !selected.isEmpty && !policy.files && !policy.charts && !policy.diagrams
                    if structuredAnswer {
                        // Keep tool selection separate from final writing. Small local models otherwise
                        // tend to repeat the last tool result instead of answering a revised question.
                        let completeSources = selected.allSatisfy {
                            !$0.previewText.isEmpty && $0.previewText.count <= 1200 && $0.fileURL?.pathExtension.lowercased() != "csv"
                        }
                        if !completeSources {
                            let initialEvidenceCount = await service.collectedEvidence().count
                            do {
                                _ = try await session.respond(to: prompt + "\nGather the evidence needed for the current question using source tools if necessary. Do not write the final answer yet.", options: GenerationOptions(maximumResponseTokens: 1200))
                            } catch LanguageModelSession.GenerationError.decodingFailure {
                                // Successful tool results are already validated and registered. The
                                // gatherer's unused prose can fail to decode without losing those facts.
                                guard await service.collectedEvidence().count > initialEvidenceCount else { throw WorkspaceError.message("The local model could not read these sources. Please retry.") }
                            }
                        }
                        try scope.check()
                        let gathered = await service.collectedEvidence().map {
                            "[\($0.number)] \($0.locator)\n\($0.excerpt)"
                        }.joined(separator: "\n\n")
                        answerPrompt = try await ContextBuilder.build(request, sources: sources, memories: memoryContext, evidence: gathered, tools: [], sourceAnswer: true)
                        session = LanguageModelSession(model: model, instructions: ContextBuilder.sourceAnswerInstructions(for: request))
                    }
                    var answer = ""
                    if structuredAnswer {
                        let sourceEvidence = await service.collectedEvidence()
                        if request.prompt.contains(where: \.isNumber) {
                            continuation.yield(.step("Checking source values"))
                            if let comparison = try await SourceComparison.answer(question: request.prompt, evidence: sourceEvidence, sources: selected) {
                                try scope.check()
                                continuation.yield(.text(comparison))
                                continuation.yield(.finished)
                                return
                            }
                        }
                        for try await snapshot in session.streamResponse(to: answerPrompt, generating: SourceAnswer.self, options: GenerationOptions(maximumResponseTokens: 1200)) {
                            try scope.check()
                            answer = SourceAnswer.markdown(snapshot.content)
                            if !answer.isEmpty { continuation.yield(.text(answer)) }
                        }
                    } else if let conversation {
                        answer = try await ConversationResponder.respond(session: session, context: conversation, request: request, scope: scope) {
                            continuation.yield(.text($0))
                        }
                    } else {
                        for try await snapshot in session.streamResponse(to:answerPrompt,options:GenerationOptions(maximumResponseTokens:1200)) {
                            try scope.check()
                            answer = snapshot.content
                            let outputs = await service.generatedOutputs()
                            continuation.yield(.text(outputs.isEmpty ? answer : Self.outputReceipt(outputs)))
                        }
                    }
                    try scope.check()
                    let outputs = await service.generatedOutputs()
                    if !outputs.isEmpty {
                        continuation.yield(.text(Self.outputReceipt(outputs)))
                        continuation.yield(.finished)
                        return
                    }
                    guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw WorkspaceError.message("The local model returned an empty answer. Please retry or simplify the question.")
                    }
                    let evidence = await service.collectedEvidence()
                    let cited = ReplyValidation.referenceNumbers(in: answer)
                    if !structuredAnswer, !evidence.isEmpty, cited.isEmpty {
                        let revision = try await session.respond(to: "Add inline square-bracket citations to your last answer using the supplied passage numbers. Preserve the answer to this current question: \(request.prompt)\nDo not call tools again or revive an earlier question.", options: GenerationOptions(maximumResponseTokens: 1200))
                        try scope.check()
                        answer = revision.content
                    }
                    let validated = try ReplyValidation.validate(answer, evidence: evidence)
                    continuation.yield(.text(validated))
                    continuation.yield(.finished)
                } catch is CancellationError {
                    // The caller already marks the visible reply stopped.
                } catch {
                    let outputs = await toolService?.generatedOutputs() ?? []
                    if !outputs.isEmpty, !Task.isCancelled {
                        continuation.yield(.text(Self.outputReceipt(outputs) + "\n\nThe model could not finish the rest of its response. Inspect the files in Outputs; any additional requested work may need another message."))
                        continuation.yield(.finished)
                    } else {
                        continuation.yield(.failed(Self.message(for: error)))
                    }
                }
            }
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(75)) } catch { return }
                scope.cancel()
                continuation.yield(.failed("The local model took too long. Try a shorter request."))
                continuation.finish()
                task.cancel()
            }
            continuation.onTermination = { _ in scope.cancel(); task.cancel(); deadline.cancel() }
        }
    }

    private static func outputReceipt(_ outputs: [Attachment]) -> String {
        "Created " + outputs.map(\.name).joined(separator: ", ") + ". Open the files below or in Outputs to inspect and share them."
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? LanguageModelSession.GenerationError else {
            if (error as NSError).domain.hasPrefix("FoundationModels.") {
                return "The on-device model could not finish this answer. Please retry or simplify the question."
            }
            return error.localizedDescription
        }
        switch error {
        case .exceededContextWindowSize: return "This request exceeds the local model's context. Select fewer sources or start a new chat."
        case .assetsUnavailable: return "The on-device model assets are unavailable. Check Apple Intelligence in Settings and try again."
        case .decodingFailure: return "The local model could not produce a valid answer. Retry or ask a shorter question."
        case .guardrailViolation, .refusal: return "The on-device model declined this request. Try a different question."
        case .unsupportedLanguageOrLocale: return "The on-device model does not support this language. Try another language."
        case .rateLimited, .concurrentRequests: return "The on-device model is busy. Wait a moment and retry."
        case .unsupportedGuide: return "This system model cannot use the requested response format. Check for an iOS update."
        @unknown default: return "The on-device model could not finish. Your conversation is saved; please retry."
        }
    }
}
