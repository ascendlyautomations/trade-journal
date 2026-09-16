import Foundation

/// Authoritative max drawdown methodology from `accounts.drawdown_type` — never inferred client-side.
nonisolated enum PropFirmDrawdownType: String, Codable, Sendable, Hashable, CaseIterable {
    case staticThreshold = "static"
    case intradayTrailing = "intraday_trailing"
    case endOfDayTrailing = "end_of_day_trailing"

    var displayName: String {
        switch self {
        case .staticThreshold:
            return "Static"
        case .intradayTrailing:
            return "Intraday Trailing"
        case .endOfDayTrailing:
            return "End-of-Day Trailing"
        }
    }

    /// One-line UI copy when the type is known.
    var conciseFootnote: String {
        switch self {
        case .staticThreshold:
            return "The drawdown threshold stays fixed; it does not trail account performance."
        case .intradayTrailing:
            return "The drawdown can trail the session high-water mark while you trade."
        case .endOfDayTrailing:
            return "The drawdown threshold trails using your firm's end-of-day balance rules."
        }
    }

    var usesTrailingCycleFloor: Bool {
        switch self {
        case .intradayTrailing, .endOfDayTrailing:
            return true
        case .staticThreshold:
            return false
        }
    }

    static func parse(raw: String?) -> PropFirmDrawdownType? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return PropFirmDrawdownType(rawValue: normalized)
    }
}
