//
//  IndexingError.swift
//  Traces
//
//  Created by Diogo Neves on 05/05/2026.
//

import Foundation

enum IndexingError: LocalizedError {
    case alreadyIndexing

    var errorDescription: String? {
        switch self {
        case .alreadyIndexing:
            return "Indexing is already in progress."
        }
    }
}
