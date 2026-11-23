import Foundation

/// Rolling / custom windows for thematic psychology reports.
nonisolated enum PsychologyReportTimePreset: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "rolling:7d"
    case thirtyDays = "rolling:30d"
    case ninetyDays = "rolling:90d"
    case sixMonths = "rolling:6m"
    case all = "rolling:all"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .ninetyDays: return "90D"
        case .sixMonths: return "6M"
        case .all: return "All"
        }
    }

    static func from(periodID: String) -> PsychologyReportTimePreset? {
        PsychologyReportTimePreset(rawValue: periodID)
    }
}

/// Resolved period identity for generator + UI.
nonisolated enum PsychologyReportTimeScope: Equatable, Sendable {
    case preset(PsychologyReportTimePreset)
    case custom(DateInterval)

    var periodID: String {
        switch self {
        case .preset(let preset):
            return preset.rawValue
        case .custom(let interval):
            let start = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: interval.start)
            let end = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: interval.end)
            return "custom:\(start):\(end)"
        }
    }

    static func from(periodID: String) -> PsychologyReportTimeScope {
        if let preset = PsychologyReportTimePreset.from(periodID: periodID) {
            return .preset(preset)
        }
        if periodID.hasPrefix("custom:") {
            let rest = String(periodID.dropFirst("custom:".count))
            let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2,
               let start = dayKeyDate(parts[0]),
               let end = dayKeyDate(parts[1]) {
                let calendar = TradingReportPeriods.eastern
                let normalized = DashboardScopeFilterSupport.normalizedCustomInterval(
                    start: start,
                    end: end,
                    calendar: calendar
                )
                return .custom(normalized)
            }
        }
        return .preset(.ninetyDays)
    }

    var menuTitle: String {
        switch self {
        case .preset(let preset):
            return preset.menuTitle
        case .custom(let interval):
            return DashboardScopeFilterSupport.compactTimeLabel(
                dateRange: .thirtyDays,
                customInterval: interval
            )
        }
    }

    private static func dayKeyDate(_ key: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TradingReportPeriods.eastern.timeZone
        return formatter.date(from: key)
    }
}