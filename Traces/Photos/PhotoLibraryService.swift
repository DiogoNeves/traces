import Foundation
import Photos

nonisolated struct PhotoLibraryPersistentChanges: Sendable {
    let changedAssetIDs: Set<String>
    let deletedAssetIDs: Set<String>
    let latestChangeToken: PHPersistentChangeToken

    var hasChanges: Bool {
        !changedAssetIDs.isEmpty || !deletedAssetIDs.isEmpty
    }
}

nonisolated final class PhotoLibraryService {
    private let photoLibrary: PHPhotoLibrary

    init(photoLibrary: PHPhotoLibrary = .shared()) {
        self.photoLibrary = photoLibrary
    }

    var currentChangeToken: PHPersistentChangeToken {
        photoLibrary.currentChangeToken
    }

    func register(_ observer: any PHPhotoLibraryChangeObserver) {
        photoLibrary.register(observer)
    }

    func unregister(_ observer: any PHPhotoLibraryChangeObserver) {
        photoLibrary.unregisterChangeObserver(observer)
    }

    func fetchImageAssets() -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: .image, options: makeImageFetchOptions())
    }

    func fetchAssets(withLocalIdentifiers ids: [String]) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    }

    func persistentChanges(
        since token: PHPersistentChangeToken
    ) throws -> PhotoLibraryPersistentChanges {
        let fetchResult = try photoLibrary.fetchPersistentChanges(since: token)
        var changedAssetIDs = Set<String>()
        var deletedAssetIDs = Set<String>()
        var latestChangeToken = token

        for change in fetchResult {
            latestChangeToken = change.changeToken

            let details = try change.changeDetails(for: .asset)

            changedAssetIDs.formUnion(details.insertedLocalIdentifiers)
            changedAssetIDs.formUnion(details.updatedLocalIdentifiers)
            deletedAssetIDs.formUnion(details.deletedLocalIdentifiers)
        }

        changedAssetIDs.subtract(deletedAssetIDs)

        return PhotoLibraryPersistentChanges(
            changedAssetIDs: changedAssetIDs,
            deletedAssetIDs: deletedAssetIDs,
            latestChangeToken: latestChangeToken
        )
    }

    func makeImageFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true)
        ]
        options.wantsIncrementalChangeDetails = true
        return options
    }
}
