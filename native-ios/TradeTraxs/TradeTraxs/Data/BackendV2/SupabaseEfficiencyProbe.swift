import Foundation
import os

#if DEBUG
/// Lightweight Phase A evidence — one line per decision, no per-row noise.
nonisolated enum SupabaseEfficiencyProbe {
    enum ActivityReconnectMode: String {
        case unreadOnly
        case full
    }

    enum DashboardPayoutSource: String {
        case v3
        case legacyAchievements
    }

    enum ViewerSyncAuthority: String {
        case v3
        case v2
    }

    enum CalendarSource: String {
        case analytics
        case legacyRawTrades
    }

    enum DashboardTradeSource: String {
        case v3
        case legacyRawTrades
    }

    enum MessagingCatchUpMode: String {
        case lightweight
        case full
    }

    enum DashboardV3RequestMode: String {
        case new
        case joinedExisting
    }

    enum AnalyticsReconcileMode: String {
        case skippedCurrentRevision
        case network
    }

    enum SoftStaleFlightMode: String {
        case joined
        case new
    }

    nonisolated private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "SupabaseEfficiency"
    )

    nonisolated static func activityReconnect(_ mode: ActivityReconnectMode) {
        logger.debug("[SupabaseEfficiency] activityReconnect=\(mode.rawValue, privacy: .public)")
    }

    nonisolated static func dashboardPayoutSource(_ source: DashboardPayoutSource) {
        logger.debug("[SupabaseEfficiency] dashboardPayoutSource=\(source.rawValue, privacy: .public)")
    }

    nonisolated static func viewerSyncAuthority(_ authority: ViewerSyncAuthority) {
        logger.debug("[SupabaseEfficiency] viewerSyncAuthority=\(authority.rawValue, privacy: .public)")
    }

    nonisolated static func calendarSource(_ source: CalendarSource) {
        logger.debug("[SupabaseEfficiency] calendarSource=\(source.rawValue, privacy: .public)")
    }

    nonisolated static func dashboardTradeSource(_ source: DashboardTradeSource) {
        logger.debug("[SupabaseEfficiency] dashboardTradeSource=\(source.rawValue, privacy: .public)")
    }

    nonisolated static func messagingCatchUp(_ mode: MessagingCatchUpMode, reason: String) {
        logger.debug(
            "[SupabaseEfficiency] messagingCatchUp=\(mode.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    nonisolated static func dashboardV3Request(_ mode: DashboardV3RequestMode, reason: String) {
        logger.debug(
            "[SupabaseEfficiency] dashboardV3Request=\(mode.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    nonisolated static func analyticsReconcile(_ mode: AnalyticsReconcileMode) {
        logger.debug("[SupabaseEfficiency] analyticsReconcile=\(mode.rawValue, privacy: .public)")
    }

    nonisolated static func softStaleFlight(domain: String, mode: SoftStaleFlightMode) {
        logger.debug(
            "[SupabaseEfficiency] softStaleFlight=\(mode.rawValue, privacy: .public) domain=\(domain, privacy: .public)"
        )
    }
}
#endif
