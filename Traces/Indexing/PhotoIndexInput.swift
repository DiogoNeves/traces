//
//  PhotoIndexInput.swift
//  Traces
//
//  Created by Diogo Neves on 04/05/2026.
//

import Foundation
import Photos

struct PhotoIndexInput: Equatable {
    static let currentIndexVersion = 2

    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let mediaSubtypesRawValue: UInt
    let fingerprint: String

    init(asset: PHAsset) {
        id = asset.localIdentifier
        creationDate = asset.creationDate
        modificationDate = asset.modificationDate
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        mediaSubtypesRawValue = asset.mediaSubtypes.rawValue

        // Used to detect whether the indexed metadata snapshot is stale.
        fingerprint = Self.makeFingerprint(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            mediaSubtypesRawValue: asset.mediaSubtypes.rawValue
        )
    }

    static func makeFingerprint(
        id: String,
        creationDate: Date?,
        modificationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        mediaSubtypesRawValue: UInt
    ) -> String {
        // TODO: Replace with a compact stable hash if fingerprints become large.
        [
            id,
            creationDate.map { String($0.timeIntervalSince1970) } ?? "nil",
            modificationDate.map { String($0.timeIntervalSince1970) } ?? "nil",
            String(pixelWidth),
            String(pixelHeight),
            String(mediaSubtypesRawValue)
        ].joined(separator: "|")
    }
}
