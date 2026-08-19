import Foundation

/// Ephemeral handoff from Dashboard chart taps → Trade History.
///
/// Not a domain model — presentation-only seed consumed once on Trade History open.
/// Uses existing ``TradeHistoryFilters`` plus optional local-only constraints.
@MainActor
enum TradeHistoryLaunchSeed {
    struct Payload: Equatable, Sendable {
        var filters: TradeHistoryFilters
        var searchText: String = ""
        /// `Calendar` weekday (1 = Sunday … 7 = Saturday).
        var weekday: Int? = nil
        /// Hour of day `0...23` (entry time).
        var hour: Int? = nil
        /// Matches ``Trade.sessionLabel`` (case-insensitive contains).
        var sessionLabel: String? = nil
        /// Hold duration seconds range (half-open), matching Dashboard histogram buckets.
        var holdSecondsRange: HoldSecondsRange? = nil
    }

    struct HoldSecondsRange: Equatable, Sendable {
        var lower: TimeInterval
        var upper: TimeInterval

        func contains(_ seconds: TimeInterval) -> Bool {
            seconds >= lower && seconds < upper
        }
    }

    private static var pending: Payload?

    static func set(_ payload: Payload) {
        pending = payload
    }

    static func consume() -> Payload? {
        let value = pending
        pending = nil
        return value
    }

    /// Maps Dashboard histogram bucket labels to duration ranges.
    static func holdRange(forBucketLabel label: String) -> HoldSecondsRange? {
        switch label {
        case "<5m": return HoldSecondsRange(lower: 0, upper: 300)
        case "5–15m", "5-15m": return HoldSecondsRange(lower: 300, upper: 900)
        case "15–60m", "15-60m": return HoldSecondsRange(lower: 900, upper: 3_600)
        case "1–4h", "1-4h": return HoldSecondsRange(lower: 3_600, upper: 14_400)
        case "4h+": return HoldSecondsRange(lower: 14_400, upper: TimeInterval.greatestFiniteMagnitude)
        default: return nil
        }
    }

    static func calendarWeekday(forHeatmapLabel label: String) -> Int? {
        switch label {
        case "Sun": return 1
        case "Mon": return 2
        case "Tue": return 3
        case "Wed": return 4
        case "Thu": return 5
        case "Fri": return 6
        case "Sat": return 7
        default: return nil
        }
    }
}
