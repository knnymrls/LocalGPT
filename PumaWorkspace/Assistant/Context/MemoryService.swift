import Foundation

/// Only saved user-authored context enters future prompts. Receipts are emitted after a durable write.
actor MemoryService: MemoryCapture {
    private let repository: any MemoryRepository
    private let extract: @Sendable (String) async throws -> [ExtractedMemory]
    init(repository: any MemoryRepository, extract: @escaping @Sendable (String) async throws -> [ExtractedMemory] = { try await MemoryExtractor().extract(from: $0) }) {
        self.repository = repository; self.extract = extract
    }

    func context(for prompt: String = "") async throws -> String {
        let items = try await repository.all()
        let words = Set(prompt.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 3 }.map(String.init))
        let ranked = items.filter { $0.state == .saved }.sorted { a, b in
            func score(_ item: MemoryItem) -> Int {
                words.filter { item.text.localizedCaseInsensitiveContains($0) }.count
            }
            let left = score(a), right = score(b)
            return left == right ? a.updatedAt > b.updatedAt : left > right
        }
        return ranked.prefix(16).map { "- \($0.text)" }.joined(separator: "\n")
    }

    func capture(_ request: ReplyRequest, onSaved: @Sendable (MemoryItem) async -> Void) async throws {
        try await capture(request, scope: RequestScope(), onSaved: onSaved)
    }

    func capture(_ request: ReplyRequest, scope: RequestScope, onSaved: @Sendable (MemoryItem) async -> Void) async throws {
        try scope.check()
        let candidates = try await extract(request.prompt)
        var existing = try await repository.all()
        for candidate in candidates {
            try scope.check()
            let key = MemoryExtractor.fingerprint(candidate.text)
            if existing.contains(where:{ $0.fingerprint == key || $0.text.localizedCaseInsensitiveCompare(candidate.text) == .orderedSame }) { continue }
            var item = MemoryItem(text:candidate.text,origin:"From this conversation",state:.saved)
            item.conversationID = request.conversationID
            item.messageID = request.userMessageID
            item.sourceQuote = candidate.evidence
            item.fingerprint = key
            guard MemoryPolicy.shouldSave(candidate, in: request.prompt) else { continue }
            guard try await repository.insertIfNew(item) else { continue }
            existing.append(item)
            await onSaved(item)
        }
    }
}
