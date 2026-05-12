//
//  RelatedPhotoSection.swift
//  Traces
//
//  Created by Diogo Neves on 12/05/2026.
//

import Foundation

nonisolated enum RelatedPhotoSectionKind: String, Sendable {
    case overTheYears
    case samePlaceEarlierYears
    case samePlace
    case similarPhotos
    case similarScreenshots
}

nonisolated struct RelatedPhotoSection: Equatable, Identifiable, Sendable {
    var id: RelatedPhotoSectionKind {
        kind
    }

    let kind: RelatedPhotoSectionKind
    let title: String
    let candidates: [RelatedPhotoCandidate]
}
