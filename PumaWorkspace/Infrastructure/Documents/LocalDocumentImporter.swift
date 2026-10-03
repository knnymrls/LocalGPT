import Foundation
import PDFKit
import Vision
import ImageIO

actor LocalDocumentImporter: DocumentImporter {
    private let files: WorkspaceFiles
    private let database: WorkspaceDatabase
    private let repository: any AttachmentRepository
    private static let processorVersion = "text-v1"

    init(files: WorkspaceFiles, database: WorkspaceDatabase, repository: any AttachmentRepository) {
        self.files = files; self.database = database; self.repository = repository
    }

    func prepare(_ attachment: Attachment) async throws -> Attachment {
        guard let original = attachment.fileURL else { throw WorkspaceError.message("The file could not be read. Please select it again.") }
        try Task.checkCancellation()
        var item = attachment
        let (url, fingerprint) = try files.persistCopy(of: original, id: item.id, name: item.name)
        item.fileURL = url
        item.fingerprint = fingerprint
        try await repository.save(item)
        ImportStaging.removeIfStaged(original)
        try Task.checkCancellation()
        let key = fingerprint + "-" + Self.processorVersion
        let passages: [SourcePassage]
        if let cached = try await database.cachedExtraction(key) {
            passages = cached.map { SourcePassage(sourceID: item.id, locator: $0.locator, text: $0.text) }
        } else {
            do { passages = try extract(url: url, kind: item.kind, sourceID: item.id) }
            catch {
                item.readiness = .failed
                item.failureReason = error.localizedDescription
                try await repository.save(item)
                throw error
            }
        }
        try Task.checkCancellation()
        guard !passages.isEmpty else {
            item.readiness = .failed
            item.failureReason = "No readable text was found. This runtime reads images through OCR; general image understanding requires the newer vision model."
            try await repository.save(item)
            throw WorkspaceError.message(item.failureReason!)
        }
        try await database.index(passages, sourceID: item.id, fingerprint: key)
        try Task.checkCancellation()
        item.previewText = String(passages.map(\.text).joined(separator: "\n").prefix(12_000))
        item.readiness = .ready
        item.failureReason = nil
        try await repository.save(item)
        return item
    }

    func remove(_ id: UUID) async throws {
        try await repository.delete(id: id)
        try files.remove(id: id)
    }

    private func extract(url: URL, kind: Attachment.Kind, sourceID: UUID) throws -> [SourcePassage] {
        var sections: [(String,String)] = []
        switch kind {
        case .pdf:
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw WorkspaceError.message("This PDF is locked or unreadable.") }
            guard pdf.pageCount <= 300 else { throw WorkspaceError.message("Choose a PDF with at most 300 pages.") }
            for n in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let page = pdf.page(at: n) else { continue }
                var text = page.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let image = page.thumbnail(of: CGSize(width: 1600,height: 2000), for: .mediaBox).cgImage {
                    text = try recognize(image)
                }
                sections.append(("Page \(n+1)",text))
            }
        case .image:
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL,nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(imageSource,0,[
                    kCGImageSourceCreateThumbnailFromImageAlways:true,
                    kCGImageSourceThumbnailMaxPixelSize:2000,
                    kCGImageSourceCreateThumbnailWithTransform:true
                  ] as CFDictionary) else { throw WorkspaceError.message("This image cannot be opened.") }
            sections = [("Image text",try recognize(image))]
        case .text, .markdown, .code, .spreadsheet:
            let ext = url.pathExtension.lowercased()
            guard !["xlsx","xls","numbers","ods"].contains(ext) else {
                throw WorkspaceError.message("Export this spreadsheet as CSV to let the assistant read it.")
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) else {
                throw WorkspaceError.message("This file is not readable text.")
            }
            sections = [("Text",text)]
        default:
            throw WorkspaceError.message("This format can be previewed, but is not supported for analysis yet. Use PDF, text, CSV, or an image.")
        }
        return sections.flatMap { locator,text in
            Self.chunks(text).enumerated().map { index,chunk in
                SourcePassage(sourceID:sourceID,locator:"\(locator) · passage \(index+1)",text:chunk)
            }
        }
    }

    private func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage:image).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n") ?? ""
    }

    static func chunks(_ text: String, size: Int = 1400) -> [String] {
        let text = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start,offsetBy:size,limitedBy:text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            if end == text.endIndex { break }
            start = text.index(end,offsetBy:-min(160,size/4))
        }
        return result
    }
}
