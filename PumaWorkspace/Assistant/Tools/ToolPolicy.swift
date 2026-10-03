import Foundation

/// Narrow the tool surface before inference. A memory request cannot cause an unsolicited file.
struct ToolPolicy: Sendable {
    let files: Bool
    let charts: Bool
    let diagrams: Bool

    init(prompt: String) {
        let text = prompt.lowercased()
        func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        let outputRequest = matches(#"\b(create|make|generate|export|save|write|build|produce|draw|render|give me|download|turn .* into|convert)\b"#)
        files = outputRequest && matches(#"\b(file|pdf|csv|markdown|json|script|\.r|report|document|spreadsheet)\b"#)
        charts = outputRequest && matches(#"\b(chart|plot|graph|histogram)\b"#)
        diagrams = outputRequest && matches(#"\b(diagram|flowchart|flow chart)\b"#)
    }
}
