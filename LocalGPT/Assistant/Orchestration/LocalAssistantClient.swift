import Foundation
import FoundationModels

struct LocalAssistantClient: AssistantClient {
    let database: WorkspaceDatabase
    let attachments: any AttachmentRepository
    let memories: MemoryService
    let writer: ArtifactWriter

    func send(_ request: ReplyRequest) -> AsyncStream<ReplyEvent> {
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
                    let service = WorkspaceToolService(
                        request: request, scope: scope, database: database,
                        attachments: attachments, writer: writer, emit: { continuation.yield($0) })
                    toolService = service
                    try await AssistantTurn(
                        request: request, service: service, memories: memories,
                        scope: scope, attachments: attachments,
                        emit: { continuation.yield($0) }
                    ).run(model: model)
                } catch is CancellationError {
                    // The caller already marks the visible reply stopped.
                } catch {
                    let outputs = await toolService?.generatedOutputs() ?? []
                    if !outputs.isEmpty, !Task.isCancelled {
                        continuation.yield(
                            .text(
                                OutputReceipt.text(outputs)
                                    + "\n\nThe model could not finish the rest of its response. Inspect the files in Outputs; any additional requested work may need another message."
                            ))
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
            continuation.onTermination = { _ in
                scope.cancel()
                task.cancel()
                deadline.cancel()
            }
        }
    }

    private static func message(for error: Error) -> String {
        if #available(iOS 27.0, *), let modelError = error as? LanguageModelError {
            switch modelError {
            case .contextSizeExceeded:
                return
                    "This request exceeds the local model's context. Select fewer images or sources, or start a new chat."
            case .unsupportedCapability:
                return
                    "The current on-device model does not support this request. Check Apple Intelligence setup and iOS updates."
            case .guardrailViolation, .refusal:
                return "The on-device model declined this request. Try a different question."
            case .rateLimited:
                return "The on-device model is busy. Wait a moment and retry."
            default: break
            }
        }
        guard let error = error as? LanguageModelSession.GenerationError else {
            if (error as NSError).domain.hasPrefix("FoundationModels.") {
                return "The on-device model could not finish this answer. Please retry or simplify the question."
            }
            return error.localizedDescription
        }
        switch error {
        case .exceededContextWindowSize:
            return "This request exceeds the local model's context. Select fewer sources or start a new chat."
        case .assetsUnavailable:
            return "The on-device model assets are unavailable. Check Apple Intelligence in Settings and try again."
        case .decodingFailure:
            return "The local model could not produce a valid answer. Retry or ask a shorter question."
        case .guardrailViolation, .refusal:
            return "The on-device model declined this request. Try a different question."
        case .unsupportedLanguageOrLocale:
            return "The on-device model does not support this language. Try another language."
        case .rateLimited, .concurrentRequests: return "The on-device model is busy. Wait a moment and retry."
        case .unsupportedGuide:
            return "This system model cannot use the requested response format. Check for an iOS update."
        @unknown default: return "The on-device model could not finish. Your conversation is saved; please retry."
        }
    }
}
