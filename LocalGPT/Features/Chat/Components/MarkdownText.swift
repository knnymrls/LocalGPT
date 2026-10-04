import SwiftUI

/// A reply's Markdown, drawn as native text blocks: headings, paragraphs,
/// bullet and numbered lists, quotes, code, and rules. Metrics use 16pt body on a 21pt line, 8pt between blocks.
struct MarkdownText: View {
    let text: String
    /// Find in chat's query; every match is marked.
    var highlight = ""
    var citations: [Citation] = []
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: pt(8)) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { index, block in
                view(for: block, isFirst: index == 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Tokens.foreground)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "localgpt-evidence", let number = Int(url.host ?? ""),
                  let citation = citations.first(where: { $0.number == number }) else { return .systemAction }
            navigation.present(.evidence(citation))
            return .handled
        })
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(styled(text))
                .font(.system(size: Self.headingSize(level) * Tokens.uiScale, weight: .semibold))
                .padding(.top, isFirst ? 0 : pt(6))
        case .paragraph(let text):
            Text(styled(text))
                .font(.text)
                .lineSpacing(2)
        case .list(let items):
            VStack(alignment: .leading, spacing: pt(5)) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: pt(8)) {
                        Text(item.marker)
                            .font(.text)
                            .monospacedDigit()
                            .foregroundStyle(Tokens.foregroundSecondary)
                            .frame(minWidth: pt(12), alignment: .leading)
                        Text(styled(item.text))
                            .font(.text)
                            .lineSpacing(2)
                    }
                    .padding(.leading, CGFloat(item.depth) * pt(14))
                }
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 13 * Tokens.uiScale, design: .monospaced))
                    .lineSpacing(3)
                    .padding(pt(12))
            }
            .scrollIndicators(.hidden)
            .background(Tokens.hover, in: RoundedRectangle(cornerRadius: pt(10), style: .continuous))
        case .quote(let text):
            Text(styled(text))
                .font(.text)
                .lineSpacing(2)
                .foregroundStyle(Tokens.foregroundSecondary)
                .padding(.leading, pt(12))
                .padding(.vertical, pt(2))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(uiColor: Tokens.Palette.borderStrong)).frame(width: 2)
                }
        case .table(let rows):
            // Columns keep their natural width; a table wider than the
            // screen scrolls sideways rather than squeezing its text.
            ScrollView(.horizontal) { table(rows) }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        case .rule:
            Rectangle()
                .fill(Color(uiColor: Tokens.Palette.borderDivider))
                .frame(height: 0.5)
                .padding(.vertical, pt(4))
        }
    }

    /// A plain grid: semibold header row, hairlines between rows, no fill.
    private func table(_ rows: [[String]]) -> some View {
        let widths = (0..<(rows.map(\.count).max() ?? 0)).map { column in
            let natural = rows.enumerated().map { index, row -> CGFloat in
                guard column < row.count else { return 0 }
                let font = UIFont.systemFont(ofSize: 15 * Tokens.uiScale, weight: index == 0 ? .semibold : .regular)
                return (String(Self.inline(row[column]).characters) as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            return min(pt(220), max(pt(64), ceil(natural) + pt(2)))
        }
        return Grid(alignment: .topLeading, horizontalSpacing: pt(16), verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                if index > 0 {
                    Rectangle()
                        .fill(Color(uiColor: Tokens.Palette.borderDivider))
                        .frame(height: 0.5)
                        .gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                        Text(styled(cell))
                            .font(.system(size: 15 * Tokens.uiScale, weight: index == 0 ? .semibold : .regular))
                            .lineSpacing(2)
                            // One line up to a comfortable column width,
                            // wrapping only past it.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: widths[column], alignment: .leading)
                            .padding(.vertical, pt(9))
                    }
                }
            }
        }
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 18
        default: 16
        }
    }

    private func styled(_ text: String) -> AttributedString {
        var attributed = Self.inline(text)
        for citation in citations {
            let marker = "[\(citation.number)]"
            var search = attributed.startIndex..<attributed.endIndex
            while let range = attributed[search].range(of: marker) {
                attributed[range].link = URL(string: "localgpt-evidence://\(citation.number)")
                attributed[range].foregroundColor = Tokens.foreground
                search = range.upperBound..<attributed.endIndex
            }
        }
        return FindHighlight.mark(attributed, query: highlight)
    }

    /// Bold, italic, inline code, and links inside one block.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// The reply with its Markdown marks removed, for reading aloud.
    static func plain(_ text: String) -> String {
        MarkdownBlock.parse(text).map { block in
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text):
                String(inline(text).characters)
            case .list(let items):
                items.map { String(inline($0.text).characters) }.joined(separator: ". ")
            case .code(let code): code
            case .table(let rows):
                rows.map { $0.map { String(inline($0).characters) }.filter { !$0.isEmpty }.joined(separator: ", ") }
                    .joined(separator: ". ")
            case .rule: ""
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }
}

/// One block of a Markdown reply.
enum MarkdownBlock {
    struct Item {
        var marker: String
        var text: String
        var depth: Int
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case list([Item])
    case code(String)
    case quote(String)
    /// Rows of cells; the first row is the header.
    case table([[String]])
    case rule

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [Item] = []
        var code: [String]?
        var table: [[String]] = []

        func flush() {
            if !table.isEmpty {
                blocks.append(.table(table))
                table = []
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
            if !items.isEmpty {
                blocks.append(.list(items))
                items = []
            }
        }

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty || !items.isEmpty { flush() }
                let cells = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // The |---|---| line under the header only separates.
                let isSeparator = cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }
                if !isSeparator { table.append(cells) }
                continue
            }
            if !table.isEmpty { flush() }
            if trimmed == "---" || trimmed == "***" {
                flush()
                blocks.append(.rule)
                continue
            }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") {
                flush()
                blocks.append(.heading(level: hashes, text: String(trimmed.dropFirst(hashes + 1))))
                continue
            }
            if trimmed.hasPrefix("> ") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
                continue
            }
            let depth = line.prefix { $0 == " " }.count / 2
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !paragraph.isEmpty { flush() }
                items.append(Item(marker: "•", text: String(trimmed.dropFirst(2)), depth: depth))
                continue
            }
            let digits = trimmed.prefix { $0.isNumber }
            if !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") {
                if !paragraph.isEmpty { flush() }
                items.append(Item(
                    marker: "\(digits).", text: String(trimmed.dropFirst(digits.count + 2)), depth: depth
                ))
                continue
            }
            if !items.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

/// Marks every match of Find in chat's query in a run of text.
enum FindHighlight {
    static func mark(_ text: AttributedString, query: String) -> AttributedString {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return text }
        var result = text
        var start = result.startIndex
        while start < result.endIndex,
              let range = result[start...].range(of: needle, options: .caseInsensitive) {
            result[range].backgroundColor = Color.yellow.opacity(0.85)
            result[range].foregroundColor = .black
            start = range.upperBound
        }
        return result
    }
}
