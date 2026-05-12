//
//  TracesTests.swift
//  TracesTests
//
//  Created by Diogo Neves on 28/04/2026.
//

import Testing
import Foundation
import GRDB
import Photos
@testable import Traces

struct TracesTests {

    @Test func indexingSkipsFreshRows() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)
        let inputs = [
            makeInput(id: "asset-1"),
            makeInput(id: "asset-2")
        ]

        let firstResult = try await manager.indexPhotos(inputs)
        let secondResult = try await manager.indexPhotos(inputs)

        #expect(firstResult.indexedCount == 2)
        #expect(firstResult.prunedCount == 0)
        #expect(secondResult.indexedCount == 0)
        #expect(secondResult.prunedCount == 0)
        #expect(try await manager.indexedPhotoCount() == 2)
    }

    @Test func staleFingerprintReindexesRow() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)

        let original = makeInput(id: "asset-1", pixelWidth: 100)
        let updated = makeInput(id: "asset-1", pixelWidth: 200)

        _ = try await manager.indexPhotos([original])
        let result = try await manager.indexPhotos([updated])

        #expect(result.indexedCount == 1)
        #expect(result.prunedCount == 0)
        #expect(try await manager.indexedPhotoCount() == 1)
    }

    @Test func fullIndexPrunesRowsOutsideCurrentLibrarySnapshot() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)

        _ = try await manager.indexPhotos([
            makeInput(id: "asset-1"),
            makeInput(id: "asset-2")
        ])
        let result = try await manager.indexPhotos([
            makeInput(id: "asset-1")
        ])

        #expect(result.indexedCount == 0)
        #expect(result.prunedCount == 1)
        #expect(try await manager.indexedPhotoCount() == 1)
    }

    @Test func incrementalIndexDeletesRemovedRowsWithoutFullPrune() async throws {
        let database = try makeDatabase()
        let store = database.indexStore

        try store.upsert([
            makeInput(id: "asset-1"),
            makeInput(id: "asset-2")
        ])

        let deletedCount = try store.deleteIndexedPhotos(withIDs: ["asset-2"])

        #expect(deletedCount == 1)
        #expect(try store.indexedPhotoCount() == 1)
    }

    @Test func fullReconciliationIsRequiredForMissingRowsOrOldVersions() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)

        #expect(try await manager.requiresFullReconciliation(expectedAssetCount: 1))

        _ = try await manager.indexPhotos([makeInput(id: "asset-1")])

        #expect(!(try await manager.requiresFullReconciliation(expectedAssetCount: 1)))

        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE indexed_photo SET index_version = ?",
                arguments: [-1]
            )
        }

        #expect(try await manager.requiresFullReconciliation(expectedAssetCount: 1))
    }

    @Test func relatedSectionsPreferEarlierYearsAndKeepScreenshotsSeparate() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)

        let selectedDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 10)
        ))
        let olderDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2024, month: 5, day: 10)
        ))
        let newerDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 11)
        ))

        let selected = makeInput(
            id: "selected",
            creationDate: selectedDate,
            assetKind: .photo,
            latitude: 51.5,
            longitude: -0.1
        )
        let olderPhoto = makeInput(
            id: "older-photo",
            creationDate: olderDate,
            assetKind: .photo,
            latitude: 51.5001,
            longitude: -0.1001
        )
        let newerPhoto = makeInput(
            id: "newer-photo",
            creationDate: newerDate,
            assetKind: .photo,
            latitude: 51.5002,
            longitude: -0.1002
        )
        let screenshot = makeInput(
            id: "screenshot",
            creationDate: olderDate,
            assetKind: .screenshot,
            latitude: 51.5003,
            longitude: -0.1003
        )

        _ = try await manager.indexPhotos([
            selected,
            newerPhoto,
            screenshot,
            olderPhoto
        ])

        let sections = try await manager.relatedSections(
            for: selected,
            limitPerSection: 3
        )

        #expect(sections.map(\.kind) == [.samePlaceEarlierYears])
        #expect(sections.first?.candidates.map(\.id) == ["older-photo"])
    }

    @Test func relatedSectionsFallBackToSamePlaceWithoutEarlierYears() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)

        let selectedDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 10)
        ))
        let sameYearDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 9)
        ))

        let selected = makeInput(
            id: "selected",
            creationDate: selectedDate,
            assetKind: .photo,
            latitude: 51.5,
            longitude: -0.1
        )
        let samePlace = makeInput(
            id: "same-place",
            creationDate: sameYearDate,
            assetKind: .photo,
            latitude: 51.5001,
            longitude: -0.1001
        )

        _ = try await manager.indexPhotos([selected, samePlace])

        let sections = try await manager.relatedSections(
            for: selected,
            limitPerSection: 3
        )

        #expect(sections.map(\.kind) == [.samePlace])
        #expect(sections.first?.candidates.map(\.id) == ["same-place"])
    }

    @Test func relatedSectionsPreferFavoritesBeforeOtherCandidates() async throws {
        let database = try makeDatabase()
        let manager = IndexManager(store: database.indexStore)

        let selectedDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 10)
        ))
        let olderDate = try #require(Calendar.current.date(
            from: DateComponents(year: 2024, month: 5, day: 10)
        ))

        let selected = makeInput(
            id: "selected",
            creationDate: selectedDate,
            assetKind: .photo,
            latitude: 51.5,
            longitude: -0.1
        )
        let nearbyRegularPhoto = makeInput(
            id: "nearby-regular-photo",
            creationDate: olderDate,
            assetKind: .photo,
            latitude: 51.5001,
            longitude: -0.1001
        )
        let fartherFavoritePhoto = makeInput(
            id: "farther-favorite-photo",
            creationDate: olderDate,
            assetKind: .photo,
            isFavorite: true,
            latitude: 51.501,
            longitude: -0.101
        )

        _ = try await manager.indexPhotos([
            selected,
            nearbyRegularPhoto,
            fartherFavoritePhoto
        ])

        let sections = try await manager.relatedSections(
            for: selected,
            limitPerSection: 3
        )

        #expect(sections.first?.candidates.map(\.id) == [
            "farther-favorite-photo",
            "nearby-regular-photo"
        ])
    }

    @Test func photoLibraryServiceSortsImagesOldestFirst() {
        let service = PhotoLibraryService()
        let options = service.makeImageFetchOptions()
        let sort = options.sortDescriptors?.first

        #expect(options.wantsIncrementalChangeDetails)
        #expect(sort?.key == "creationDate")
        #expect(sort?.ascending == true)
    }

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(dbQueue: DatabaseQueue())
    }

    private func makeInput(
        id: String,
        creationDate: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        modificationDate: Date? = nil,
        mediaSubtypesRawValue: UInt = 0,
        assetKind: IndexedAssetKind = .photo,
        isFavorite: Bool = false,
        pixelWidth: Int = 100,
        pixelHeight: Int = 100,
        latitude: Double? = 51.5,
        longitude: Double? = -0.1
    ) -> PhotoIndexInput {
        let latBucket = latitude.map(PhotoIndexInput.bucket(for:))
        let lonBucket = longitude.map(PhotoIndexInput.bucket(for:))

        return PhotoIndexInput(
            id: id,
            creationDate: creationDate,
            modificationDate: modificationDate,
            isFavorite: isFavorite,
            mediaSubtypesRawValue: mediaSubtypesRawValue,
            assetKind: assetKind,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            latitude: latitude,
            longitude: longitude,
            latBucket: latBucket,
            lonBucket: lonBucket
        )
    }

}
