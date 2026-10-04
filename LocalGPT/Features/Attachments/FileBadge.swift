import SwiftUI

/// A file's type glyph in its colour: red PDF, blue document, green
/// spreadsheet, foreground ink for the rest. One size everywhere a file is
/// named, so the composer, replies, and sheets agree.
struct FileBadge: View {
    let file: Attachment

    var body: some View {
        Icon(file.kind.icon, size: 20, color: file.kind.tint)
    }
}

/// One file as a row: its type tag, its name, and an arrow.
struct FileRowLabel: View {
    let file: Attachment

    var body: some View {
        HStack(spacing: pt(12)) {
            FileBadge(file: file)
            Text(file.name)
                .font(.text)
                .foregroundStyle(Tokens.foreground)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: pt(8))
            Icon(.chevronRight, size: 16, color: Tokens.foregroundMuted)
        }
    }
}
