import Foundation
import CryptoKit

struct WorkspaceFiles: Sendable {
    let root: URL
    static var applicationRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PumaWorkspace", isDirectory: true)
    }
    static let maximumImportBytes = 30 * 1024 * 1024

    func persistCopy(of source: URL, id: UUID, name: String) throws -> (URL, String) {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumImportBytes else { throw WorkspaceError.message("This file is too large. Choose one under 30 MB.") }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count <= Self.maximumImportBytes else { throw WorkspaceError.message("This file is too large.") }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined()
        return (try write(data, id: id, name: name), fingerprint)
    }

    func write(_ data: Data, id: UUID, name: String) throws -> URL {
        let url = fileURL(id: id, name: name)
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    func fileURL(id: UUID, name: String) -> URL {
        root.appendingPathComponent("Files/\(id.uuidString)", isDirectory: true)
            .appendingPathComponent(Self.safeName(name))
    }

    func remove(id: UUID) throws {
        let folder = root.appendingPathComponent("Files/\(id.uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    static func safeName(_ name: String) -> String {
        let leaf = (name as NSString).lastPathComponent
        let clean = leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "." || text == ".." ? "Untitled.txt" : String(text.prefix(140))
    }
}

enum WorkspaceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}
