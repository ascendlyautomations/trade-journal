import Foundation

/// Screen that owns a contextual tour. The walkthrough is one definition.
enum ContextualTourID: String, Codable, Hashable, Sendable {
    case dashboard
}

/// Where a walkthrough step is shown. The coordinator waits until this surface is on screen.
enum ContextualTourSurface: String, Equatable, Sendable {
    case dashboard
    case feed
    case profile
    case settings
}

enum ContextualTourStepRole: Equatable, Sendable {
    /// Measure a real control, then spotlight it.
    case spotlight
    /// Explain immediately. A target, when it can be measured, still gets a hole.
    case narration
    /// Continue / Exit between major sections. No spotlight.
    case sectionContinue
    case finish

    /// Shown in progress and as a full explanation card.
    var countsTowardProgress: Bool {
        switch self {
        case .spotlight, .narration, .finish:
            return true
        case .sectionContinue:
            return false
        }
    }
}

/// A real control the spotlight measures. Never a hard-coded coordinate.
enum ContextualTourTargetID: String, Hashable, Sendable {
    case dashboardAccountAndDates
    case dashboardPerformance
    case dashboardTrades
    case dashboardReports
    case dashboardWithdrawals
    case dashboardCalendar
    case dashboardNotifications
    case feedContentFilters
    case feedTradeRooms
    case feedExplore
    case profileIdentity
    case profileTradeRoom
    case settingsAppearance
}

struct ContextualTourStep: Equatable, Sendable {
    var target: ContextualTourTargetID?
    var title: String
    var message: String
    var surface: ContextualTourSurface
    var role: ContextualTourStepRole
    /// Toolbar controls can sit outside the preference tree. Explain them anyway.
    var presentsIfUnmeasured: Bool = false

    init(
        target: ContextualTourTargetID? = nil,
        title: String,
        message: String,
        surface: ContextualTourSurface,
        role: ContextualTourStepRole = .spotlight,
        presentsIfUnmeasured: Bool = false
    ) {
        self.target = target
        self.title = title
        self.message = message
        self.surface = surface
        self.role = role
        self.presentsIfUnmeasured = presentsIfUnmeasured
    }
}

struct ContextualTourDefinition: Equatable, Sendable {
    let id: ContextualTourID
    /// Increment only this tour when its screen is redesigned.
    /// Stays at 1 so a completed Dashboard tour is not forced again.
    /// Settings replay uses in-memory replay and does not depend on a version bump.
    let version: Int
    let steps: [ContextualTourStep]

    var informationalStepCount: Int {
        steps.filter(\.role.countsTowardProgress).count
    }
}

/// Accounts created before this instant do not receive automatic tours.
/// Same instant in Debug and Release. Do not use device install date.
enum ContextualTourLaunch {
    static let productionAccountCreatedAtCutoffISO8601 = "2026-09-23T00:00:00Z"

    static let accountCreatedAtCutoff: Date = {
        ISO8601.date(from: productionAccountCreatedAtCutoffISO8601)
            ?? Date(timeIntervalSince1970: 1_790_121_600)
    }()
}

enum ContextualTourCatalog {
    static let dashboard = ContextualTourDefinition(
        id: .dashboard,
        version: 1,
        steps: walkthroughSteps
    )

    private static let walkthroughSteps: [ContextualTourStep] = [
        ContextualTourStep(
            target: .dashboardAccountAndDates,
            title: "Accounts & timeframe",
            message: "Pick which account and period the Dashboard uses.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardPerformance,
            title: "Equity curve",
            message: "See how your account has performed over time.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardTrades,
            title: "Trades",
            message: "Review your full trade journal.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardReports,
            title: "Reports",
            message: "Weekly and monthly performance breakdowns.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardWithdrawals,
            title: "Withdrawals",
            message: "Track live and prop-firm payouts.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardCalendar,
            title: "Calendar",
            message: "Review performance day by day.",
            surface: .dashboard,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            target: .dashboardNotifications,
            title: "Notifications",
            message: "Social updates and activity alerts.",
            surface: .dashboard,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            title: "Continue to Feed",
            message: "",
            surface: .dashboard,
            role: .sectionContinue
        ),
        ContextualTourStep(
            target: .feedContentFilters,
            title: "Feed filters",
            message: "Filter by trades, posts, clips, and more.",
            surface: .feed,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            target: .feedTradeRooms,
            title: "Trade Rooms",
            message: "Chat and trade with your communities.",
            surface: .feed,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            target: .feedExplore,
            title: "Explore",
            message: "Find traders and content across TradeTraxs.",
            surface: .feed,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            title: "Continue to Profile",
            message: "",
            surface: .feed,
            role: .sectionContinue
        ),
        ContextualTourStep(
            target: .profileIdentity,
            title: "Profile",
            message: "Your identity, stats, and shared content.",
            surface: .profile,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            target: .profileTradeRoom,
            title: "Your Trade Room",
            message: "Your community space for market discussion.",
            surface: .profile,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            target: .settingsAppearance,
            title: "Appearance",
            message: "Choose System, Light, or Dark mode.",
            surface: .settings,
            presentsIfUnmeasured: true
        ),
        ContextualTourStep(
            title: "You're all set",
            message: "Replay this walkthrough anytime in Settings.",
            surface: .settings,
            role: .finish
        ),
    ]
}
