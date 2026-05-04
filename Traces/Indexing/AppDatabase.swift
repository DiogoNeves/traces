//
//  AppDatabase.swift
//  Traces
//
//  Created by Diogo Neves on 01/05/2026.
//

import Foundation
import GRDB

struct AppDatabase {
    let dbQueue: DatabaseQueue

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

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createIndexedPhoto") { db in
            try db.create(table: "indexed_photo") { table in
                table.column("id", .text).primaryKey()
                table.column("creation_date", .double)
                table.column("modification_date", .double)
                table.column("pixel_width", .integer).notNull()
                table.column("pixel_height", .integer).notNull()
                table.column("media_subtypes", .integer).notNull()
                table.column("fingerprint", .text).notNull()
                table.column("index_version", .integer).notNull()
                table.column("indexed_at", .double).notNull()
            }
        }

        return migrator
    }
}
