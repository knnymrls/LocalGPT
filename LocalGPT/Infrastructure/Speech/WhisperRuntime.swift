@preconcurrency import WhisperKit
import Foundation

/// Serial inference with a warm model and a persistent, app-owned asset cache.
/// Only public model assets are downloaded. Audio never enters the downloader.
actor WhisperRuntime {
    static let shared = WhisperRuntime()
    private var engine: WhisperEngine?
    private var loading: Task<WhisperEngine, Error>?
    private var previous: Task<String, Error>?

    func prepare() async throws {
        if engine != nil { return }
        if let loading { engine = try await loading.value; return }
        let task = Task { try await WhisperEngine.load() }
        loading = task
        do { engine = try await task.value; loading = nil }
        catch { loading = nil; throw error }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        try Task.checkCancellation()
        guard let engine else { throw WorkspaceError.message("The local speech model is not ready.") }
        let previous = previous
        let task = Task {
            if let previous { _ = try? await previous.value }
            try Task.checkCancellation()
            return try await engine.transcribe(samples)
        }
        self.previous = task
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

/// WhisperKit is an ObjC/Core ML wrapper. All inference is serialized by WhisperRuntime.
private final class WhisperEngine: @unchecked Sendable {
    let model: WhisperKit
    init(model: WhisperKit) { self.model = model }

    static func load() async throws -> WhisperEngine {
        let root = WorkspaceFiles.applicationRoot.appendingPathComponent("SpeechAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let location = root.appendingPathComponent("model-location.txt")
        let relative = try? String(contentsOf: location, encoding: .utf8)
        let existing = relative.map { root.appendingPathComponent($0) }
        let folder = existing.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil }
        let config = WhisperKitConfig(model: "openai_whisper-base", downloadBase: root,
                                      modelFolder: folder, tokenizerFolder: root, verbose: false,
                                      prewarm: false, load: true, download: folder == nil)
        let model = try await WhisperKit(config)
        if let modelFolder = model.modelFolder, modelFolder.path.hasPrefix(root.path + "/") {
            let relative = String(modelFolder.path.dropFirst(root.path.count + 1))
            try relative.write(to: location, atomically: true, encoding: .utf8)
        }
        return WhisperEngine(model: model)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let options = DecodingOptions(verbose: false, task: .transcribe,
                                      language: Locale.current.language.languageCode?.identifier,
                                      temperatureFallbackCount: 1, skipSpecialTokens: true,
                                      withoutTimestamps: true, concurrentWorkerCount: 1)
        let results = try await model.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
