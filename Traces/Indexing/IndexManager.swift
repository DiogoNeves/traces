//
//  IndexManager.swift
//  Traces
//
//  Created by Diogo Neves on 05/05/2026.
//

import Foundation
import Photos

final class IndexManager {
    private let store: IndexStore
    private var isIndexing = false

    init(store: IndexStore) {
        self.store = store
    }

    func indexPhotos(_ inputs: [PhotoIndexInput]) throws -> Int {
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

        return indexedCount
    }

    func indexedPhotoCount() throws -> Int {
        try store.indexedPhotoCount()
    }
}
