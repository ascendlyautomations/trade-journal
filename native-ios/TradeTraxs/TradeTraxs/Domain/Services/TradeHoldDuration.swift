import Foundation

/// Hold duration from entry/exit — mirrors web `formatHoldDurationFromTimes` / `formatHoldDurationSeconds`.
nonisolated enum TradeHoldDuration {
    static func compute(entryAt: Date, exitAt: Date?) -> (seconds: Int, text: String)? {
        guard let exitAt, exitAt > entryAt else { return nil }
        let seconds = Int(exitAt.timeIntervalSince(entryAt).rounded(.down))
        guard seconds > 0, let text = formatSeconds(seconds) else { return nil }
        return (seconds, text)
    }

    static func formatSeconds(_ totalSeconds: Int) -> String? {
        guard totalSeconds > 0 else { return nil }

        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "\(days)d \(remHours)h"
        }

        if hours == 0, minutes == 0 {
            return "0m"
        }

        if hours == 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }

        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}
