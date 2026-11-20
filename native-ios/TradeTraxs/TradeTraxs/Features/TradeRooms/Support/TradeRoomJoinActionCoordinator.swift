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
        TradeRoomMembershipStore.shared.isJoined(roomID)
            || inboxStore.rooms.contains(where: { $0.id == roomID })
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
        if (try? await rooms.membership(roomID: room.id, profileID: viewerID)) != nil {
            mutationStates[room.id] = .joined
            return .joined
        }
        _ = await TradeRoomStaleMembershipReconciler.reconcileOptimisticJoinState(
            roomID: room.id,
            viewerID: viewerID,
            rooms: rooms,
            inboxStore: store
        )
        let joined = isJoined(roomID: room.id, inboxStore: store)
        let current = effectiveState(for: room, isJoined: joined)
        guard TradeRoomJoinPresentation.isInteractive(current) else { return current }

        mutationStates[room.id] = TradeRoomJoinPresentation.mutationPhase(
            for: TradeRoomJoinPresentation.action(for: room.joinPolicy)
        )
        lastErrorMessage = nil

        let outcome = await TradeRoomJoinFlow.attemptJoin(room: room, viewerID: viewerID, rooms: rooms)

        switch outcome {
        case .joined(let membership, _):
            mutationStates[room.id] = .joined
            TradeRoomMembershipSync.applyJoined(
                suggestion: room,
                viewerID: viewerID,
                inboxStore: store,
                confirmedMembership: membership
            )
            await onDirectJoinSucceeded?()
            ExperienceHaptics.play(.success)
            return .joined
        case .requested:
            mutationStates[room.id] = .requested
            ExperienceHaptics.play(.success)
            return .requested
        case .pending:
            mutationStates[room.id] = .requested
            return .requested
        case .banned:
            mutationStates.removeValue(forKey: room.id)
            lastErrorMessage = "You cannot join this room."
            ExperienceHaptics.play(.warning)
            return .idle
        case .error(let message):
            if isAlreadyPendingError(message: message) {
                mutationStates[room.id] = .requested
                return .requested
            }
            mutationStates.removeValue(forKey: room.id)
            lastErrorMessage = message
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
        await performJoinAction(
            room: room,
            viewerID: viewerID,
            rooms: rooms,
            inboxStore: inboxStore
        )
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

    private func isAlreadyPendingError(message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("pending") || lowered.contains("already")
    }

}