import Foundation

/// Owner-only daily lifestyle / mental-state check-in — separate from per-trade psychology.
nonisolated struct TraderDailyCheckIn: Hashable, Codable, Sendable, Identifiable {
    var id: TraderDailyCheckInID
    var ownerProfileID: ProfileID
    /// Eastern trade date (`YYYY-MM-DD`) — matches `trades.trade_date` semantics.
    var checkInDate: String
    var sleepHours: Decimal?
    var sleepQuality: Int?
    var morningRating: Int?
    var stressLevel: Int?
    var energyLevel: Int?
    var focusLevel: Int?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    var isComplete: Bool {
        TraderDailyCheckInValidation.isComplete(self)
    }
}

/// Create / edit payload for today's (or historical) check-in.
nonisolated struct TraderDailyCheckInDraft: Hashable, Sendable {
    var checkInDate: String
    var sleepHours: Decimal?
    var sleepQuality: Int
    var morningRating: Int
    var stressLevel: Int
    var energyLevel: Int
    var focusLevel: Int
    var notes: String

    init(
        checkInDate: String,
        sleepHours: Decimal?,
        sleepQuality: Int,
        morningRating: Int,
        stressLevel: Int,
        energyLevel: Int,
        focusLevel: Int,
        notes: String
    ) {
        self.checkInDate = checkInDate
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.morningRating = morningRating
        self.stressLevel = stressLevel
        self.energyLevel = energyLevel
        self.focusLevel = focusLevel
        self.notes = notes
    }

    static func empty(for checkInDate: String) -> TraderDailyCheckInDraft {
        TraderDailyCheckInDraft(
            checkInDate: checkInDate,
            sleepHours: nil,
            sleepQuality: 3,
            morningRating: 3,
            stressLevel: 3,
            energyLevel: 3,
            focusLevel: 3,
            notes: ""
        )
    }

    init(checkIn: TraderDailyCheckIn) {
        checkInDate = checkIn.checkInDate
        sleepHours = checkIn.sleepHours
        sleepQuality = checkIn.sleepQuality ?? 3
        morningRating = checkIn.morningRating ?? 3
        stressLevel = checkIn.stressLevel ?? 3
        energyLevel = checkIn.energyLevel ?? 3
        focusLevel = checkIn.focusLevel ?? 3
        notes = checkIn.notes ?? ""
    }
}

/// Stress rating scale for daily check-ins — 1 is most stressed, 5 is calmest (matches other 1–5 metrics).
nonisolated enum TraderDailyCheckInStressScale {
    static let labels: [Int: String] = [
        1: "Very Stressed",
        2: "Stressed",
        3: "Moderate",
        4: "Relaxed",
        5: "Calm",
    ]

    static func label(for level: Int) -> String {
        labels[level] ?? "\(level)/5"
    }

    static func displayText(for level: Int?) -> String {
        guard let level else { return "—" }
        return "\(label(for: level)) (\(level)/5)"
    }

    static func averageDisplayText(for average: Double) -> String {
        let rounded = min(5, max(1, Int(average.rounded())))
        return String(format: "%.1f/5 · %@", average, label(for: rounded))
    }

    /// True when the trader reported elevated stress (1–2 on the calmness scale).
    static func isElevated(_ level: Int) -> Bool {
        level <= 2
    }
}

nonisolated enum TraderDailyCheckInValidation {
    static let ratingRange = 1...5
    static let sleepHoursRange: ClosedRange<Decimal> = 0...24

    static func isComplete(_ checkIn: TraderDailyCheckIn) -> Bool {
        guard let sleepHours = checkIn.sleepHours,
              sleepHoursRange.contains(sleepHours)
        else { return false }
        return [
            checkIn.sleepQuality,
            checkIn.morningRating,
            checkIn.stressLevel,
            checkIn.energyLevel,
            checkIn.focusLevel,
        ].allSatisfy { rating in
            guard let rating else { return false }
            return ratingRange.contains(rating)
        }
    }

    static func validate(_ draft: TraderDailyCheckInDraft) -> String? {
        guard let sleepHours = draft.sleepHours, sleepHoursRange.contains(sleepHours) else {
            return "Enter hours of sleep between 0 and 24."
        }
        let ratings: [(String, Int)] = [
            ("Sleep quality", draft.sleepQuality),
            ("Morning rating", draft.morningRating),
            ("Stress", draft.stressLevel),
            ("Energy", draft.energyLevel),
            ("Focus", draft.focusLevel),
        ]
        for (label, value) in ratings where !ratingRange.contains(value) {
            return "\(label) must be between 1 and 5."
        }
        return nil
    }
}
