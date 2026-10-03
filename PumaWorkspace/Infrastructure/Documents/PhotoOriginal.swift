@preconcurrency import Photos
import Foundation

enum PhotoOriginal {
    static func load(id: String) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw WorkspaceError.message("This photo is no longer available.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: WorkspaceError.message("This photo is not stored on the device. Download it in Photos first, then add it again.")) }
            }
        }
    }
}
