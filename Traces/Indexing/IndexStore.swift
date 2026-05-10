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
        try upsert([input], indexedAt: indexedAt)
    }

    func upsert(_ inputs: [PhotoIndexInput], indexedAt: Date = Date()) throws {
        guard !inputs.isEmpty else {
            return
        }

        try dbQueue.write { db in
            for input in inputs {
                try Self.upsert(input, indexedAt: indexedAt, in: db)
            }
        }
    }

    func indexedPhotoCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM indexed_photo") ?? 0
        }
    }

    func hasIndexVersionMismatch(currentVersion: Int) throws -> Bool {
        try dbQueue.read { db in
            let count = try Int.fetchOne(
                db,
                sql: """
                SELECT EXISTS (
                    SELECT 1
                    FROM indexed_photo
                    WHERE index_version != ?
                    LIMIT 1
                )
                """,
                arguments: [currentVersion]
            ) ?? 0

            return count > 0
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

            try db.execute(
                sql: """
                CREATE TEMP TABLE IF NOT EXISTS current_index_asset (
                    id TEXT PRIMARY KEY
                )
                """
            )
            try db.execute(sql: "DELETE FROM current_index_asset")

            for id in ids {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO current_index_asset (id) VALUES (?)",
                    arguments: [id]
                )
            }

            try db.execute(sql: """
            DELETE FROM indexed_photo
            WHERE NOT EXISTS (
                SELECT 1
                FROM current_index_asset
                WHERE current_index_asset.id = indexed_photo.id
            )
            """)

            return db.changesCount
        }
    }

    func deleteIndexedPhotos(withIDs ids: Set<String>) throws -> Int {
        guard !ids.isEmpty else {
            return 0
        }

        return try dbQueue.write { db in
            var deletedCount = 0
            let idsArray = Array(ids)

            for startIndex in stride(from: 0, to: idsArray.count, by: 500) {
                let endIndex = min(startIndex + 500, idsArray.count)
                let batch = Array(idsArray[startIndex..<endIndex])

                try db.execute(literal: """
                DELETE FROM indexed_photo
                WHERE id IN \(batch)
                """)
                deletedCount += db.changesCount
            }

            return deletedCount
        }
    }
    
    func wipeIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM indexed_photo")
        }
    }

    func metadataData(forKey key: String) throws -> Data? {
        try dbQueue.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value FROM index_metadata WHERE key = ?",
                arguments: [key]
            )
        }
    }

    func setMetadataData(_ data: Data, forKey key: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO index_metadata (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [key, data]
            )
        }
    }

    func removeMetadataData(forKey key: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM index_metadata WHERE key = ?",
                arguments: [key]
            )
        }
    }

    private static func upsert(
        _ input: PhotoIndexInput,
        indexedAt: Date,
        in db: Database
    ) throws {
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
