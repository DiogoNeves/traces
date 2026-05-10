//
//  IndexingResult.swift
//  Traces
//
//  Created by Diogo Neves on 05/05/2026.
//

nonisolated struct IndexingResult: Equatable, Sendable {
    let indexedCount: Int
    let prunedCount: Int
}
