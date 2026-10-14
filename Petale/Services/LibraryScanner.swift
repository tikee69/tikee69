import Photos

/// Lit la photothèque (sans les images elles-mêmes, seulement leurs informations).
enum LibraryScanner {
    static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func fetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        options.includeHiddenAssets = false
        return options
    }

    /// Liste toutes les photos et vidéos. Les analyses déjà faites sont conservées.
    static func scan(existing: [String: PhotoInfo]) -> [PhotoInfo] {
        let options = fetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)

        var photos: [PhotoInfo] = []
        photos.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            let old = existing[id]
            let isPick = asset.representsBurst
                || asset.burstSelectionTypes.contains(.userPick)
                || asset.burstSelectionTypes.contains(.autoPick)
            var size = old?.fileSize ?? 0
            if size <= 0 { size = fileSize(of: asset) }

            photos.append(PhotoInfo(
                id: id,
                creationDate: asset.creationDate,
                isVideo: asset.mediaType == .video,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isFavorite: asset.isFavorite,
                burstID: asset.burstIdentifier,
                isBurstPick: isPick,
                fileSize: size,
                duration: asset.duration,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                analysis: old?.analysis
            ))
        }
        return photos
    }

    /// Taille réelle du fichier (photo + éventuelle vidéo Live Photo).
    static func fileSize(of asset: PHAsset) -> Int64 {
        var total: Int64 = 0
        let key = "fileSize"
        for resource in PHAssetResource.assetResources(for: asset) {
            // Propriété non documentée mais stable : on vérifie qu'elle existe avant de la lire.
            guard resource.responds(to: NSSelectorFromString(key)) else { continue }
            if let number = resource.value(forKey: key) as? NSNumber {
                total += number.int64Value
            }
        }
        if total > 0 { return total }
        // Estimation si la taille est inconnue
        if asset.mediaType == .video {
            return Int64(max(asset.duration, 1) * 1_500_000)
        }
        return Int64(Double(asset.pixelWidth * asset.pixelHeight) * 0.35)
    }
}
