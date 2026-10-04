import Foundation

/// Explicit output intent, including a follow-up format correction. Ordinary chat
/// never acquires output capabilities merely because an earlier turn made a file.
struct ToolPolicy: Sendable {
    let files: Bool
    let charts: Bool
    let diagrams: Bool
    let fileFormat: String?

    init(prompt: String) {
        let text = Self.normalize(prompt)
        let format = Self.format(in: text)
        let requested =
            Self.matches(
                text,
                #"\b(create|make|generate|export|save|write|build|produce|draw|render|plot|visualize|give|send|put|download|turn .* into|convert|update|revise|redo|regenerate)\b"#
            ) || Self.matches(text, #"^(a |an )?(pdf|txt|csv|json|markdown|text file)( please)?[.!?]?$"#)
        let declined = Self.matches(
            text,
            #"\b(don't|do not|never|without)\s+(create|make|generate|export|save|write|build|produce|draw|render|plot|visualize|give|send|put|download|convert|update|revise|redo|regenerate)\b"#
        )
        let enabled = requested && !declined
        charts = enabled && Self.matches(text, #"\b(chart|plot|graph|histogram)\b"#)
        diagrams = enabled && Self.matches(text, #"\b(diagram|flowchart|flow chart)\b"#)
        files = enabled && (format != nil || Self.matches(text, #"\b(file|script|report|document|spreadsheet)\b"#))
        fileFormat = files ? (format ?? "txt") : nil
    }

    init(request: ReplyRequest) {
        let direct = Self(prompt: request.prompt)
        let text = Self.normalize(request.prompt)
        let previous = request.history.last {
            $0.role == .user && $0.id != request.userMessageID && $0.text != request.prompt
        }.map { Self(prompt: $0.text) }
        let declined = Self.matches(text, #"\b(don't|do not|never|without)\b"#)
        let correction =
            Self.format(in: text) != nil
            && Self.matches(text, #"\b(i meant|instead|actually|rather|as a|as an)\b"#)
        if !declined, correction, previous?.files == true, let format = Self.format(in: text) {
            self.init(prompt: "Create a \(format) file")
            return
        }
        let revision =
            Self.matches(text, #"\b(update|revise|redo|regenerate|change|recreate)\b"#)
            && Self.matches(text, #"\b(it|that|same|again|version)\b"#)
        guard !direct.files, !direct.charts, !direct.diagrams, revision, !declined else {
            self = direct
            return
        }
        self = previous ?? direct
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func format(in text: String) -> String? {
        // A correction such as “TXT instead of PDF” gives the first format priority.
        let pattern = #"\b(pdf|txt|csv|json|markdown|md)\b|\btext\s+file\b|\.r\b|\br\s+(script|file|code)\b"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let value = String(text[range])
        if value == "markdown" { return "md" }
        if value.hasPrefix("text") { return "txt" }
        if value == ".r" || value.hasPrefix("r ") { return "r" }
        return value
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
