import Foundation
import Observation

/// Shared Trade Room join/request mutations + optimistic reconciliation for discovery surfaces.
@Observable
@MainActor
final class TradeRoomJoinActionCoordinator {
    static let shared = TradeRoomJoinActionCoordinator()

    private(set) var mutationStates: [RoomID: TradeRoomDiscoveryJoinState] = [:]
    private(set) var lastErrorMessage: String?

    private init() {}

    func effectiveState(
        for room: ExploreRoomSuggestion,
        isJoined: Bool
    ) -> TradeRoomDiscoveryJoinState {
        TradeRoomJoinPresentation.resolveState(
            isJoined: isJoined,
            joinPolicy: room.joinPolicy,
            joinRequestState: room.viewerJoinRequestState,
            mutationOverride: mutationStates[room.id]
        )
    }

    func isJoined(roomID: RoomID, inboxStore: MessagesInboxStore) -> Bool {
        inboxStore.rooms.contains(where: { $0.id == roomID })
    }

    @discardableResult
    func performJoinAction(
        room: ExploreRoomSuggestion,
        viewerID: ProfileID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore? = nil,
        onDirectJoinSucceeded: (() async -> Void)? = nil
    ) async -> TradeRoomDiscoveryJoinState {
        let store = inboxStore ?? MessagesInboxStore.shared
        let joined = isJoined(roomID: room.id, inboxStore: store)
        let current = effectiveState(for: room, isJoined: joined)
        guard TradeRoomJoinPresentation.isInteractive(current) else { return current }

        if room.joinPolicy == .approval {
            return await performRequest(
                room: room,
                viewerID: viewerID,
                rooms: rooms,
                inboxStore: store
            )
        }

        mutationStates[room.id] = .joining
        lastErrorMessage = nil

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || room.id.rawValue.hasPrefix("dev-") {
            mutationStates[room.id] = .joined
            ExperienceHaptics.play(.success)
            return .joined
        }

        do {
            _ = try await rooms.join(roomID: room.id, profileID: viewerID)
            mutationStates[room.id] = .joined
            SessionMemberRoomsStore.shared.invalidate(viewerID: viewerID)
            GettingStartedRefreshCenter.noteJoinedOtherTradeRoom(from: room, viewer: viewerID)
            await onDirectJoinSucceeded?()
            ExperienceHaptics.play(.success)
            return .joined
        } catch {
            mutationStates.removeValue(forKey: room.id)
            lastErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return .idle
        }
    }

    @discardableResult
    func performRequest(
        room: ExploreRoomSuggestion,
        viewerID: ProfileID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore? = nil
    ) async -> TradeRoomDiscoveryJoinState {
        let store = inboxStore ?? MessagesInboxStore.shared
        let joined = isJoined(roomID: room.id, inboxStore: store)
        let current = effectiveState(for: room, isJoined: joined)
        guard current == .idle else { return current }

        mutationStates[room.id] = .requesting
        lastErrorMessage = nil

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || room.id.rawValue.hasPrefix("dev-") {
            mutationStates[room.id] = .requested
            ExperienceHaptics.play(.success)
            return .requested
        }

        do {
            let status = try await rooms.requestJoin(roomID: room.id)
            if status == .pending || status == .approved {
                mutationStates[room.id] = .requested
                ExperienceHaptics.play(.success)
                return .requested
            }
            mutationStates.removeValue(forKey: room.id)
            return .idle
        } catch {
            if isAlreadyPendingError(error) {
                mutationStates[room.id] = .requested
                return .requested
            }
            mutationStates.removeValue(forKey: room.id)
            lastErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return .idle
        }
    }

    func patchJoined(_ roomID: RoomID) {
        mutationStates[roomID] = .joined
    }

    func patchRequested(_ roomID: RoomID) {
        mutationStates[roomID] = .requested
    }

    func clearMutation(for roomID: RoomID) {
        mutationStates.removeValue(forKey: roomID)
    }

    private func isAlreadyPendingError(_ error: Error) -> Bool {
        let message = ProfileSectionSupport.message(for: error).lowercased()
        return message.contains("pending") || message.contains("already")
    }
}
