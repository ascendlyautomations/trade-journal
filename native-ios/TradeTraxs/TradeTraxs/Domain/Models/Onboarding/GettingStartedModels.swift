import Foundation

/// Shared checklist signals — mirrors `GettingStartedChecklistSignals` on web.
nonisolated struct GettingStartedSignals: Sendable, Equatable {
    var onboardingCompleted: Bool
    var hasSeenGettingStartedIntro: Bool
    var hasSeenOnboardingCompletePopup: Bool
    var tradeCount: Int
    var profilePostCount: Int
    var followCount: Int
    var hasEverJoinedOtherRoom: Bool
    var hasPublicTrade: Bool
    var firstPrivateTradeID: TradeID?

    static let empty = GettingStartedSignals(
        onboardingCompleted: false,
        hasSeenGettingStartedIntro: false,
        hasSeenOnboardingCompletePopup: false,
        tradeCount: 0,
        profilePostCount: 0,
        followCount: 0,
        hasEverJoinedOtherRoom: false,
        hasPublicTrade: false,
        firstPrivateTradeID: nil
    )
}

nonisolated enum GettingStartedTaskID: String, CaseIterable, Sendable, Identifiable {
    case profile
    case trade
    case follow
    case room
    case post
    case publicTrade = "public"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .profile: return "Complete your profile"
        case .trade: return "Add your first trade"
        case .follow: return "Follow another trader"
        case .room: return "Join a trade room"
        case .publicTrade: return "Make your first trade public"
        case .post: return "Create your first post"
        }
    }
}

nonisolated struct GettingStartedTask: Sendable, Equatable, Identifiable {
    var id: GettingStartedTaskID
    var label: String
    var isComplete: Bool
}

nonisolated struct GettingStartedProgress: Sendable, Equatable {
    static let totalCount = 6

    var tasks: [GettingStartedTask]
    var completedCount: Int
    var totalCount: Int
    var allComplete: Bool

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

/// RPC wire shape for `rpc_v1_getting_started_signals`.
nonisolated struct GettingStartedSignalsWire: Codable, Sendable {
    var onboarding_completed: Bool?
    var has_seen_getting_started_intro: Bool?
    var has_seen_onboarding_complete_popup: Bool?
    var trade_count: Int?
    var profile_post_count: Int?
    var follow_count: Int?
    var has_ever_joined_other_room: Bool?
    var has_public_trade: Bool?
    var first_private_trade_id: String?
}

nonisolated enum GettingStartedSignalsDecoder {
    static func decode(_ data: Data) throws -> GettingStartedSignals {
        let wire = try JSONDecoder().decode(GettingStartedSignalsWire.self, from: data)
        return map(wire)
    }

    static func map(_ wire: GettingStartedSignalsWire) -> GettingStartedSignals {
        GettingStartedSignals(
            onboardingCompleted: wire.onboarding_completed == true,
            hasSeenGettingStartedIntro: wire.has_seen_getting_started_intro == true,
            hasSeenOnboardingCompletePopup: wire.has_seen_onboarding_complete_popup == true,
            tradeCount: max(0, wire.trade_count ?? 0),
            profilePostCount: max(0, wire.profile_post_count ?? 0),
            followCount: max(0, wire.follow_count ?? 0),
            hasEverJoinedOtherRoom: wire.has_ever_joined_other_room == true,
            hasPublicTrade: wire.has_public_trade == true,
            firstPrivateTradeID: wire.first_private_trade_id.flatMap { TradeID($0) }
        )
    }
}
