import Foundation

/// Independent, cancellable memory extraction. Receipts follow durable writes.
protocol MemoryCapture: Sendable {
    func capture(_ request: ReplyRequest, onSaved: @Sendable (MemoryItem) async -> Void) async throws
}
