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
        PsychologyCheckInHistoryGate.psychologyPreviewParts(for: checkIn)
    }

    /// Distinct days under Check-In History → Psychology (web `countPsychologyCheckInHistoryDays`).
    static func countPsychologyCheckInHistoryDays(_ checkIns: [TraderDailyCheckIn]) -> Int {
        PsychologyCheckInHistoryGate.countPsychologyCheckInHistoryDays(checkIns)
    }
}

extension CheckInHistoryDaySummary {
    var hasPsychologyContent: Bool {
        guard let checkIn else { return false }
        return checkIn.qualifiesForPsychologyCheckInHistory
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
