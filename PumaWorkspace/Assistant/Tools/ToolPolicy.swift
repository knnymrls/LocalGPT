import Foundation

/// Deterministic capability gating: ordinary chat never acquires output tools merely
/// because a previous turn created a file. Explicit revisions may inherit its kind.
struct ToolPolicy: Sendable {
    let files: Bool
    let charts: Bool
    let diagrams: Bool

    init(prompt: String) {
        let text = prompt.lowercased()
        let requested = Self.matches(
            text,
            #"\b(create|make|generate|export|save|write|build|produce|draw|render|plot|visualize|give me|download|turn .* into|convert|update|revise|redo|regenerate)\b"#
        )
        let declined = Self.matches(
            text,
            #"\b(don't|do not|never|without)\s+(create|make|generate|export|save|write|build|produce|draw|render|plot|visualize|download|convert|update|revise|redo|regenerate)\b"#
        )
        let enabled = requested && !declined
        files =
            enabled && Self.matches(text, #"\b(file|pdf|csv|markdown|json|script|report|document|spreadsheet)\b|\.r\b"#)
        charts = enabled && Self.matches(text, #"\b(chart|plot|graph|histogram)\b"#)
        diagrams = enabled && Self.matches(text, #"\b(diagram|flowchart|flow chart)\b"#)
    }

    init(request: ReplyRequest) {
        let direct = Self(prompt: request.prompt)
        let text = request.prompt.lowercased()
        let revision =
            Self.matches(text, #"\b(update|revise|redo|regenerate|change|recreate)\b"#)
            && Self.matches(text, #"\b(it|that|same|again|version)\b"#)
        let declined = Self.matches(text, #"\b(don't|do not|never|without)\b"#)
        guard !direct.files, !direct.charts, !direct.diagrams, revision, !declined else {
            self = direct
            return
        }
        // Only inherit from the immediately preceding user request; do not revive an old task.
        let previous = request.history.last {
            $0.role == .user && $0.id != request.userMessageID && $0.text != request.prompt
        }
        self = previous.map { Self(prompt: $0.text) } ?? direct
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
