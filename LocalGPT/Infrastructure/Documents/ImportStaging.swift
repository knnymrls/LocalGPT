import Foundation

/// Security-scoped input is copied off the UI actor before the picker relinquishes it.
/// Staging is durable until the importer has committed its own copy.
enum ImportStaging {
    static var root: URL { WorkspaceFiles.applicationRoot.appendingPathComponent("Incoming", isDirectory: true) }
    static func copy(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= WorkspaceFiles.maximumImportBytes else { throw WorkspaceError.message("Choose a file under 30 MB.") }
        return try store(Data(contentsOf: url, options: .mappedIfSafe), named: url.lastPathComponent)
    }

    static func store(_ data: Data, named name: String) throws -> URL {
        guard data.count <= WorkspaceFiles.maximumImportBytes else { throw WorkspaceError.message("Choose a file under 30 MB.") }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(WorkspaceFiles.safeName(name))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    static func removeIfStaged(_ url: URL) {
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
