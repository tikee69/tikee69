import Photos
import UIKit

/// Charge les vignettes et les images en grand pour l'affichage.
enum ImageLoader {
    static let manager = PHCachingImageManager()
    private static let assetCache = NSCache<NSString, PHAsset>()

    static func loadAsset(_ id: String) -> PHAsset? {
        if let cached = assetCache.object(forKey: id as NSString) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: LibraryScanner.fetchOptions()).firstObject
        else { return nil }
        assetCache.setObject(asset, forKey: id as NSString)
        return asset
    }

    /// Envoie d'abord une version rapide (floue), puis la version nette.
    static func images(for id: String, pixelSize: CGSize, contentMode: PHImageContentMode = .aspectFill) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = loadAsset(id) else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let requestID = manager.requestImage(
                for: asset, targetSize: pixelSize, contentMode: contentMode, options: options
            ) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded { continuation.finish() }
            }
            continuation.onTermination = { _ in
                manager.cancelImageRequest(requestID)
            }
        }
    }

    static func clearCache() {
        assetCache.removeAllObjects()
    }
}
