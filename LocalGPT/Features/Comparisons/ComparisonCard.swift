import SwiftUI

/// The side-by-side comparison artifact inside an assistant reply: one row per
/// criterion, cited values, the facts still missing, and per-chat notes.
struct ComparisonCard: View {
    let comparison: Comparison

    @Environment(ChatSessionStore.self) private var chat

    private static let padX: CGFloat = pt(16)
    private static let radius: CGFloat = pt(20)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            optionHeader
            ForEach(comparison.criteria) { criterion in
                divider
                criterionRow(criterion)
            }
            if !comparison.unknowns.isEmpty {
                divider
                missing
            }
            divider
            notes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.cardFill, in: .rect(cornerRadius: Self.radius, style: .continuous))
        .clipShape(.rect(cornerRadius: Self.radius, style: .continuous))
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: pt(8)) {
            Text(comparison.title)
                .font(.title)
                .foregroundStyle(Tokens.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if comparison.isRevision {
                Text("Revised")
                    .font(.caption)
                    .foregroundStyle(Tokens.foreground)
            }
        }
        .padding(.horizontal, Self.padX)
        .padding(.top, pt(14))
        .padding(.bottom, pt(12))
    }

    private var optionHeader: some View {
        columns { option in
            Text(option.label)
                .font(.caption)
                .foregroundStyle(Tokens.foregroundSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, Self.padX)
        .padding(.vertical, pt(10))
    }

    private func criterionRow(_ criterion: Comparison.Criterion) -> some View {
        VStack(alignment: .leading, spacing: pt(4)) {
            Text(criterion.label)
                .font(.caption)
                .foregroundStyle(Tokens.foregroundSecondary)
            columns { option in
                value(comparison.cell(criterion, option))
            }
        }
        .padding(.horizontal, Self.padX)
        .padding(.vertical, pt(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if criterion.id == comparison.revisedCriterionID {
                Rectangle()
                    .fill(Tokens.foreground)
                    .frame(width: pt(2))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func value(_ cell: Comparison.Cell) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: pt(3)) {
            if let value = cell.value {
                Text(value)
                    .font(.text)
                    .foregroundStyle(Tokens.foreground)
            } else {
                Text("Unknown")
                    .font(.text)
                    .foregroundStyle(Tokens.foregroundMuted)
            }
            ForEach(cell.citations) { citation in
                CitationChip(citation: citation)
            }
        }
    }

    private var missing: some View {
        Text("Missing: \(comparison.unknowns.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(Tokens.foregroundSecondary)
            .padding(.horizontal, Self.padX)
            .padding(.vertical, pt(10))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notes: some View {
        @Bindable var chat = chat
        return VStack(alignment: .leading, spacing: pt(4)) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(Tokens.foregroundSecondary)
            TextField(
                "",
                text: $chat.notes,
                prompt: Text("Add a note").foregroundStyle(Tokens.foregroundMuted),
                axis: .vertical
            )
            .font(.text)
            .foregroundStyle(Tokens.foreground)
            .lineLimit(1...6)
            .accessibilityLabel("Notes")
        }
        .padding(.horizontal, Self.padX)
        .padding(.top, pt(10))
        .padding(.bottom, pt(14))
    }

    private var divider: some View {
        Rectangle()
            .fill(Tokens.border)
            .frame(height: 0.5)
            .padding(.leading, Self.padX)
    }

    /// Two equal columns, one per option.
    private func columns<Cell: View>(@ViewBuilder _ cell: @escaping (Comparison.Option) -> Cell) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: pt(12)) {
            ForEach(comparison.options) { option in
                cell(option)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
