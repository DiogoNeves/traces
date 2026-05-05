//
//  IndexManager.swift
//  Traces
//
//  Created by Diogo Neves on 05/05/2026.
//

import Foundation
import Photos

actor IndexManager {
    private let store: IndexStore
    private var isIndexing = false

    init(store: IndexStore) {
        self.store = store
    }

    func indexPhotos(_ inputs: [PhotoIndexInput]) throws -> IndexingResult {
        guard !isIndexing else {
            throw IndexingError.alreadyIndexing
        }
        
        isIndexing = true
        defer { isIndexing = false }
        
        let idsNeedingIndex = try store.photoIDsNeedingIndex(inputs)

        var indexedCount = 0

        for input in inputs where idsNeedingIndex.contains(input.id) {
            try store.upsert(input)
            indexedCount += 1
        }
        
        let currentIDs = Set(inputs.map(\.id))
        let prunedCount = try store.pruneIndexedPhotos(keepingIDs: currentIDs)

        return IndexingResult(indexedCount: indexedCount, prunedCount: prunedCount)
    }

    func indexedPhotoCount() throws -> Int {
        try store.indexedPhotoCount()
    }
    
    func wipeIndex() throws {
        guard !isIndexing else {
            throw IndexingError.alreadyIndexing
        }

        try store.wipeIndex()
    }
}
