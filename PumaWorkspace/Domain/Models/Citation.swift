import Foundation

struct Citation: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Display number used by citation chips.
    var number: Int
    var sourceID: UUID
    /// e.g. "Page 2 · lines 14–22" or "Image text region".
    var locator: String
    /// The original passage containing the cited span.
    var excerpt: String
    /// Cited span inside `excerpt`, as UTF-16 offsets.
    var range: Range<Int>

    init(id: UUID = UUID(), number: Int, sourceID: UUID, locator: String, excerpt: String, range: Range<Int>) {
        self.id = id
        self.number = number
        self.sourceID = sourceID
        self.locator = locator
        self.excerpt = excerpt
        self.range = range
    }
}
