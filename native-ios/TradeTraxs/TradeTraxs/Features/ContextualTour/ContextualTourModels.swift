import Foundation

/// Screen that owns a contextual tour. The walkthrough is one definition.
enum ContextualTourID: String, Codable, Hashable, Sendable {
    case dashboard
}

/// Where a walkthrough step is shown. The coordinator waits until this surface is on screen.
enum ContextualTourSurface: String, Equatable, Sendable {
    case dashboard
    case feed
    case messages
    case profile
    case settings
    case payouts
    case expenseTracker
    case trades
}

enum ContextualTourStepRole: Equatable, Sendable {
    /// Measure a real control, then spotlight it.
    case spotlight
    /// Explain immediately. A target, when it can be measured, still gets a hole.
    case narration
    /// Continue / Exit between major sections. No spotlight.
    case sectionContinue
    case finish
    /// End-of-tour choice before dismissal (e.g. open Trading Rules).
    case tradingRulesPrompt

    /// Shown in progress and as a full explanation card.
    var countsTowardProgress: Bool {
        switch self {
        case .spotlight, .narration, .finish, .tradingRulesPrompt:
            return true
        case .sectionContinue:
            return false
        }
    }
}

/// A real control the spotlight measures. Never a hard-coded coordinate.
enum ContextualTourTargetID: String, CaseIterable, Hashable, Sendable {
    case mainTabHome
    case mainTabFeed
    case mainTabCreate
    case mainTabMessages
    case mainTabProfile
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
    case profileSettings
    case settingsAppearance
    case settingsTradingRules
    case payoutsHistory
    case expenseTrackerAdd
    case expenseTrackerIncome
    case expenseTrackerAnalytics
    case expenseTrackerExport
}

extension ContextualTourTargetID {
    var mainTabIdentifier: TabIdentifier? {
        switch self {
        case .mainTabHome: return .home
        case .mainTabFeed: return .feed
        case .mainTabCreate: return .create
        case .mainTabMessages: return .messages
        case .mainTabProfile: return .profile
        default: return nil
        }
    }

    var isMainTabBarTarget: Bool { mainTabIdentifier != nil }

    var prefersWalkthroughCardAboveSpotlight: Bool {
        isMainTabBarTarget
    }
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
            target: .mainTabHome,
            title: "Home tab — Your Dashboard",
            message: "View your trading performance, journal, and analytics in one place.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardAccountAndDates,
            title: "Accounts & Timeframe",
            message: "Choose which trading accounts and dates to analyze.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardPerformance,
            title: "Trading Performance",
            message: "Track your account's performance over time.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardTrades,
            title: "Your Trade Journal",
            message: "Review and manage your recorded trades.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardReports,
            title: "Performance Reports",
            message: "Review weekly and monthly trading performance.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardWithdrawals,
            title: "Withdrawals & Expenses",
            message: "Track payouts, prop firm expenses, and business expenses.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .dashboardCalendar,
            title: "Trading Calendar",
            message: "Review your trading performance day by day.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .mainTabFeed,
            title: "Feed tab — Trading Community",
            message: "Connect with traders and discover shared trades, posts, and clips.",
            surface: .dashboard
        ),
        ContextualTourStep(
            target: .feedContentFilters,
            title: "Feed Filters",
            message: "Choose which types of content appear in your feed.",
            surface: .feed
        ),
        ContextualTourStep(
            target: .feedTradeRooms,
            title: "Trade Rooms",
            message: "Join trading communities, voice chats, and live streams.",
            surface: .feed
        ),
        ContextualTourStep(
            target: .feedExplore,
            title: "Explore",
            message: "Discover traders, content, and leaderboards.",
            surface: .feed
        ),
        ContextualTourStep(
            target: .mainTabCreate,
            title: "Create tab — Create & Journal",
            message: "Log trades, record withdrawals, and share posts, clips, and stories.",
            surface: .feed
        ),
        ContextualTourStep(
            target: .mainTabMessages,
            title: "Messages tab — Messages",
            message: "Access private messages, group conversations, and Trade Room chats.",
            surface: .feed
        ),
        ContextualTourStep(
            target: .mainTabProfile,
            title: "Profile tab — Your Profile",
            message: "Access your personal trading profile.",
            surface: .feed
        ),
        ContextualTourStep(
            target: .profileIdentity,
            title: "Profile header — Your Trading Identity",
            message: "Display your bio, trading statistics, and social information.",
            surface: .profile
        ),
        ContextualTourStep(
            target: .profileTradeRoom,
            title: "Your Trade Room",
            message: "Build your own trading community.",
            surface: .profile
        ),
        ContextualTourStep(
            target: .profileSettings,
            title: "Settings button — Settings",
            message: "Manage your accounts, preferences, and TradeTraxs experience.",
            surface: .profile
        ),
        ContextualTourStep(
            target: .settingsAppearance,
            title: "Appearance",
            message: "Choose System, Light, or Dark mode.",
            surface: .settings
        ),
        ContextualTourStep(
            target: .settingsTradingRules,
            title: "Trading Rules",
            message: "Set trading limits and measure how consistently you follow them.",
            surface: .settings
        ),
        ContextualTourStep(
            title: "Trading Rules",
            message: "Would you like to configure your trading rules now? Replay this walkthrough anytime in Settings.",
            surface: .settings,
            role: .tradingRulesPrompt
        ),
    ]
}
