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

                return lhsDate < rhsDate

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
    }
}
