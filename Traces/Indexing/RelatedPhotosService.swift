//
//  RelatedPhotosService.swift
//  Traces
//
//  Created by Diogo Neves on 12/05/2026.
//

import Foundation

nonisolated struct RelatedPhotosService {
    private let store: IndexStore
    private let calendar: Calendar

    init(
        store: IndexStore,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.calendar = calendar
    }

    func sections(
        for input: PhotoIndexInput,
        limitPerSection: Int = 3
    ) throws -> [RelatedPhotoSection] {
        guard limitPerSection > 0 else {
            return []
        }

        if let earlierYears = try samePlaceEarlierYearsSection(
            for: input,
            limit: limitPerSection
        ) {
            return [earlierYears]
        }

        if let samePlace = try samePlaceSection(
            for: input,
            limit: limitPerSection
        ) {
            return [samePlace]
        }

        return []
    }

    private func samePlaceEarlierYearsSection(
        for input: PhotoIndexInput,
        limit: Int
    ) throws -> RelatedPhotoSection? {
        guard let selectedDate = input.creationDate else {
            return nil
        }

        let candidates = try collectNearbyCandidates(
            for: input,
            olderThan: selectedDate,
            minimumCount: limit
        ) {
            yearDifference(
                from: $0.creationDate,
                to: input.creationDate
            ) != nil
        }
        let rankedCandidates = rankEarlierYearCandidates(
            candidates,
            selectedInput: input
        )
        let sectionCandidates = Array(rankedCandidates.prefix(limit))

        guard !sectionCandidates.isEmpty else {
            return nil
        }

        return RelatedPhotoSection(
            kind: .samePlaceEarlierYears,
            title: earlierYearsTitle(
                selectedDate: selectedDate,
                candidates: sectionCandidates
            ),
            candidates: sectionCandidates
        )
    }

    private func samePlaceSection(
        for input: PhotoIndexInput,
        limit: Int
    ) throws -> RelatedPhotoSection? {
        let candidates = try collectNearbyCandidates(
            for: input,
            olderThan: nil,
            minimumCount: limit
        ) { _ in true }
        let rankedCandidates = rankSamePlaceCandidates(
            candidates,
            selectedInput: input
        )
        let sectionCandidates = Array(rankedCandidates.prefix(limit))

        guard !sectionCandidates.isEmpty else {
            return nil
        }

        return RelatedPhotoSection(
            kind: .samePlace,
            title: "Same place",
            candidates: sectionCandidates
        )
    }

    private func collectNearbyCandidates(
        for input: PhotoIndexInput,
        olderThan: Date?,
        minimumCount: Int,
        isUsefulCandidate: (RelatedPhotoCandidate) -> Bool
    ) throws -> [RelatedPhotoCandidate] {
        var candidatesByID: [String: RelatedPhotoCandidate] = [:]

        for bucketRadius in [1, 2, 5] {
            let candidates = try store.nearbyCandidates(
                for: input,
                bucketRadius: bucketRadius,
                olderThan: olderThan,
                limit: 300
            )

            for candidate in candidates {
                candidatesByID[candidate.id] = candidate
            }

            let usefulCandidateCount = candidatesByID.values
                .filter(isUsefulCandidate)
                .count

            if usefulCandidateCount >= minimumCount {
                break
            }
        }

        return Array(candidatesByID.values)
    }

    private func rankEarlierYearCandidates(
        _ candidates: [RelatedPhotoCandidate],
        selectedInput: PhotoIndexInput
    ) -> [RelatedPhotoCandidate] {
        candidates
            .filter {
                yearDifference(
                    from: $0.creationDate,
                    to: selectedInput.creationDate
                ) != nil
            }
            .sorted {
                compareEarlierYearCandidates(
                    $0,
                    $1,
                    selectedInput: selectedInput
                )
            }
    }

    private func rankSamePlaceCandidates(
        _ candidates: [RelatedPhotoCandidate],
        selectedInput: PhotoIndexInput
    ) -> [RelatedPhotoCandidate] {
        candidates.sorted {
            compareSamePlaceCandidates(
                $0,
                $1,
                selectedInput: selectedInput
            )
        }
    }

    private func compareEarlierYearCandidates(
        _ lhs: RelatedPhotoCandidate,
        _ rhs: RelatedPhotoCandidate,
        selectedInput: PhotoIndexInput
    ) -> Bool {
        let lhsYearDifference = yearDifference(
            from: lhs.creationDate,
            to: selectedInput.creationDate
        ) ?? Int.max
        let rhsYearDifference = yearDifference(
            from: rhs.creationDate,
            to: selectedInput.creationDate
        ) ?? Int.max

        if lhsYearDifference != rhsYearDifference {
            return lhsYearDifference < rhsYearDifference
        }

        let lhsDateDistance = dateDistance(
            lhs.creationDate,
            selectedInput.creationDate
        )
        let rhsDateDistance = dateDistance(
            rhs.creationDate,
            selectedInput.creationDate
        )

        if lhsDateDistance != rhsDateDistance {
            return lhsDateDistance < rhsDateDistance
        }

        return compareLocationThenID(lhs, rhs, selectedInput: selectedInput)
    }

    private func compareSamePlaceCandidates(
        _ lhs: RelatedPhotoCandidate,
        _ rhs: RelatedPhotoCandidate,
        selectedInput: PhotoIndexInput
    ) -> Bool {
        let lhsLocationDistance = distanceMeters(from: selectedInput, to: lhs)
        let rhsLocationDistance = distanceMeters(from: selectedInput, to: rhs)

        switch (lhsLocationDistance, rhsLocationDistance) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        default:
            break
        }

        switch (
            selectedInput.creationDate,
            lhs.creationDate,
            rhs.creationDate
        ) {
        case let (selected?, lhsDate?, rhsDate?):
            let lhsDistance = abs(lhsDate.timeIntervalSince(selected))
            let rhsDistance = abs(rhsDate.timeIntervalSince(selected))

            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

        default:
            break
        }

        return lhs.id < rhs.id
    }

    private func compareLocationThenID(
        _ lhs: RelatedPhotoCandidate,
        _ rhs: RelatedPhotoCandidate,
        selectedInput: PhotoIndexInput
    ) -> Bool {
        let lhsDistance = distanceMeters(from: selectedInput, to: lhs)
        let rhsDistance = distanceMeters(from: selectedInput, to: rhs)

        switch (lhsDistance, rhsDistance) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        default:
            return lhs.id < rhs.id
        }
    }

    private func dateDistance(_ lhs: Date?, _ rhs: Date?) -> TimeInterval {
        guard let lhs,
              let rhs else {
            return .infinity
        }

        return abs(lhs.timeIntervalSince(rhs))
    }

    private func earlierYearsTitle(
        selectedDate: Date,
        candidates: [RelatedPhotoCandidate]
    ) -> String {
        let yearDifferences = Set(
            candidates.compactMap {
                yearDifference(from: $0.creationDate, to: selectedDate)
            }
        )

        guard yearDifferences.count == 1,
              let yearDifference = yearDifferences.first else {
            return "Same place, earlier years"
        }

        if yearDifference == 1 {
            return "Same place, 1 year ago"
        }

        return "Same place, \(yearDifference) years ago"
    }

    private func yearDifference(
        from candidateDate: Date?,
        to selectedDate: Date?
    ) -> Int? {
        guard let candidateDate,
              let selectedDate else {
            return nil
        }

        let candidateYear = calendar.component(.year, from: candidateDate)
        let selectedYear = calendar.component(.year, from: selectedDate)
        let yearDifference = selectedYear - candidateYear

        return yearDifference > 0 ? yearDifference : nil
    }

    private func distanceMeters(
        from input: PhotoIndexInput,
        to candidate: RelatedPhotoCandidate
    ) -> Double? {
        guard let inputLatitude = input.latitude,
              let inputLongitude = input.longitude,
              let candidateLatitude = candidate.latitude,
              let candidateLongitude = candidate.longitude else {
            return nil
        }

        return haversineDistanceMeters(
            latitude1: inputLatitude,
            longitude1: inputLongitude,
            latitude2: candidateLatitude,
            longitude2: candidateLongitude
        )
    }

    private func haversineDistanceMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let latitude1Radians = latitude1 * .pi / 180
        let latitude2Radians = latitude2 * .pi / 180
        let latitudeDelta = (latitude2 - latitude1) * .pi / 180
        let longitudeDelta = (longitude2 - longitude1) * .pi / 180

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1Radians)
            * cos(latitude2Radians)
            * sin(longitudeDelta / 2)
            * sin(longitudeDelta / 2)

        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
