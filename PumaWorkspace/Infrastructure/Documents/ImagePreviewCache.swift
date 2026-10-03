import Foundation

/// Decode bounded feed previews away from the UI actor. Encoded previews have
/// an independent memory budget; full-size files remain on disk for Quick Look.
actor ImagePreviewCache {
    static let shared = ImagePreviewCache()
    private let cache = NSCache<NSString, NSData>()

    init() {
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func preview(url: URL, fingerprint: String?) -> Data? {
        let key = (url.absoluteString + "|" + (fingerprint ?? "")) as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        guard let data = ImageThumbnail.make(from: url, maximumPixelSize: 1200) else { return nil }
        cache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
}
