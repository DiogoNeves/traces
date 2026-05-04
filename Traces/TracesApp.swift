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
    
    init() {
        do {
            database = try AppDatabase()
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
