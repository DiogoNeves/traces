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

    init(store: IndexStore) {
        self.store = store
    }

    func indexPhotos(_ assets: [PHAsset]) throws -> Int {
        var indexedCount = 0

        for asset in assets {
            let input = PhotoIndexInput(asset: asset)
            try store.upsert(input)
            indexedCount += 1
        }

        return indexedCount
    }

    func indexedPhotoCount() throws -> Int {
        try store.indexedPhotoCount()
    }
}
