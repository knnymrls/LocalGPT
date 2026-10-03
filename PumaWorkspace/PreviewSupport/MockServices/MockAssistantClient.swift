#if DEBUG
import Foundation

/// Scripted replies streamed at about 30 tokens per second.
struct MockAssistantClient: AssistantClient {
    var tokensPerSecond: Double = 30

    func send(_ request: ReplyRequest) -> AsyncStream<ReplyEvent> {
        let script = Self.script(for: request)
        let interval = Duration.milliseconds(Int(1000 / tokensPerSecond))
        return AsyncStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(700))
                for step in script.steps {
                    if Task.isCancelled { break }
                    continuation.yield(.step(step))
                    try? await Task.sleep(for: .milliseconds(900))
                }
                if !script.documents.isEmpty { continuation.yield(.documents(script.documents)) }
                for token in Self.tokens(script.text) {
                    if Task.isCancelled { break }
                    continuation.yield(.token(token))
                    try? await Task.sleep(for: interval)
                }
                if !Task.isCancelled {
                    if let artifact = script.artifact { continuation.yield(.artifact(artifact)) }
                    if let memory = script.memory { continuation.yield(.memoryProposal(memory)) }
                    continuation.yield(script.fails ? .failed("Reply interrupted. Try again.") : .finished)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct Script {
        var text: String
        var steps: [String] = []
        var documents: [UUID] = []
        var artifact: Comparison?
        var memory: MemoryItem?
        var fails = false
    }

    static func script(for request: ReplyRequest) -> Script {
        let prompt = request.prompt.lowercased()
        // Steps are only for specific work, such as reading a file. A plain
        // answer has none. The sources this chat can read, in a stable order.
        let sources = Fixtures.attachments.filter { request.selectedSourceIDs.contains($0.id) }
        let reading = sources.map { "Reading \($0.name)" }
        let used = sources.map(\.id)

        if prompt.contains("fail") {
            return Script(text: "Let me look through the proposals and", fails: true)
        }
        if prompt.contains("guest") || prompt.range(of: #"\b\d{2,3}\b"#, options: .regularExpression) != nil {
            return Script(
                text: Fixtures.revisedReply,
                steps: reading,
                documents: used,
                artifact: Fixtures.revisedComparison,
                memory: Fixtures.memoryProposal
            )
        }
        if prompt.contains("compare") {
            return Script(
                text: Fixtures.comparisonReply,
                steps: reading,
                documents: used,
                artifact: Fixtures.comparison
            )
        }
        if prompt.contains("missing") {
            return Script(
                text: """
                ## What's missing

                1. **Accessibility at Riverside Loft.** The proposal doesn't say whether the loft is step-free or has an elevator.
                2. **End time.** Neither proposal lists one.
                3. **Overtime rate.** Neither proposal gives a price for running late.

                It is worth asking both venues before you decide.
                """,
                steps: reading,
                documents: used
            )
        }
        if prompt.contains("screenshot") {
            return Script(
                text: """
                Maya's update confirms three things:

                - A final count of **140 guests**
                - All of them seated
                - Two guests who use wheelchairs

                That rules out Riverside Loft's seated capacity unless they can add tables.
                """,
                steps: reading,
                documents: used
            )
        }
        return Script(
            text: """
            I can help with that. Add the documents you want me to use with the **plus** button, then ask me to:

            - Compare them
            - Pull out specific details
            - Point out what's missing
            """
        )
    }

    /// Splits text into word-ish tokens that keep their trailing whitespace.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == " " { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
#endif
