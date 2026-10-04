import Foundation

protocol DocumentImporter: Sendable {
    func prepare(_ attachment: Attachment) async throws -> Attachment
    func remove(_ id: UUID) async throws
}
