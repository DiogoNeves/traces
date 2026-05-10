//
//  RelatedPhotoCandidate.swift
//  Traces
//
//  Created by Diogo Neves on 07/05/2026.
//

import Foundation

nonisolated struct RelatedPhotoCandidate: Equatable, Sendable {
    let id: String
    let creationDate: Date?
    let latitude: Double?
    let longitude: Double?
    let assetKind: IndexedAssetKind
}
