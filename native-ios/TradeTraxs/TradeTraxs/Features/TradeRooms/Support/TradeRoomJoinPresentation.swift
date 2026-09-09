import Foundation

/// Viewer join-request row status from `room_join_requests.status`.
nonisolated enum TradeRoomJoinRequestState: String, Codable, Sendable, Hashable {
    case pending
    case approved
    case rejected

    static func parse(_ raw: String?) -> TradeRoomJoinRequestState? {
        guard let raw else { return nil }
        return TradeRoomJoinRequestState(rawValue: raw.lowercased())
    }
}

/// Authoritative + optimistic join button phase for discoverable rooms.
nonisolated enum TradeRoomDiscoveryJoinState: Equatable, Sendable {
    case idle
    case joining
    case joined
    case requesting
    case requested
}

nonisolated struct RoomJoinRequestRecord: Hashable, Sendable, Identifiable {
    var id: String
    var roomID: RoomID
    var profileID: ProfileID
    var status: TradeRoomJoinRequestState
    var createdAt: Date?
    var profile: Profile?
}

nonisolated enum TradeRoomJoinRequestResolution: String, Sendable {
    case approve
    case decline
}

/// Shared join/request presentation — one source of truth for all discovery surfaces.
nonisolated enum TradeRoomJoinPresentation {
    /// Discovery row status — Your Rooms shows Owner/Joined; Suggested/Popular keep join CTAs.
    static func discoveryStatusTitle(
        isYourRoomsContext: Bool,
        isOwner: Bool,
        joinPolicy: TradeRoomJoinPolicy,
        state: TradeRoomDiscoveryJoinState
    ) -> String {
        if isYourRoomsContext {
            if isOwner { return "Owner" }
            switch state {
            case .joined, .requested:
                return "Joined"
            default:
                break
            }
        }
        return buttonTitle(joinPolicy: joinPolicy, state: state)
    }

    static func buttonTitle(
        joinPolicy: TradeRoomJoinPolicy,
        state: TradeRoomDiscoveryJoinState
    ) -> String {
        switch state {
        case .joined:
            return "Joined"
        case .requested:
            return joinPolicy == .approval ? "Requested" : "Joined"
        case .joining:
            return joinPolicy == .approval ? "Request" : "Join"
        case .requesting:
            return "Request"
        case .idle:
            return joinPolicy == .approval ? "Request" : "Join"
        }
    }

    static func previewButtonTitle(
        joinPolicy: TradeRoomJoinPolicy,
        state: TradeRoomDiscoveryJoinState
    ) -> String {
        switch state {
        case .requested, .requesting:
            return "Request Pending"
        default:
            return buttonTitle(joinPolicy: joinPolicy, state: state)
        }
    }

    static func isInteractive(_ state: TradeRoomDiscoveryJoinState) -> Bool {
        switch state {
        case .idle:
            return true
        case .joining, .requesting, .joined, .requested:
            return false
        }
    }

    static func showsButton(
        isOwner: Bool,
        state: TradeRoomDiscoveryJoinState
    ) -> Bool {
        if isOwner { return true }
        switch state {
        case .idle, .joining, .requesting, .joined, .requested:
            return true
        }
    }

    static func resolveState(
        isJoined: Bool,
        joinPolicy: TradeRoomJoinPolicy,
        joinRequestState: TradeRoomJoinRequestState?,
        mutationOverride: TradeRoomDiscoveryJoinState?
    ) -> TradeRoomDiscoveryJoinState {
        if let mutationOverride {
            switch mutationOverride {
            case .joining, .requesting:
                return mutationOverride
            case .joined, .requested:
                return mutationOverride
            case .idle:
                break
            }
        }
        if isJoined { return .joined }
        if joinRequestState == .pending { return .requested }
        return .idle
    }

    static func mutationPhase(for action: TradeRoomJoinAction) -> TradeRoomDiscoveryJoinState {
        switch action {
        case .directJoin: return .joining
        case .requestJoin: return .requesting
        }
    }

    static func successPhase(for action: TradeRoomJoinAction) -> TradeRoomDiscoveryJoinState {
        switch action {
        case .directJoin: return .joined
        case .requestJoin: return .requested
        }
    }

    static func action(for joinPolicy: TradeRoomJoinPolicy) -> TradeRoomJoinAction {
        joinPolicy == .approval ? .requestJoin : .directJoin
    }
}

nonisolated enum TradeRoomJoinAction: Sendable {
    case directJoin
    case requestJoin
}
