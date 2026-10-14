import Photos

enum PhotoActionError: LocalizedError {
    case nothingFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .nothingFound: return "Ces photos n'existent plus dans votre photothèque."
        case .failed(let message): return message
        }
    }
}

/// Actions qui modifient la photothèque. iPhone demande toujours votre confirmation.
enum PhotoActions {
    private static func assets(_ ids: [String]) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: LibraryScanner.fetchOptions())
    }

    /// Supprime les photos (elles vont dans « Supprimés récemment » pendant 30 jours).
    /// Retourne les identifiants réellement supprimés, ou `nil` si vous avez annulé.
    static func delete(ids: [String]) async throws -> [String]? {
        guard !ids.isEmpty else { return [] }
        let found = assets(ids)
        guard found.count > 0 else { throw PhotoActionError.nothingFound }
        var foundIDs: [String] = []
        found.enumerateObjects { asset, _, _ in foundIDs.append(asset.localIdentifier) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(found)
            }
            return foundIDs
        } catch {
            if isUserCancellation(error) { return nil }
            throw PhotoActionError.failed("La suppression a échoué : \(error.localizedDescription)")
        }
    }

    static func createAlbum(title: String, ids: [String]) async throws {
        let found = assets(ids)
        guard found.count > 0 else { throw PhotoActionError.nothingFound }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                request.addAssets(found)
            }
        } catch {
            throw PhotoActionError.failed("Impossible de créer l'album : \(error.localizedDescription)")
        }
    }

    static func setFavorite(id: String, _ favorite: Bool) async throws {
        guard let asset = assets([id]).firstObject else { throw PhotoActionError.nothingFound }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = favorite
            }
        } catch {
            throw PhotoActionError.failed("Impossible de modifier le favori : \(error.localizedDescription)")
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == PHPhotosError.errorDomain, ns.code == PHPhotosError.userCancelled.rawValue { return true }
        // Sur certaines versions, l'annulation remonte comme une erreur Cocoa 3072.
        if ns.domain == NSCocoaErrorDomain, ns.code == 3072 { return true }
        return false
    }
}
