//
//  IndexStore.swift
//  Traces
//
//  Created by Diogo Neves on 04/05/2026.
//

import Foundation
import GRDB

struct IndexStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func upsert(_ input: PhotoIndexModel, indexedAt: Date = Date()) throws {
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
                    PhotoIndexModel.currentIndexVersion,
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
}
