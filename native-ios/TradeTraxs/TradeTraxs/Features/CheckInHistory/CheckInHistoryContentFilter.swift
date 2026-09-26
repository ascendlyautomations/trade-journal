import Foundation

enum CheckInHistoryContentFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case trades
    case psychology

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .trades: return "Trades"
        case .psychology: return "Psychology"
        }
    }
}

enum CheckInHistoryFieldClassification {
    /// Daily check-in questionnaire fields (Sleep, Morning, Mental State, Notes).
    static func psychologyPreviewParts(for checkIn: TraderDailyCheckIn) -> [String] {
        var parts: [String] = []
        if let hours = checkIn.sleepHours {
            parts.append("\(NumberDisplay.hours(NSDecimalNumber(decimal: hours).doubleValue)) Sleep")
        }
        if let quality = checkIn.sleepQuality {
            parts.append("Sleep Quality \(quality)/5")
        }
        if let morning = checkIn.morningRating {
            parts.append("Morning \(morning)/5")
        }
        if let stress = checkIn.stressLevel {
            parts.append("Stress \(TraderDailyCheckInStressScale.displayText(for: stress))")
        }
        if let energy = checkIn.energyLevel {
            parts.append("Energy \(energy)/5")
        }
        if let focus = checkIn.focusLevel {
            parts.append("Focus \(focus)/5")
        }
        if let notes = checkIn.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        return parts
    }
}

extension CheckInHistoryDaySummary {
    var hasPsychologyContent: Bool {
        guard let checkIn else { return false }
        return !CheckInHistoryFieldClassification.psychologyPreviewParts(for: checkIn).isEmpty
    }

    func matches(contentFilter: CheckInHistoryContentFilter) -> Bool {
        switch contentFilter {
        case .all:
            return true
        case .trades:
            return hasTrades
        case .psychology:
            return hasPsychologyContent
        }
    }
}
