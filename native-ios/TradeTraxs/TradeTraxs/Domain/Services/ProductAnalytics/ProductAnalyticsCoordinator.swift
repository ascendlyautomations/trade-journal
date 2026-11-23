import Foundation

/// Fire-and-forget product analytics — never blocks UI.
@MainActor
final class ProductAnalyticsCoordinator {
    static let shared = ProductAnalyticsCoordinator()

    private var repository: (any AnalyticsRepository)?
    private var sessionId = UUID()
    private var sessionStartedThisLaunch = false
    private var lastAppOpenHour: String?
    private var lastScreenByHour: [String: String] = [:]
    private var featuresThisSession = Set<String>()

    private init() {}

    func bind(repository: (any AnalyticsRepository)?) {
        let hadRepository = self.repository != nil
        self.repository = repository
        if repository != nil, !hadRepository {
            handleBecameActive()
        }
    }

    func resetSession() {
        sessionId = UUID()
        sessionStartedThisLaunch = false
        lastAppOpenHour = nil
        lastScreenByHour = [:]
        featuresThisSession = []
    }

    func handleBecameActive() {
        guard repository != nil else { return }
        noteSessionStartedIfNeeded()
        noteAppOpenedThrottled()
    }

    func handleEnterBackground() {
        guard let repository else { return }
        Task { await repository.flushPendingEvents() }
    }

    func noteSessionStartedIfNeeded() {
        guard let repository, !sessionStartedThisLaunch else { return }
        sessionStartedThisLaunch = true
        Task {
            await repository.track(
                event: ProductAnalyticsEventName.sessionStarted.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "dedupe_key": "session_started:\(sessionId.uuidString)",
                ]
            )
        }
    }

    func noteAppOpenedThrottled() {
        guard let repository else { return }
        let hour = Self.utcHourBucket()
        if lastAppOpenHour == hour { return }
        lastAppOpenHour = hour
        Task {
            await repository.track(
                event: ProductAnalyticsEventName.appOpened.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "dedupe_key": "app_opened:\(hour)",
                ]
            )
        }
    }

    func noteScreen(_ screen: ProductAnalyticsScreenID) {
        guard let repository, screen != .unknown else { return }
        let hour = Self.utcHourBucket()
        let key = "\(screen.rawValue):\(hour)"
        if lastScreenByHour[key] != nil { return }
        lastScreenByHour[key] = hour
        let featureInserted = Self.feature(for: screen).map { featuresThisSession.insert($0.rawValue).inserted } ?? false
        let feature = Self.feature(for: screen)
        Task {
            await repository.track(
                event: ProductAnalyticsEventName.screenViewed.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "screen_id": screen.rawValue,
                    "dedupe_key": "screen:\(sessionId.uuidString):\(screen.rawValue):\(hour)",
                ]
            )
            if featureInserted, let feature {
                await repository.track(
                    event: ProductAnalyticsEventName.featureUsed.rawValue,
                    properties: [
                        "session_id": sessionId.uuidString,
                        "feature": feature.rawValue,
                        "dedupe_key": "feature:\(sessionId.uuidString):\(feature.rawValue)",
                    ]
                )
            }
        }
    }

    func noteProfileViewed(profileID: ProfileID, viewerOwnsProfile: Bool) {
        guard let repository, !viewerOwnsProfile else { return }
        let day = Self.utcDay()
        Task {
            await repository.track(
                event: ProductAnalyticsEventName.profileViewed.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "profile_id": profileID.rawValue,
                    "dedupe_key": "profile_view:\(sessionId.uuidString):\(profileID.rawValue):\(day)",
                ]
            )
        }
    }

    func noteTraxsProPreviewStarted(
        entryPoint: TraxsProPreviewEntryPoint,
        previewFeature: TraxsProPreviewFeature
    ) {
        trackTraxsProPreviewEvent(
            ProductAnalyticsEventName.traxsProPreviewStarted,
            entryPoint: entryPoint,
            previewFeature: previewFeature
        )
    }

    func noteTraxsProPreviewExited(
        entryPoint: TraxsProPreviewEntryPoint,
        previewFeature: TraxsProPreviewFeature
    ) {
        trackTraxsProPreviewEvent(
            ProductAnalyticsEventName.traxsProPreviewExited,
            entryPoint: entryPoint,
            previewFeature: previewFeature
        )
    }

    func noteTraxsProPreviewUpgradeTapped(
        entryPoint: TraxsProPreviewEntryPoint,
        previewFeature: TraxsProPreviewFeature
    ) {
        trackTraxsProPreviewEvent(
            ProductAnalyticsEventName.traxsProPreviewUpgradeTapped,
            entryPoint: entryPoint,
            previewFeature: previewFeature
        )
    }

    func notePaywallViewed(gateReason: String) {
        guard let repository else { return }
        let dedupeSuffix = UUID().uuidString
        Task {
            await repository.track(
                event: ProductAnalyticsEventName.paywallViewed.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "gate_reason": gateReason,
                    "dedupe_key": "paywall_viewed:\(sessionId.uuidString):\(dedupeSuffix)",
                ]
            )
        }
    }

    func noteMonetizationUpgradeClicked(gateReason: String, billingProvider: String) {
        guard let repository else { return }
        let dedupeSuffix = UUID().uuidString
        Task {
            await repository.track(
                event: ProductAnalyticsEventName.monetizationUpgradeClicked.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "gate_reason": gateReason,
                    "billing_provider": billingProvider,
                    "dedupe_key": "monetization_upgrade_clicked:\(sessionId.uuidString):\(dedupeSuffix)",
                ]
            )
        }
    }

    private func trackTraxsProPreviewEvent(
        _ event: ProductAnalyticsEventName,
        entryPoint: TraxsProPreviewEntryPoint,
        previewFeature: TraxsProPreviewFeature
    ) {
        guard let repository else { return }
        let dedupeSuffix = UUID().uuidString
        Task {
            await repository.track(
                event: event.rawValue,
                properties: [
                    "session_id": sessionId.uuidString,
                    "entry_point": entryPoint.rawValue,
                    "preview_feature": previewFeature.rawValue,
                    "dedupe_key": "\(event.rawValue):\(sessionId.uuidString):\(dedupeSuffix)",
                ]
            )
        }
    }

    func mapTabToScreen(_ tab: TabIdentifier) -> ProductAnalyticsScreenID {
        switch tab {
        case .home: return .dashboard
        case .feed: return .feed
        case .create: return .addTrade
        case .messages: return .messages
        case .profile: return .profile
        }
    }

    private static func feature(for screen: ProductAnalyticsScreenID) -> ProductAnalyticsFeatureKey? {
        switch screen {
        case .dashboard: return .dashboard
        case .analytics: return .analytics
        case .trades, .tradeDetail: return .trades
        case .feed: return .feed
        case .messages, .messageThread: return .messages
        case .tradeRooms, .tradeRoom: return .tradeRooms
        case .aiAnalyst: return .aiAnalyst
        case .brokerIntegrations: return .brokerIntegrations
        case .calendar: return .calendar
        case .explore: return .explore
        case .addTrade: return .addTrade
        case .settings: return .settings
        case .profile: return .profile
        case .profileOther: return .profile
        case .reports: return .reports
        default: return nil
        }
    }

    private static func utcHourBucket() -> String {
        let c = Calendar(identifier: .gregorian)
        var cal = c
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let d = Date()
        let y = cal.component(.year, from: d)
        let m = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        let h = cal.component(.hour, from: d)
        return "\(y)-\(m)-\(day)-\(h)"
    }

    private static func utcDay() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: Date())
    }
}