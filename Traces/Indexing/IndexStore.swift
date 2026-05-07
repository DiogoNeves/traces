//
//  IndexStore.swift
//  Traces
//
//  Created by Diogo Neves on 04/05/2026.
//

import Foundation
import GRDB

nonisolated struct IndexStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    func photoIDsNeedingIndex(_ inputs: [PhotoIndexInput]) throws -> Set<String> {
        guard !inputs.isEmpty else {
            return []
        }

        let ids = inputs.map(\.id)

        return try dbQueue.read { db in
            let request: SQLRequest<Row> = """
            SELECT id, fingerprint, index_version
            FROM indexed_photo
            WHERE id IN \(ids)
            """
            let rows = try request.fetchAll(db)

            var existingByID: [String: Row] = [:]
            for row in rows {
                existingByID[row["id"]] = row
            }

            var needingIndex = Set<String>()

            for input in inputs {
                guard let row = existingByID[input.id] else {
                    needingIndex.insert(input.id)
                    continue
                }

                let storedFingerprint: String = row["fingerprint"]
                let storedIndexVersion: Int = row["index_version"]

                if storedFingerprint != input.fingerprint ||
                    storedIndexVersion != PhotoIndexInput.currentIndexVersion {
                    needingIndex.insert(input.id)
                }
            }

            return needingIndex
        }
    }

    func upsert(_ input: PhotoIndexInput, indexedAt: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO indexed_photo (
                    id,
                    creation_date,
                    modification_date,
                    media_subtypes,
                    asset_kind,
                    pixel_width,
                    pixel_height,
                    latitude,
                    longitude,
                    lat_bucket,
                    lon_bucket,
                    fingerprint,
                    index_version,
                    indexed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    creation_date = excluded.creation_date,
                    modification_date = excluded.modification_date,
                    media_subtypes = excluded.media_subtypes,
                    asset_kind = excluded.asset_kind,
                    pixel_width = excluded.pixel_width,
                    pixel_height = excluded.pixel_height,
                    latitude = excluded.latitude,
                    longitude = excluded.longitude,
                    lat_bucket = excluded.lat_bucket,
                    lon_bucket = excluded.lon_bucket,
                    fingerprint = excluded.fingerprint,
                    index_version = excluded.index_version,
                    indexed_at = excluded.indexed_at
                """,
                arguments: [
                    input.id,
                    input.creationDate?.timeIntervalSince1970,
                    input.modificationDate?.timeIntervalSince1970,
                    input.mediaSubtypesRawValue,
                    input.assetKind.rawValue,
                    input.pixelWidth,
                    input.pixelHeight,
                    input.latitude,
                    input.longitude,
                    input.latBucket,
                    input.lonBucket,
                    input.fingerprint,
                    PhotoIndexInput.currentIndexVersion,
                    indexedAt.timeIntervalSince1970
                ]
            )
        }
    }

    func indexedPhotoCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM indexed_photo") ?? 0
        }
    }
    
    func sameLocationCandidates(
        for input: PhotoIndexInput,
        bucketRadius: Int = 1,
        limit: Int = 200
    ) throws -> [RelatedPhotoCandidate] {
        guard let latBucket = input.latBucket,
              let lonBucket = input.lonBucket else {
            return []
        }

        return try dbQueue.read { db in
            let minLatBucket = latBucket - bucketRadius
            let maxLatBucket = latBucket + bucketRadius
            let minLonBucket = lonBucket - bucketRadius
            let maxLonBucket = lonBucket + bucketRadius

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, creation_date, latitude, longitude, asset_kind
                FROM indexed_photo
                WHERE id != ?
                AND lat_bucket BETWEEN ? AND ?
                AND lon_bucket BETWEEN ? AND ?
                AND asset_kind = ?
                LIMIT ?
                """,
                arguments: [
                    input.id,
                    minLatBucket,
                    maxLatBucket,
                    minLonBucket,
                    maxLonBucket,
                    input.assetKind.rawValue,
                    limit
                ]
            )

            return rows.compactMap { row in
                let rawKind: String = row["asset_kind"]

                guard let assetKind = IndexedAssetKind(rawValue: rawKind) else {
                    return nil
                }

                let creationTimestamp: Double? = row["creation_date"]

                return RelatedPhotoCandidate(
                    id: row["id"],
                    creationDate: creationTimestamp.map(Date.init(timeIntervalSince1970:)),
                    latitude: row["latitude"],
                    longitude: row["longitude"],
                    assetKind: assetKind
                )
            }
        }
    }
    
    func pruneIndexedPhotos(keepingIDs ids: Set<String>) throws -> Int {
        try dbQueue.write { db in
            if ids.isEmpty {
                try db.execute(sql: "DELETE FROM indexed_photo")
                return db.changesCount
            }

            let idsArray = Array(ids)

            try db.execute(literal: """
            DELETE FROM indexed_photo
            WHERE id NOT IN \(idsArray)
            """)

            return db.changesCount
        }
    }
    
    func wipeIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM indexed_photo")
        }
    }
}
