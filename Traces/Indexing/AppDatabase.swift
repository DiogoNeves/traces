//
//  AppDatabase.swift
//  Traces
//
//  Created by Diogo Neves on 01/05/2026.
//

import Foundation
import GRDB

nonisolated struct AppDatabase {
    let dbQueue: DatabaseQueue
    
    var indexStore: IndexStore {
        IndexStore(dbQueue: dbQueue)
    }

    init() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directoryURL = appSupportURL.appendingPathComponent(
            "Traces",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let databaseURL = directoryURL.appendingPathComponent("Traces.sqlite")
        dbQueue = try DatabaseQueue(path: databaseURL.path)

        try Self.migrator.migrate(dbQueue)
    }

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createIndexedPhoto") { db in
            try db.create(table: "indexed_photo") { table in
                table.column("id", .text).primaryKey()
                table.column("creation_date", .double)
                table.column("modification_date", .double)
                table.column("media_subtypes", .integer).notNull()
                table.column("pixel_width", .integer).notNull()
                table.column("pixel_height", .integer).notNull()
                table.column("fingerprint", .text).notNull()
                table.column("index_version", .integer).notNull()
                table.column("indexed_at", .double).notNull()
            }
        }
        
        migrator.registerMigration("addMemoryRetrievalFields") { db in
            try db.alter(table: "indexed_photo") { table in
                table.add(column: "asset_kind", .text).notNull().defaults(to: "photo")
                table.add(column: "latitude", .double)
                table.add(column: "longitude", .double)
                table.add(column: "lat_bucket", .integer)
                table.add(column: "lon_bucket", .integer)
            }

            try db.create(
                index: "idx_indexed_photo_location_bucket",
                on: "indexed_photo",
                columns: ["lat_bucket", "lon_bucket"]
            )

            try db.create(
                index: "idx_indexed_photo_asset_kind",
                on: "indexed_photo",
                columns: ["asset_kind"]
            )
        }

        migrator.registerMigration("createIndexMetadata") { db in
            try db.create(table: "index_metadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .blob).notNull()
            }
        }

        migrator.registerMigration("addFavoriteToIndexedPhoto") { db in
            try db.alter(table: "indexed_photo") { table in
                table.add(column: "is_favorite", .boolean)
                    .notNull()
                    .defaults(to: false)
            }

            try db.create(
                index: "idx_indexed_photo_favorite",
                on: "indexed_photo",
                columns: ["is_favorite"]
            )
        }

        return migrator
    }
}
