import SwiftUI

extension Attachment.Kind {
    /// Three page glyphs cover every file: Page for PDFs, Report for
    /// spreadsheets, Page 2 for documents, text, Markdown, and the rest.
    var icon: NucleoIcon {
        switch self {
        case .image: .fileImage
        case .pdf: .filePDF
        case .spreadsheet: .fileSpreadsheet
        default: .fileDocument
        }
    }

    /// The type's colour: red PDFs, blue documents, green spreadsheets.
    /// Markdown and everything else stay in the foreground ink.
    var tint: Color {
        switch self {
        case .pdf: Tokens.filePDF
        case .document: Tokens.fileDocument
        case .spreadsheet: Tokens.fileSpreadsheet
        default: Tokens.foreground
        }
    }

    /// The tag shown when a file's name has no extension.
    var shortName: String {
        switch self {
        case .image: "IMG"
        case .pdf: "PDF"
        case .document: "DOC"
        case .spreadsheet: "CSV"
        case .markdown: "MD"
        case .text: "TXT"
        default: "FILE"
        }
    }

    var displayName: String {
        switch self {
        case .image: "Photo"
        case .pdf: "PDF"
        case .document: "Document"
        case .spreadsheet: "Spreadsheet"
        case .markdown: "Markdown"
        case .text: "Text"
        case .code: "Code"
        case .presentation: "Presentation"
        case .archive: "Archive"
        case .audio: "Audio"
        case .video: "Video"
        case .other: "File"
        }
    }
}
