import Foundation

/// Shared with tools so cancellation revokes their authority immediately.
final class RequestScope: @unchecked Sendable {
    private let lock = NSLock()
    private var revoked = false
    func cancel() { lock.withLock { revoked = true } }
    func check() throws {
        try Task.checkCancellation()
        if lock.withLock({ revoked }) { throw CancellationError() }
    }
}
