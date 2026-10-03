import Foundation
import FoundationModels

/// Constrain document answers before rendering Markdown. Free-form table generation
/// occasionally spent the entire response budget padding a single column with spaces.
@Generable
struct SourceAnswer {
    @Guide(description: "The latest user question, including its current numeric requirements. Do not substitute a source value or an earlier question.")
    var currentQuestion: String

    @Guide(description: "A direct concise answer with [1], [2] citations. Missing facts are unknown. No Markdown tables here.", .maximumCount(4))
    var paragraphs: [String]

    @Guide(description: "A table only if the latest question explicitly requests a table. Otherwise use empty headers and rows.")
    var table: SourceAnswerTable

    static func markdown(_ value: PartiallyGenerated) -> String {
        var sections = (value.paragraphs ?? []).filter { !$0.isEmpty }
        if let table = value.table, let headers = table.headers, !headers.isEmpty {
            func cell(_ text: String) -> String {
                text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
            }
            let columns = headers.count
            var lines = ["| " + headers.map(cell).joined(separator: " | ") + " |",
                         "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |"]
            for row in table.rows ?? [] {
                guard let cells = row.cells, cells.count == columns else { continue }
                lines.append("| " + cells.map(cell).joined(separator: " | ") + " |")
            }
            if lines.count > 2 { sections.append(lines.joined(separator: "\n")) }
        }
        return sections.joined(separator: "\n\n")
    }
}

@Generable
struct SourceAnswerTable {
    @Guide(description: "Named column headers, including the compared options. Empty when no table is requested.", .maximumCount(6))
    var headers: [String]
    @Guide(description: "Rows of source facts, with [1], [2] citations. Use Unknown for unspecified facts.", .maximumCount(12))
    var rows: [SourceAnswerRow]
}

@Generable
struct SourceAnswerRow {
    @Guide(description: "One short cell per column, in header order.", .count(2...6))
    var cells: [String]
}
