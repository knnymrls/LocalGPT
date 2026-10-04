import SwiftUI

/// The passage behind a citation, with the cited span highlighted.
struct EvidenceSheet: View {
    let citation: Citation

    @Environment(ChatSessionStore.self) private var chat

    private var source: Attachment? {
        guard let a = chat.attachment(citation.sourceID), a.readiness != .removed else { return nil }
        return a
    }

    var body: some View {
        if let source, !citation.excerpt.isEmpty {
            SheetScaffold(title: source.name) {
                VStack(alignment: .leading, spacing: pt(8)) {
                    Text(citation.locator)
                        .font(.caption)
                        .foregroundStyle(Tokens.foregroundSecondary)
                        .padding(.horizontal, SheetMetrics.rowPadX)
                    Text(passage)
                        .font(.text)
                        .foregroundStyle(Tokens.foreground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SheetMetrics.rowPadX)
                        .background(Tokens.cardFill, in: .rect(cornerRadius: SheetMetrics.cardRadius, style: .continuous))
                }
            }
        } else {
            SheetScaffold(title: "Source") {
                SheetEmptyState(
                    icon: .draft,
                    title: "Source unavailable",
                    message: "This source was removed, so the passage can't be shown."
                )
            }
        }
    }

    /// The excerpt with `citation.range` (UTF-16 offsets) on an accent 12% fill.
    private var passage: AttributedString {
        var text = AttributedString(citation.excerpt)
        let excerpt = citation.excerpt
        let count = excerpt.utf16.count
        let lower = min(max(citation.range.lowerBound, 0), count)
        let upper = min(max(citation.range.upperBound, lower), count)
        guard lower < upper else { return text }
        let start = String.Index(utf16Offset: lower, in: excerpt)
        let end = String.Index(utf16Offset: upper, in: excerpt)
        if let range = Range(start..<end, in: text) {
            text[range].backgroundColor = Tokens.foreground.opacity(0.12)
        }
        return text
    }
}
