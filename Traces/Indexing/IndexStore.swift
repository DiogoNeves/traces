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
                    pixel_width,
                    pixel_height,
                    media_subtypes,
                    fingerprint,
                    index_version,
                    indexed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    creation_date = excluded.creation_date,
                    modification_date = excluded.modification_date,
                    pixel_width = excluded.pixel_width,
                    pixel_height = excluded.pixel_height,
                    media_subtypes = excluded.media_subtypes,
                    fingerprint = excluded.fingerprint,
                    index_version = excluded.index_version,
                    indexed_at = excluded.indexed_at
                """,
                arguments: [
                    input.id,
                    input.creationDate?.timeIntervalSince1970,
                    input.modificationDate?.timeIntervalSince1970,
                    input.pixelWidth,
                    input.pixelHeight,
                    input.mediaSubtypesRawValue,
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
    
    func wipeIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM indexed_photo")
        }
    }
}
