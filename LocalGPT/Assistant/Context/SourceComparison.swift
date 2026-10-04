import Foundation
import FoundationModels

@Generable
struct SourceNumericPlan {
    @Guide(description: "Numeric requirements in the latest user question. For example, needing seating for 140 guests means atLeast 140 guests. Extract every option, including those that fail. Empty if the question has no numeric requirement.", .maximumCount(3))
    var comparisons: [SourceNumericComparison]
}

@Generable
struct SourceNumericComparison {
    @Guide(description: "Exact words from the latest user question containing the required number and unit.")
    var requirementQuote: String
    var threshold: Double
    @Guide(description: "The shared unit appearing literally in the requirement and the source quotes, such as guests.")
    var unit: String
    var relation: SourceNumericRelation
    @Guide(description: "Every option to compare, including insufficient options. Values must be copied from the cited source.", .maximumCount(6))
    var options: [SourceNumericOption]
}

@Generable
enum SourceNumericRelation: String { case atLeast, atMost, exactly }

@Generable
struct SourceNumericOption {
    var name: String
    var value: Double
    var citation: Int
    @Guide(description: "An exact source quote containing this option's numeric value and unit.")
    var quote: String
}

/// Numerical qualification is deterministic after quote-validated extraction.
/// Additional facts come directly from the cited passages, not a second model verdict.
enum SourceComparison {
    static func answer(question: String, evidence: [Citation], sources: [Attachment]) async throws -> String? {
        let names = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, ($0.name as NSString).deletingPathExtension) })
        if let direct = directRequirement(question: question, evidence: evidence, names: names),
           let answer = render(try .init(direct.generatedContent), question: question, evidence: evidence, names: names) {
            return answer
        }
        let session = LanguageModelSession(instructions: """
            Extract numeric requirements from the user's question and matching values from the source passages.
            Copy requirementQuote from the question and option quotes from the sources exactly.
            Do not invent requirements. Extract only requirements actually stated, not every possible relation.
            Include all named options, even those with insufficient values. Do not calculate qualification.
            """)
        let passages = evidence.map { "[\($0.number)] \($0.excerpt)" }.joined(separator: "\n\n")
        let result = try await session.respond(to: "Question: \(question)\n\nSource passages:\n\(passages)", generating: SourceNumericPlan.self, options: GenerationOptions(maximumResponseTokens: 900))
        guard !result.content.comparisons.isEmpty else { return nil }
        let answers = try verifiedAnswers(result.content, question: question, evidence: evidence)
        guard !answers.isEmpty else {
            throw WorkspaceError.message("The numeric requirement could not be matched to all selected sources. Inspect the citations or specify the value and unit more clearly.")
        }
        return answers.joined(separator: "\n\n")
    }

    static func verifiedAnswers(_ plan: SourceNumericPlan, question: String, evidence: [Citation]) throws -> [String] {
        var seen = Set<String>()
        return try plan.comparisons.compactMap {
            guard let answer = render(try .init($0.generatedContent), question: question, evidence: evidence),
                  seen.insert(answer).inserted else { return nil }
            return answer
        }
    }

    static func render(_ plan: SourceNumericComparison.PartiallyGenerated, question: String, evidence: [Citation], names: [UUID: String] = [:]) -> String? {
        guard let quote = plan.requirementQuote, quote.count >= 5, question.localizedCaseInsensitiveContains(quote),
              let threshold = plan.threshold, threshold.isFinite,
              let unit = plan.unit, !unit.isEmpty, quote.localizedCaseInsensitiveContains(unit),
              contains(threshold, unit: unit, in: quote),
              let relation = plan.relation, let options = plan.options else { return nil }
        var rows: [(String, Double, Citation)] = []
        for option in options {
            guard let name = option.name, !name.isEmpty, let number = option.citation,
                  let source = evidence.first(where: { $0.number == number }),
                  (source.excerpt.localizedCaseInsensitiveContains(name) || names[source.sourceID] == name),
                  let sourceQuote = option.quote, sourceQuote.count >= 5,
                  source.excerpt.localizedCaseInsensitiveContains(sourceQuote),
                  sourceQuote.localizedCaseInsensitiveContains(unit),
                  let value = option.value, value.isFinite, contains(value, unit: unit, in: sourceQuote) else { return nil }
            rows.append((name, value, source))
        }
        // Do not silently omit an option while claiming a comparison is complete.
        guard !rows.isEmpty, Set(rows.map { $0.2.sourceID }) == Set(evidence.map(\.sourceID)),
              Set(rows.map { $0.0.lowercased() }).count == rows.count else { return nil }
        let phrase: String
        switch relation {
        case .atLeast: phrase = "at least"
        case .atMost: phrase = "at most"
        case .exactly: phrase = "exactly"
        }
        var result = "Requirement: \(phrase) \(threshold.formatted()) \(unit)."
        for (name, value, citation) in rows {
            let qualifies: Bool
            switch relation {
            case .atLeast: qualifies = value >= threshold
            case .atMost: qualifies = value <= threshold
            case .exactly: qualifies = value == threshold
            }
            result += "\n\n\(name) \(qualifies ? "meets" : "does not meet") the requirement: \(value.formatted()) \(unit). [\(citation.number)]"
        }
        result += "\n\nSource details:"
        for (_, _, citation) in rows {
            let passage = String(citation.excerpt.prefix(600)).replacingOccurrences(of: "\n", with: " ")
            result += "\n\n> [\(citation.number)] \(passage)"
        }
        return result
    }

    /// Handle one explicit number-and-unit requirement without probabilistic extraction.
    /// Ambiguous values, multiple requirements, conversions, and unsupported phrasing
    /// fall back to quoted extraction; no value is guessed from a different field.
    static func directRequirement(question: String, evidence: [Citation], names: [UUID: String]) -> SourceNumericComparison? {
        guard let pattern = try? NSRegularExpression(pattern: #"(?<![\w.-])(-?\d[\d,]*(?:\.\d+)?)(?:\s+|-)([\p{L}%]+)\b"#),
              let match = pattern.matches(in: question, range: NSRange(question.startIndex..., in: question)).only,
              let numberRange = Range(match.range(at: 1), in: question),
              let unitRange = Range(match.range(at: 2), in: question),
              let quoteRange = Range(match.range, in: question),
              let threshold = Double(question[numberRange].replacingOccurrences(of: ",", with: "")) else { return nil }
        let prefix = String(question[..<numberRange.lowerBound].suffix(80)).lowercased()
        let suffix = question[unitRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard prefix.range(of: #"\b(not|don't|without)\b"#, options: .regularExpression) == nil,
              prefix.range(of: #"^\s*(do|does|did|should|could|would|can)\b"#, options: .regularExpression) == nil else { return nil }
        let relation: SourceNumericRelation
        if prefix.range(of: #"\b(at most|no more than|maximum)\b"#, options: .regularExpression) != nil { relation = .atMost }
        else if prefix.range(of: #"\bexactly\b"#, options: .regularExpression) != nil { relation = .exactly }
        else if prefix.range(of: #"\b(under|over|less|more|up to|budget|spend|cost)\b"#, options: .regularExpression) != nil { return nil }
        else if prefix.range(of: #"\b(need|require|minimum|at least)\b"#, options: .regularExpression) != nil || suffix.hasPrefix("requirement") { relation = .atLeast }
        else { return nil }
        let unit = String(question[unitRange])
        var options: [SourceNumericOption] = []
        for id in Set(evidence.map(\.sourceID)) {
            guard let name = names[id] else { return nil }
            var candidates: [(Double, Citation, String)] = []
            for source in evidence where source.sourceID == id {
                for valueMatch in pattern.matches(in: source.excerpt, range: NSRange(source.excerpt.startIndex..., in: source.excerpt)) {
                    guard let valueRange = Range(valueMatch.range(at: 1), in: source.excerpt),
                          let sourceUnitRange = Range(valueMatch.range(at: 2), in: source.excerpt),
                          let sourceQuoteRange = Range(valueMatch.range, in: source.excerpt),
                          source.excerpt[sourceUnitRange].localizedCaseInsensitiveCompare(unit) == .orderedSame,
                          let value = Double(source.excerpt[valueRange].replacingOccurrences(of: ",", with: "")) else { continue }
                    candidates.append((value, source, String(source.excerpt[sourceQuoteRange])))
                }
            }
            guard Set(candidates.map(\.0)).count == 1, let candidate = candidates.first else { return nil }
            options.append(SourceNumericOption(name: name, value: candidate.0, citation: candidate.1.number, quote: candidate.2))
        }
        guard !options.isEmpty else { return nil }
        return SourceNumericComparison(requirementQuote: String(question[quoteRange]), threshold: threshold, unit: unit,
                                       relation: relation, options: options.sorted { $0.citation < $1.citation })
    }

    private static func contains(_ number: Double, unit: String, in quote: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"-?\d[\d,]*(?:\.\d+)?"#) else { return false }
        return regex.matches(in: quote, range: NSRange(quote.startIndex..., in: quote)).contains {
            guard let range = Range($0.range, in: quote) else { return false }
            guard Double(quote[range].replacingOccurrences(of: ",", with: "")) == number else { return false }
            let before = quote[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let after = quote[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–"))).lowercased()
            let unit = unit.lowercased()
            // Bind the unit to this number, rather than another field elsewhere in the quote.
            return after.hasPrefix(unit) || before.hasSuffix(unit)
        }
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
