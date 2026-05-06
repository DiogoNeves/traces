//
//  PhotoIndexInput.swift
//  Traces
//
//  Created by Diogo Neves on 04/05/2026.
//

import Foundation
import Photos

enum IndexedAssetKind: String, Sendable {
    case photo
    case screenshot
}

struct PhotoIndexInput: Equatable, Sendable {
    nonisolated static let currentIndexVersion = 3
    nonisolated static let locationBucketSize = 0.001


    let id: String
    
    let creationDate: Date?
    let modificationDate: Date?
    let mediaSubtypesRawValue: UInt
    let assetKind: IndexedAssetKind
    
    let pixelWidth: Int
    let pixelHeight: Int
    
    let latitude: Double?
    let longitude: Double?
    let latBucket: Int?
    let lonBucket: Int?
    
    let fingerprint: String

    init(asset: PHAsset) {
        id = asset.localIdentifier
        
        creationDate = asset.creationDate
        modificationDate = asset.modificationDate
        mediaSubtypesRawValue = asset.mediaSubtypes.rawValue
        assetKind = asset.mediaSubtypes.contains(.photoScreenshot)
            ? .screenshot
            : .photo
        
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        
        let location = asset.location
        latitude = location?.coordinate.latitude
        longitude = location?.coordinate.longitude

        if let latitude, let longitude {
            latBucket = Self.bucket(for: latitude)
            lonBucket = Self.bucket(for: longitude)
        } else {
            latBucket = nil
            lonBucket = nil
        }

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
    
    static func bucket(for coordinate: Double) -> Int {
        // Quantizes a coordinate into a simple grid bucket. Longitude bucket
        // sizes vary by latitude, so exact distance filtering must happen later.
        Int(floor(coordinate / locationBucketSize))
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
