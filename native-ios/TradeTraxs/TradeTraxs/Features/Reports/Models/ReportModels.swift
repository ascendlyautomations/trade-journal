import Foundation

/// Catalog card for a web Trading Report period.
struct ReportTypeCardModel: Hashable, Identifiable, Sendable {
    var id: TradingReportPeriodKey { periodKey }
    var periodKey: TradingReportPeriodKey
    var title: String
    var subtitle: String
    var systemImage: String
    var actionTitle: String
    var availability: ReportAvailability
    var dateRangeLabel: String?

    var reportID: ReportID { periodKey.reportID }
}

enum ReportAvailability: Hashable, Codable, Sendable {
    case readyToGenerate
    case generating
    case ready

    var actionTitle: String {
        switch self {
        case .ready: return "View Report"
        case .readyToGenerate, .generating: return "Generate"
        }
    }
}
