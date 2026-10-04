import Foundation

/// References may only point at passages actually returned by a scoped tool.
enum ReplyValidation {
    static func referenceNumbers(in text: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return [] }
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return Int(text[range])
        })
    }

    static func validate(_ text: String, evidence: [Citation]) throws -> String {
        guard !evidence.isEmpty else { return text }
        let references = referenceNumbers(in: text)
        let available = Set(evidence.map(\.number))
        guard references.isSubset(of: available) else {
            throw WorkspaceError.message("The reply contained an unverified source reference. Review the available passages or retry.")
        }
        guard !evidence.isEmpty, references.isEmpty else { return text }
        // Never invent a claim-to-passage mapping if the model omits it twice.
        // The list is explicitly labeled as sources read, rather than supporting every assertion.
        let list = evidence.map { "[\($0.number)]" }.joined(separator: " ")
        return text + "\n\nSources read: " + list
    }
}
