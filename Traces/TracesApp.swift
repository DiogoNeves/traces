//
//  TracesApp.swift
//  Traces
//
//  Created by Diogo Neves on 28/04/2026.
//

import SwiftUI

@main
struct TracesApp: App {
    private let database: AppDatabase
    private let indexManager: IndexManager
    private let photoLibraryService: PhotoLibraryService
    
    init() {
        do {
            database = try AppDatabase()
            indexManager = IndexManager(store: database.indexStore)
            photoLibraryService = PhotoLibraryService()
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                indexManager: indexManager,
                photoLibraryService: photoLibraryService
            )
        }
    }
}
