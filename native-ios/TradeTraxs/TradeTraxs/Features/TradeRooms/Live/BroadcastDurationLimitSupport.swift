import Foundation

/// Video broadcast duration limits — mirrors `tradeRoomBroadcastDurationLimit.ts`.
enum BroadcastDurationLimitSupport {
    static let maxDuration: TimeInterval = 2 * 60 * 60
    static let cooldownDuration: TimeInterval = 15 * 60

    static let viewerEndedMessage =
        "This livestream ended after reaching the 2-hour broadcast limit."
    static let broadcasterEndedMessage =
        "Your stream reached the 2-hour limit and was ended automatically."
    static let cooldownStartMessage =
        "You reached the 2-hour broadcast limit. You can start another video stream in 15 minutes."

    static func remaining(from expiresAt: String?, now: Date = Date()) -> TimeInterval? {
        guard let raw = expiresAt?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = formatter.date(from: raw)
        if parsed == nil {
            formatter.formatOptions = [.withInternetDateTime]
            parsed = formatter.date(from: raw)
        }
        guard let expiry = parsed else { return nil }
        return max(0, expiry.timeIntervalSince(now))
    }

    static func isPastExpiry(_ expiresAt: String?, now: Date = Date()) -> Bool {
        guard let remaining = remaining(from: expiresAt, now: now) else { return false }
        return remaining <= 0
    }

    enum WarningLevel: Equatable {
        case none
        case fifteenMinutes
        case fiveMinutes
        case expired
    }

    static func warningLevel(for remaining: TimeInterval?) -> WarningLevel {
        guard let remaining else { return .none }
        if remaining <= 0 { return .expired }
        if remaining <= 5 * 60 { return .fiveMinutes }
        if remaining <= 15 * 60 { return .fifteenMinutes }
        return .none
    }

    static func warningCopy(for level: WarningLevel) -> String? {
        switch level {
        case .fifteenMinutes:
            return "15 minutes left on this broadcast."
        case .fiveMinutes:
            return "5 minutes left — the stream will end automatically at the 2-hour limit."
        case .expired:
            return broadcasterEndedMessage
        case .none:
            return nil
        }
    }

    static func formattedCountdown(remaining: TimeInterval) -> String {
        let total = max(0, Int(ceil(remaining)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}