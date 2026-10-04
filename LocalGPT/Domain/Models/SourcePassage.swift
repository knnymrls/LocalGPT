import Foundation

struct SourcePassage: Codable, Hashable, Sendable {
    var sourceID: UUID
    var locator: String
    var text: String
}
