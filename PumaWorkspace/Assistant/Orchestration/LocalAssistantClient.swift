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
                do {
                    let model = SystemLanguageModel.default
                    guard model.isAvailable else {
                        let status = await SystemModelCatalog().models().first?.availability
                        throw WorkspaceError.message(status?.explanation ?? "The on-device model is unavailable.")
                    }
                    let service = WorkspaceToolService(request:request,scope:scope,database:database,
                                                       attachments:attachments,writer:writer,emit:{continuation.yield($0)})
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
                    let prompt = try await ContextBuilder.build(request,sources:sources,memories:memoryContext,evidence:evidenceContext,tools:tools)
                    try scope.check()
                    let instructions = tools.isEmpty && selected.isEmpty ? ContextBuilder.conversationInstructions : ContextBuilder.instructions
                    var session = LanguageModelSession(model:model,tools:tools,instructions:instructions)
                    var answerPrompt = prompt
                    if !selected.isEmpty && !policy.files && !policy.charts && !policy.diagrams {
                        // Keep tool selection separate from final writing. Small local models otherwise
                        // tend to repeat the last tool result instead of answering a revised question.
                        let completeSources = selected.allSatisfy {
                            !$0.previewText.isEmpty && $0.previewText.count <= 1200 && $0.fileURL?.pathExtension.lowercased() != "csv"
                        }
                        if !completeSources {
                            _ = try await session.respond(to: prompt + "\nGather the evidence needed for the current question using source tools if necessary. Do not write the final answer yet.", options: GenerationOptions(maximumResponseTokens: 1200))
                        }
                        try scope.check()
                        let gathered = await service.collectedEvidence().map {
                            "[\($0.number)] \($0.locator)\n\($0.excerpt)"
                        }.joined(separator: "\n\n")
                        answerPrompt = try await ContextBuilder.build(request, sources: sources, memories: memoryContext, evidence: gathered, tools: [])
                        session = LanguageModelSession(model: model, instructions: "Answer the user's current question using the provided source passages. Include names, comparisons to new requirements, and numbered citations [1], [2]. State what is missing. Earlier conversation is background only. Use a table only when the current question requests one.")
                    }
                    var answer = ""
                    for try await snapshot in session.streamResponse(to:answerPrompt,options:GenerationOptions(maximumResponseTokens:1200)) {
                        try scope.check()
                        answer = snapshot.content
                        continuation.yield(.text(answer))
                    }
                    try scope.check()
                    let evidence = await service.collectedEvidence()
                    let cited = ReplyValidation.referenceNumbers(in: answer)
                    if !evidence.isEmpty, cited.isEmpty {
                        let revision = try await session.respond(to: "Repeat your last answer with inline square-bracket citations using the passage numbers returned by the tools. Keep the facts and table. Do not call tools again.", options: GenerationOptions(maximumResponseTokens: 1200))
                        try scope.check()
                        answer = revision.content
                    }
                    let validated = try ReplyValidation.validate(answer, evidence: evidence)
                    continuation.yield(.text(validated))
                    continuation.yield(.finished)
                } catch is CancellationError {
                    // The caller already marks the visible reply stopped.
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
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
}
