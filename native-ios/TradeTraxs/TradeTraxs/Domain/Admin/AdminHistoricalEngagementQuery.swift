import Foundation

nonisolated enum AdminHistoricalActivityFilter: String, CaseIterable, Codable, Sendable, Hashable {
    case all
    case trading
    case social

    var menuLabel: String {
        switch self {
        case .all: return "All"
        case .trading: return "Trading"
        case .social: return "Social"
        }
    }
}

nonisolated enum AdminHistoricalEngagementPreset: String, CaseIterable, Codable, Sendable, Hashable {
    case days30
    case days90
    case days180
    case days365
    case custom

    var menuLabel: String {
        switch self {
        case .days30: return "30D"
        case .days90: return "90D"
        case .days180: return "6M"
        case .days365: return "1Y"
        case .custom: return "Custom"
        }
    }

    var seriesDays: Int? {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .days180: return 180
        case .days365: return 365
        case .custom: return nil
        }
    }
}

nonisolated struct AdminHistoricalEngagementQuery: Sendable, Hashable, Codable {
    var preset: AdminHistoricalEngagementPreset
    var customStartDate: String?
    var customEndDate: String?
    var activityFilter: AdminHistoricalActivityFilter

    static let storageKey = "tradetraxs.admin.historicalEngagement.v1"

    static let `default` = AdminHistoricalEngagementQuery(
        preset: .days90,
        customStartDate: nil,
        customEndDate: nil,
        activityFilter: .all
    )
}

enum AdminHistoricalEngagementQueryStore {
    static func load() -> AdminHistoricalEngagementQuery {
        guard let data = UserDefaults.standard.data(forKey: AdminHistoricalEngagementQuery.storageKey),
              let decoded = try? JSONDecoder().decode(AdminHistoricalEngagementQuery.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ query: AdminHistoricalEngagementQuery) {
        guard let data = try? JSONEncoder().encode(query) else { return }
        UserDefaults.standard.set(data, forKey: AdminHistoricalEngagementQuery.storageKey)
    }

    static func validate(_ query: AdminHistoricalEngagementQuery) -> String? {
        guard query.preset != .custom else {
            guard let start = query.customStartDate, let end = query.customEndDate,
                  !start.isEmpty, !end.isEmpty else {
                return "Choose start and end dates."
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            guard let startD = formatter.date(from: start), let endD = formatter.date(from: end),
                  let today = formatter.date(from: formatter.string(from: Date())) else {
                return "Invalid dates."
            }
            if startD > today || endD > today { return "Dates cannot be in the future (UTC)." }
            if startD > endD { return "Start must be on or before end." }
            let days = Calendar(identifier: .gregorian).dateComponents([.day], from: startD, to: endD).day ?? 0
            if days + 1 > 365 { return "Range cannot exceed 365 days." }
            return nil
        }
        return nil
    }
}