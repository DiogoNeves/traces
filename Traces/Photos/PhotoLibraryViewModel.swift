import Combine
import Foundation
import Photos

@MainActor
final class PhotoLibraryViewModel: NSObject, ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assetCount = 0
    @Published private(set) var libraryVersion = 0

    let indexManager: IndexManager

    private let photoLibraryService: PhotoLibraryService
    private var fetchResult: PHFetchResult<PHAsset>?
    private var hasRegisteredChangeObserver = false
    private var hasStartedInitialIndex = false
    private var indexingTask: Task<Void, Never>?

    init(
        indexManager: IndexManager,
        photoLibraryService: PhotoLibraryService
    ) {
        self.indexManager = indexManager
        self.photoLibraryService = photoLibraryService
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    deinit {
        if hasRegisteredChangeObserver {
            photoLibraryService.unregister(self)
        }
    }

    func loadIfAlreadyAuthorised() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        guard hasPhotoAccess else {
            return
        }

        loadLibraryIfNeeded()
        startInitialIndexIfNeeded()
    }

    func requestAccessAndLoad() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.authorizationStatus = status

                guard self.hasPhotoAccess else {
                    return
                }

                self.loadLibraryIfNeeded()
                self.startInitialIndexIfNeeded()
            }
        }
    }

    func asset(at index: Int) -> PHAsset? {
        guard let fetchResult,
              index >= 0,
              index < fetchResult.count else {
            return nil
        }

        return fetchResult.object(at: index)
    }

    func asset(withLocalIdentifier id: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    private var hasPhotoAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    private func loadLibraryIfNeeded() {
        guard fetchResult == nil else {
            return
        }

        setFetchResult(photoLibraryService.fetchImageAssets())
        registerForPhotoLibraryChangesIfNeeded()
    }

    private func registerForPhotoLibraryChangesIfNeeded() {
        guard !hasRegisteredChangeObserver else {
            return
        }

        photoLibraryService.register(self)
        hasRegisteredChangeObserver = true
    }

    private func setFetchResult(_ fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
        assetCount = fetchResult.count
        libraryVersion += 1
    }

    private func startInitialIndexIfNeeded() {
        guard !hasStartedInitialIndex,
              let fetchResult else {
            return
        }

        hasStartedInitialIndex = true
        indexingTask = Task { [indexManager, photoLibraryService] in
            do {
                let needsFullReconciliation = try await indexManager
                    .requiresFullReconciliation(
                        expectedAssetCount: fetchResult.count
                    )

                if !needsFullReconciliation,
                   let token = try await indexManager.photoLibraryChangeToken() {
                    do {
                        let changes = try photoLibraryService.persistentChanges(
                            since: token
                        )

                        if changes.hasChanges {
                            let changedAssets = photoLibraryService
                                .fetchAssets(
                                    withLocalIdentifiers: Array(changes.changedAssetIDs)
                                )
                            let result = try await indexManager
                                .indexChangedPhotoFetchResult(
                                    changedAssets,
                                    deletedIDs: changes.deletedAssetIDs
                                )
                            let total = try await indexManager.indexedPhotoCount()

                            try await indexManager.savePhotoLibraryChangeToken(
                                changes.latestChangeToken
                            )

                            print(
                                "Indexed \(result.indexedCount) changed photos. " +
                                "Pruned \(result.prunedCount). " +
                                "Total indexed rows: \(total)"
                            )
                            return
                        }

                        try await indexManager.savePhotoLibraryChangeToken(
                            photoLibraryService.currentChangeToken
                        )
                        print("Photo index is current; no library changes found.")
                        return
                    } catch {
                        print(
                            "Persistent PhotoKit changes unavailable; " +
                            "falling back to full index: \(error)"
                        )
                    }
                }

                let reconciliationToken = photoLibraryService.currentChangeToken
                let result = try await indexManager.reconcilePhotoFetchResult(
                    fetchResult
                )
                let total = try await indexManager.indexedPhotoCount()

                try await indexManager.savePhotoLibraryChangeToken(
                    reconciliationToken
                )

                print(
                    "Indexed \(result.indexedCount) photos. " +
                    "Pruned \(result.prunedCount). " +
                    "Total indexed rows: \(total)"
                )
            } catch {
                await MainActor.run {
                    self.hasStartedInitialIndex = false
                }

                print("Failed to index photos: \(error)")
            }
        }
    }

    private func indexLibraryChanges(
        changedAssetIDs: Set<String>,
        deletedAssetIDs: Set<String>
    ) {
        guard !changedAssetIDs.isEmpty || !deletedAssetIDs.isEmpty else {
            return
        }

        let changedAssets = photoLibraryService.fetchAssets(
            withLocalIdentifiers: Array(changedAssetIDs)
        )
        let currentChangeToken = photoLibraryService.currentChangeToken

        Task { [indexManager] in
            do {
                let result = try await indexManager.indexChangedPhotoFetchResult(
                    changedAssets,
                    deletedIDs: deletedAssetIDs
                )
                let total = try await indexManager.indexedPhotoCount()

                try await indexManager.savePhotoLibraryChangeToken(
                    currentChangeToken
                )

                print(
                    "Indexed \(result.indexedCount) live changes. " +
                    "Pruned \(result.prunedCount). " +
                    "Total indexed rows: \(total)"
                )
            } catch {
                print("Failed to index live photo changes: \(error)")
            }
        }
    }
}

extension PhotoLibraryViewModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.handlePhotoLibraryChange(changeInstance)
        }
    }

    private func handlePhotoLibraryChange(_ changeInstance: PHChange) {
        guard let fetchResult,
              let changes = changeInstance.changeDetails(for: fetchResult) else {
            return
        }

        setFetchResult(changes.fetchResultAfterChanges)

        guard changes.hasIncrementalChanges else {
            hasStartedInitialIndex = false
            startInitialIndexIfNeeded()
            return
        }

        let changedAssetIDs = Set(
            (changes.insertedObjects + changes.changedObjects)
                .map(\.localIdentifier)
        )
        let deletedAssetIDs = Set(
            changes.removedObjects.map(\.localIdentifier)
        )

        indexLibraryChanges(
            changedAssetIDs: changedAssetIDs,
            deletedAssetIDs: deletedAssetIDs
        )
    }
}
