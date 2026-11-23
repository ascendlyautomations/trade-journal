import Foundation

nonisolated enum AdminLifecycleAnalyticsPreset: String, CaseIterable, Codable, Sendable, Hashable {
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

nonisolated struct AdminLifecycleAnalyticsQuery: Sendable, Hashable, Codable {
    var preset: AdminLifecycleAnalyticsPreset
    var customStartDate: String?
    var customEndDate: String?

    static let storageKey = "tradetraxs.admin.lifecycleAnalytics.v1"

    static let `default` = AdminLifecycleAnalyticsQuery(
        preset: .days90,
        customStartDate: nil,
        customEndDate: nil
    )
}

enum AdminLifecycleAnalyticsQueryStore {
    static func load() -> AdminLifecycleAnalyticsQuery {
        guard let data = UserDefaults.standard.data(forKey: AdminLifecycleAnalyticsQuery.storageKey),
              let decoded = try? JSONDecoder().decode(AdminLifecycleAnalyticsQuery.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ query: AdminLifecycleAnalyticsQuery) {
        guard let data = try? JSONEncoder().encode(query) else { return }
        UserDefaults.standard.set(data, forKey: AdminLifecycleAnalyticsQuery.storageKey)
    }
}