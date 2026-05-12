//
//  RelatedPhotosService.swift
//  Traces
//
//  Created by Diogo Neves on 12/05/2026.
//

import Foundation

nonisolated struct RelatedPhotosService {
    private struct YearBucket {
        let offset: Int
        let createdAfter: Date?
        let createdBefore: Date
    }

    private struct BucketedCandidate {
        let bucketOffset: Int
        let candidate: RelatedPhotoCandidate
    }

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

        var sections: [RelatedPhotoSection] = []
        var usedCandidateIDs = Set<String>()

        if let overTheYears = try overTheYearsSection(
            for: input,
            maxCount: min(max(limitPerSection, 2), 6)
        ) {
            sections.append(overTheYears)
            usedCandidateIDs.formUnion(overTheYears.candidates.map(\.id))
        }

        if let earlierYears = try samePlaceEarlierYearsSection(
            for: input,
            limit: min(limitPerSection, 3),
            excluding: usedCandidateIDs
        ) {
            sections.append(earlierYears)
            usedCandidateIDs.formUnion(earlierYears.candidates.map(\.id))
        }

        if let samePlace = try samePlaceSection(
            for: input,
            limit: min(limitPerSection, 3),
            excluding: usedCandidateIDs
        ) {
            sections.append(samePlace)
        }

        return sections
    }

    private func overTheYearsSection(
        for input: PhotoIndexInput,
        maxCount: Int
    ) throws -> RelatedPhotoSection? {
        guard let selectedDate = input.creationDate else {
            return nil
        }

        let buckets = makeYearBuckets(before: selectedDate)
        let bucketedCandidates = try collectOverTheYearsCandidates(
            for: input,
            buckets: buckets,
            minimumCount: 2
        )
        let sectionCandidates = spreadOverTheYearsCandidates(
            bucketedCandidates,
            maxCount: maxCount,
            selectedInput: input
        )

        guard sectionCandidates.count >= 2 else {
            return nil
        }

        return RelatedPhotoSection(
            kind: .overTheYears,
            title: "Over the years",
            candidates: sectionCandidates
        )
    }

    private func samePlaceEarlierYearsSection(
        for input: PhotoIndexInput,
        limit: Int,
        excluding excludedIDs: Set<String>
    ) throws -> RelatedPhotoSection? {
        guard let selectedDate = input.creationDate else {
            return nil
        }

        let candidates = try collectNearbyCandidates(
            for: input,
            createdAfter: nil,
            createdBefore: selectedDate,
            minimumCount: limit
        ) {
            !excludedIDs.contains($0.id) &&
            yearDifference(
                from: $0.creationDate,
                to: input.creationDate
            ) != nil
        }
        let rankedCandidates = rankEarlierYearCandidates(
            candidates,
            selectedInput: input
        ).filter { !excludedIDs.contains($0.id) }
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
        limit: Int,
        excluding excludedIDs: Set<String>
    ) throws -> RelatedPhotoSection? {
        let candidates = try collectNearbyCandidates(
            for: input,
            createdAfter: nil,
            createdBefore: nil,
            minimumCount: limit
        ) { !excludedIDs.contains($0.id) }
        let rankedCandidates = rankSamePlaceCandidates(
            candidates,
            selectedInput: input
        ).filter { !excludedIDs.contains($0.id) }
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
        createdAfter: Date?,
        createdBefore: Date?,
        minimumCount: Int,
        isUsefulCandidate: (RelatedPhotoCandidate) -> Bool
    ) throws -> [RelatedPhotoCandidate] {
        var candidatesByID: [String: RelatedPhotoCandidate] = [:]

        for bucketRadius in [1, 2, 5] {
            let candidates = try store.nearbyCandidates(
                for: input,
                bucketRadius: bucketRadius,
                createdAfter: createdAfter,
                createdBefore: createdBefore,
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

    private func collectOverTheYearsCandidates(
        for input: PhotoIndexInput,
        buckets: [YearBucket],
        minimumCount: Int
    ) throws -> [BucketedCandidate] {
        var candidatesByID: [String: BucketedCandidate] = [:]

        for bucketRadius in [1, 2, 5] {
            for bucket in buckets {
                let candidates = try store.nearbyCandidates(
                    for: input,
                    bucketRadius: bucketRadius,
                    createdAfter: bucket.createdAfter,
                    createdBefore: bucket.createdBefore,
                    limit: 60
                )

                for candidate in candidates {
                    candidatesByID[candidate.id] = BucketedCandidate(
                        bucketOffset: bucket.offset,
                        candidate: candidate
                    )
                }
            }

            if candidatesByID.count >= minimumCount {
                break
            }
        }

        return Array(candidatesByID.values)
    }

    private func spreadOverTheYearsCandidates(
        _ bucketedCandidates: [BucketedCandidate],
        maxCount: Int,
        selectedInput: PhotoIndexInput
    ) -> [RelatedPhotoCandidate] {
        var selected: [RelatedPhotoCandidate] = []

        for isFavorite in [true, false] {
            var candidatesByBucket = Dictionary(
                grouping: bucketedCandidates.filter {
                    $0.candidate.isFavorite == isFavorite
                },
                by: \.bucketOffset
            )

            for bucketOffset in candidatesByBucket.keys {
                candidatesByBucket[bucketOffset]?.sort {
                    compareOverTheYearsCandidates(
                        $0,
                        $1,
                        selectedInput: selectedInput
                    )
                }
            }

            while selected.count < maxCount {
                var addedCandidate = false

                for bucketOffset in [10, 5, 2, 0] {
                    guard let nextCandidate = candidatesByBucket[bucketOffset]?
                        .first else {
                        continue
                    }

                    selected.append(nextCandidate.candidate)
                    candidatesByBucket[bucketOffset]?.removeFirst()
                    addedCandidate = true

                    if selected.count == maxCount {
                        break
                    }
                }

                if !addedCandidate {
                    break
                }
            }
        }

        return selected.sorted {
            compareOverTheYearsDisplayOrder(
                $0,
                $1,
                selectedInput: selectedInput
            )
        }
    }

    private func compareOverTheYearsCandidates(
        _ lhs: BucketedCandidate,
        _ rhs: BucketedCandidate,
        selectedInput: PhotoIndexInput
    ) -> Bool {
        let lhsDistance = distanceMeters(from: selectedInput, to: lhs.candidate)
        let rhsDistance = distanceMeters(from: selectedInput, to: rhs.candidate)

        switch (lhsDistance, rhsDistance) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        default:
            break
        }

        switch (lhs.candidate.creationDate, rhs.candidate.creationDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        default:
            return lhs.candidate.id < rhs.candidate.id
        }
    }

    private func compareOverTheYearsDisplayOrder(
        _ lhs: RelatedPhotoCandidate,
        _ rhs: RelatedPhotoCandidate,
        selectedInput: PhotoIndexInput
    ) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite
        }

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
            break
        }

        switch (lhs.creationDate, rhs.creationDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        default:
            return lhs.id < rhs.id
        }
    }

    private func makeYearBuckets(before selectedDate: Date) -> [YearBucket] {
        guard let twoYearsAgo = calendar.date(
            byAdding: .year,
            value: -2,
            to: selectedDate
        ),
              let fiveYearsAgo = calendar.date(
                byAdding: .year,
                value: -5,
                to: selectedDate
              ),
              let tenYearsAgo = calendar.date(
                byAdding: .year,
                value: -10,
                to: selectedDate
              ) else {
            return []
        }

        return [
            YearBucket(
                offset: 10,
                createdAfter: nil,
                createdBefore: tenYearsAgo
            ),
            YearBucket(
                offset: 5,
                createdAfter: tenYearsAgo,
                createdBefore: fiveYearsAgo
            ),
            YearBucket(
                offset: 2,
                createdAfter: fiveYearsAgo,
                createdBefore: twoYearsAgo
            ),
            YearBucket(
                offset: 0,
                createdAfter: twoYearsAgo,
                createdBefore: selectedDate
            )
        ]
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
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite
        }

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
            break
        }

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
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite
        }

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
