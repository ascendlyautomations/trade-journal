import Foundation

/// Hold duration from entry/exit — mirrors web `formatHoldDurationFromTimes` / `formatHoldDurationSeconds`.
nonisolated enum TradeHoldDuration {
    static func compute(entryAt: Date, exitAt: Date?) -> (seconds: Int, text: String)? {
        guard let exitAt, exitAt >= entryAt else { return nil }
        let seconds = Int(exitAt.timeIntervalSince(entryAt).rounded(.down))
        let allowSubMinute = timestampsSupportSecondPrecision(entryAt: entryAt, exitAt: exitAt)
        guard let text = formatSeconds(seconds, allowSubMinuteSeconds: allowSubMinute) else { return nil }
        return (seconds, text)
    }

    /// When false, sub-minute positive durations return nil (date-only / minute-only clocks).
    static func formatSeconds(_ totalSeconds: Int, allowSubMinuteSeconds: Bool = true) -> String? {
        guard totalSeconds >= 0 else { return nil }
        if totalSeconds == 0 { return "0s" }
        if totalSeconds < 60 {
            guard allowSubMinuteSeconds else { return nil }
            return "\(totalSeconds)s"
        }

        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "\(days)d \(remHours)h"
        }

        if hours == 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }

        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }

    /// True when entry/exit carry clock time beyond date-only midnight placeholders.
    static func timestampsSupportSecondPrecision(entryAt: Date, exitAt: Date) -> Bool {
        if exitAt.timeIntervalSince(entryAt).truncatingRemainder(dividingBy: 1) != 0 {
            return true
        }
        let calendar = Calendar.current
        let entry = calendar.dateComponents([.hour, .minute, .second], from: entryAt)
        let exit = calendar.dateComponents([.hour, .minute, .second], from: exitAt)
        func isDateOnlyMidnight(_ components: DateComponents) -> Bool {
            (components.hour ?? 0) == 0
                && (components.minute ?? 0) == 0
                && (components.second ?? 0) == 0
        }
        if isDateOnlyMidnight(entry), isDateOnlyMidnight(exit) {
            return false
        }
        return true
    }
}
