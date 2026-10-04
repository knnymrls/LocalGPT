import Foundation

/// A second gate after model classification: grounded does not necessarily mean worth remembering.
enum MemoryPolicy {
    static func hasOptOut(_ message: String) -> Bool {
        matches(#"\b(don['’]t|do not|never)\s+(remember|save|store)\b|\b(off the record|not for memory)\b"#, in: message)
    }

    static func shouldSave(_ item: ExtractedMemory, in message: String) -> Bool {
        guard !hasOptOut(message), MemoryExtractor.isGrounded(item, in: message) else { return false }
        switch item.kind {
        case .notMemory: return false
        case .explicitlyRequested:
            // The model cannot turn an ordinary request into consent to long-term memory.
            return matches(#"\b(remember (that|this|my|i|we)|save (this|that) (to|in|as) (your )?memory|keep (this|that) in mind (for|in) future)\b"#, in: message)
        case .lastingPreference, .enduringPersonalContext:
            // Conservative task/time boundaries; explicit remember requests can override these.
            let temporary = #"\b(today|tomorrow|tonight|yesterday|now|currently|budget|deadline|guest count|seating for)\b|\b(this|next) (event|trip|meeting|chat|task|time|week|month|year)\b|\bfor (the|our) (event|trip|meeting|task)\b"#
            let taskIntent = #"\b(just (testing|checking)|(i|we) (just )?(want|wanted|need|needed) to (test|try|check|see|create|compare|generate)|(test|try) this)\b"#
            return !matches(temporary, in: item.evidence) && !matches(taskIntent, in: item.evidence)
        }
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
