import Foundation

/// Shared messaging domain snapshot — single source of truth for Messages + Trade Rooms homes.
///
/// ``MessagingDomain`` owns mutation. Screen ViewModels present this state; child views render only.
/// Thread screens keep independent pagination state and patch the inbox store for badges/previews.
struct MessagingState: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var phase: Phase = .idle
    var viewerID: ProfileID?
    var didBootstrap = false
    var isRefreshing = false

    /// Full inbox (conversations + rooms) hydrated at least once this session.
    var hasLoadedConversations = false
    /// Member rooms hydrated (Messages and/or Trade Rooms).
    var hasLoadedRooms = false

    var errorMessage: String?
    var lastUpdated: Date?
}

extension MessagingState: ScreenStateModeling {
    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed(let message): return .failed(message)
        }
    }

    var screenErrorMessage: String? { errorMessage }

    var pagination: ScreenPaginationSnapshot { .none }
}
