import Foundation

struct Comparison: Hashable, Sendable {
    struct Criterion: Identifiable, Hashable, Sendable {
        let id: String
        var label: String
    }

    struct Option: Identifiable, Hashable, Sendable {
        let id: String
        var label: String
    }

    struct Cell: Hashable, Sendable {
        /// nil renders "Unknown".
        var value: String?
        var citations: [Citation]
    }

    var title: String
    var criteria: [Criterion]
    var options: [Option]
    /// cells[criterion.id][option.id]
    var cells: [String: [String: Cell]]
    /// Human-readable descriptions of missing facts.
    var unknowns: [String]
    /// Set when this is a revision; marks the changed criterion.
    var revisedCriterionID: String?

    var isRevision: Bool { revisedCriterionID != nil }

    func cell(_ criterion: Criterion, _ option: Option) -> Cell {
        cells[criterion.id]?[option.id] ?? Cell(value: nil, citations: [])
    }
}
