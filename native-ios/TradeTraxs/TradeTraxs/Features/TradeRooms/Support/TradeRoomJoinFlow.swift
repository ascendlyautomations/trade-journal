import Foundation

/// Web `attemptTradeRoomJoin` parity — ban check, approval requests, approved → `room_members` insert.
@MainActor
enum TradeRoomJoinFlow {
    enum Result: Sendable, Equatable {
        case joined(membership: RoomMembership, alreadyMember: Bool)
        case requested(status: TradeRoomJoinRequestState)
        case pending
        case banned
        case error(String)
    }

    static func attemptJoin(
        room: ExploreRoomSuggestion,
        viewerID: ProfileID,
        rooms: any RoomRepository
    ) async -> Result {
        await attemptJoin(
            roomID: room.id,
            joinPolicy: room.joinPolicy,
            isPrivate: false,
            viewerID: viewerID,
            rooms: rooms
        )
    }

    static func attemptJoin(
        roomID: RoomID,
        joinPolicy: TradeRoomJoinPolicy,
        isPrivate: Bool,
        viewerID: ProfileID,
        rooms: any RoomRepository
    ) async -> Result {
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            let stub = RoomMembership(
                roomID: roomID,
                profileID: viewerID,
                role: .member,
                joinedAt: .now,
                notificationsEnabled: true
            )
            return .joined(membership: stub, alreadyMember: false)
        }

        if (try? await rooms.isViewerBanned(from: roomID, profileID: viewerID)) == true {
            return .banned
        }

        let requiresApproval = TradeRoomJoinPresentation.requiresJoinApproval(
            isPrivate: isPrivate,
            joinPolicy: joinPolicy
        )

        if requiresApproval {
            if let existing = try? await rooms.viewerJoinRequest(roomID: roomID) {
                if existing == .pending {
                    return .pending
                }
                if existing == .approved {
                    return await completeDirectJoin(roomID: roomID, viewerID: viewerID, rooms: rooms)
                }
            }

            do {
                let status = try await rooms.requestJoin(roomID: roomID)
                if status == .approved {
                    return await completeDirectJoin(roomID: roomID, viewerID: viewerID, rooms: rooms)
                }
                return .requested(status: status)
            } catch {
                return .error(ProfileSectionSupport.message(for: error))
            }
        }

        return await completeDirectJoin(roomID: roomID, viewerID: viewerID, rooms: rooms)
    }

    private static func completeDirectJoin(
        roomID: RoomID,
        viewerID: ProfileID,
        rooms: any RoomRepository
    ) async -> Result {
        do {
            let hadRow = (try? await rooms.membership(roomID: roomID, profileID: viewerID)) != nil
            let membership = try await rooms.join(roomID: roomID, profileID: viewerID)
            return .joined(membership: membership, alreadyMember: hadRow)
        } catch {
            return .error(ProfileSectionSupport.message(for: error))
        }
    }
}