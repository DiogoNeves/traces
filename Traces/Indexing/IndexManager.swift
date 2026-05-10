//
//  IndexManager.swift
//  Traces
//
//  Created by Diogo Neves on 05/05/2026.
//

import Foundation
import Photos

actor IndexManager {
    private static let photoLibraryChangeTokenKey = "photoLibraryChangeToken"

    private let store: IndexStore
    private var isIndexing = false

    init(store: IndexStore) {
        self.store = store
    }

    func indexPhotos(_ inputs: [PhotoIndexInput]) throws -> IndexingResult {
        try beginIndexing()
        defer { finishIndexing() }

        let indexedCount = try indexBatches(inputs)
        let currentIDs = Set(inputs.map(\.id))
        let prunedCount = try store.pruneIndexedPhotos(keepingIDs: currentIDs)

        return IndexingResult(indexedCount: indexedCount, prunedCount: prunedCount)
    }

    func reconcilePhotoFetchResult(
        _ fetchResult: PHFetchResult<PHAsset>,
        batchSize: Int = 500
    ) throws -> IndexingResult {
        try beginIndexing()
        defer { finishIndexing() }

        let batchLimit = max(batchSize, 1)
        var batch: [PhotoIndexInput] = []
        batch.reserveCapacity(batchLimit)

        var currentIDs = Set<String>()
        currentIDs.reserveCapacity(fetchResult.count)

        var indexedCount = 0

        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)

            guard asset.mediaType == .image else {
                continue
            }

            let input = PhotoIndexInput(asset: asset)
            currentIDs.insert(input.id)
            batch.append(input)

            if batch.count == batchLimit {
                indexedCount += try indexBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        indexedCount += try indexBatch(batch)
        let prunedCount = try store.pruneIndexedPhotos(keepingIDs: currentIDs)

        return IndexingResult(indexedCount: indexedCount, prunedCount: prunedCount)
    }

    func indexChangedPhotoFetchResult(
        _ fetchResult: PHFetchResult<PHAsset>,
        deletedIDs: Set<String>,
        batchSize: Int = 500
    ) throws -> IndexingResult {
        try beginIndexing()
        defer { finishIndexing() }

        let batchLimit = max(batchSize, 1)
        var batch: [PhotoIndexInput] = []
        batch.reserveCapacity(batchLimit)

        var indexedCount = 0

        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)

            guard asset.mediaType == .image else {
                continue
            }

            batch.append(PhotoIndexInput(asset: asset))

            if batch.count == batchLimit {
                indexedCount += try indexBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        indexedCount += try indexBatch(batch)
        let prunedCount = try store.deleteIndexedPhotos(withIDs: deletedIDs)

        return IndexingResult(indexedCount: indexedCount, prunedCount: prunedCount)
    }

    func indexedPhotoCount() throws -> Int {
        try store.indexedPhotoCount()
    }

    func requiresFullReconciliation(expectedAssetCount: Int) throws -> Bool {
        let indexedPhotoCount = try store.indexedPhotoCount()

        if indexedPhotoCount != expectedAssetCount {
            return true
        }

        return try store.hasIndexVersionMismatch(
            currentVersion: PhotoIndexInput.currentIndexVersion
        )
    }

    func photoLibraryChangeToken() throws -> PHPersistentChangeToken? {
        guard let data = try store.metadataData(
            forKey: Self.photoLibraryChangeTokenKey
        ) else {
            return nil
        }

        return try NSKeyedUnarchiver.unarchivedObject(
            ofClass: PHPersistentChangeToken.self,
            from: data
        )
    }

    func savePhotoLibraryChangeToken(_ token: PHPersistentChangeToken) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )

        try store.setMetadataData(data, forKey: Self.photoLibraryChangeTokenKey)
    }
    
    func relatedPhotos(for input: PhotoIndexInput, limit: Int = 20) throws -> [RelatedPhotoCandidate]
    {
        let candidates = try store.sameLocationCandidates(for: input)

        let selectedDate = input.creationDate

        let ranked = candidates.sorted { lhs, rhs in
            switch (selectedDate, lhs.creationDate, rhs.creationDate) {
            case let (selected?, lhsDate?, rhsDate?):
                let lhsIsOlder = lhsDate < selected
                let rhsIsOlder = rhsDate < selected

                if lhsIsOlder != rhsIsOlder {
                    return lhsIsOlder
                }

                let lhsDistance = abs(lhsDate.timeIntervalSince(selected))
                let rhsDistance = abs(rhsDate.timeIntervalSince(selected))

                return lhsDistance < rhsDistance

            default:
                return lhs.id < rhs.id
            }
        }

        return Array(ranked.prefix(limit))
    }
    
    func wipeIndex() throws {
        guard !isIndexing else {
            throw IndexingError.alreadyIndexing
        }

        try store.wipeIndex()
        try store.removeMetadataData(forKey: Self.photoLibraryChangeTokenKey)
    }

    private func beginIndexing() throws {
        guard !isIndexing else {
            throw IndexingError.alreadyIndexing
        }

        isIndexing = true
    }

    private func finishIndexing() {
        isIndexing = false
    }

    private func indexBatches(
        _ inputs: [PhotoIndexInput],
        batchSize: Int = 500
    ) throws -> Int {
        let batchLimit = max(batchSize, 1)
        var indexedCount = 0

        for startIndex in stride(from: 0, to: inputs.count, by: batchLimit) {
            let endIndex = min(startIndex + batchLimit, inputs.count)
            let batch = Array(inputs[startIndex..<endIndex])
            indexedCount += try indexBatch(batch)
        }

        return indexedCount
    }

    private func indexBatch(_ inputs: [PhotoIndexInput]) throws -> Int {
        guard !inputs.isEmpty else {
            return 0
        }

        let idsNeedingIndex = try store.photoIDsNeedingIndex(inputs)
        let inputsNeedingIndex = inputs.filter {
            idsNeedingIndex.contains($0.id)
        }

        try store.upsert(inputsNeedingIndex)

        return inputsNeedingIndex.count
    }
}
