import Foundation

struct Attachment: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case image, pdf, document, spreadsheet, markdown, text, code, presentation, archive, audio, video, other

        /// The kind a file name's extension implies; `other` when it is unknown.
        init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp": self = .image
            case "pdf": self = .pdf
            case "doc", "docx", "rtf", "odt", "pages": self = .document
            case "csv", "tsv", "xls", "xlsx", "ods", "numbers": self = .spreadsheet
            case "md", "mdx", "markdown": self = .markdown
            case "txt", "log": self = .text
            case "json", "js", "ts", "jsx", "tsx", "html", "css", "xml", "py", "rb", "go", "rs", "java",
                 "c", "cpp", "h", "swift", "kt", "sh", "sql", "yaml", "yml", "toml":
                self = .code
            case "ppt", "pptx", "odp", "key": self = .presentation
            case "zip", "rar", "7z", "tar", "gz", "bz2", "xz": self = .archive
            case "mp3", "wav", "aac", "flac", "ogg", "m4a": self = .audio
            case "mp4", "mov", "avi", "mkv", "webm": self = .video
            default: self = .other
            }
        }
    }
    enum Readiness: Sendable { case ready, importing, failed, removed }

    let id: UUID
    var name: String
    var kind: Kind
    var readiness: Readiness
    /// Extracted text shown in the preview page and used for evidence passages.
    var previewText: String
    /// A small encoded image for a photo's card; nil for files and fixtures.
    var thumbnail: Data?
    /// The app's own copy of an imported file, for viewing it.
    var fileURL: URL?

    init(
        id: UUID = UUID(), name: String, kind: Kind, readiness: Readiness,
        previewText: String = "", thumbnail: Data? = nil, fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.readiness = readiness
        self.previewText = previewText
        self.thumbnail = thumbnail
        self.fileURL = fileURL
    }
}
