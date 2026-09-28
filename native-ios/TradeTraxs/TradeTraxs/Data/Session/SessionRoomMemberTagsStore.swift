import Foundation
import Observation

/// Session cache for room member tags + assignments (display + manage screens).
@Observable
@MainActor
final class SessionRoomMemberTagsStore {
    static let shared = SessionRoomMemberTagsStore()

    private var tagsByRoom: [RoomID: [RoomMemberTag]] = [:]
    private var assignmentsByRoom: [RoomID: [RoomMemberTagAssignment]] = [:]

    func tags(for roomID: RoomID) -> [RoomMemberTag] {
        tagsByRoom[roomID] ?? []
    }

    func assignments(for roomID: RoomID) -> [RoomMemberTagAssignment] {
        assignmentsByRoom[roomID] ?? []
    }

    func tags(for profileID: ProfileID, roomID: RoomID) -> [RoomMemberTag] {
        let tagByID = Dictionary(uniqueKeysWithValues: tags(for: roomID).map { ($0.id, $0) })
        return assignments(for: roomID)
            .filter { $0.profileID == profileID }
            .compactMap { tagByID[$0.tagID] }
    }

    func replace(roomID: RoomID, tags: [RoomMemberTag], assignments: [RoomMemberTagAssignment]) {
        tagsByRoom[roomID] = tags
        assignmentsByRoom[roomID] = assignments
    }

    func replaceTags(_ tags: [RoomMemberTag], roomID: RoomID) {
        tagsByRoom[roomID] = tags
    }

    func replaceAssignments(_ assignments: [RoomMemberTagAssignment], roomID: RoomID) {
        assignmentsByRoom[roomID] = assignments
    }

    func invalidate(roomID: RoomID? = nil) {
        if let roomID {
            tagsByRoom.removeValue(forKey: roomID)
            assignmentsByRoom.removeValue(forKey: roomID)
        } else {
            tagsByRoom.removeAll()
            assignmentsByRoom.removeAll()
        }
    }
}

extension SessionRoomMemberTagsStore {
    /// Loads tags + assignments only — never seeds preset tags (manager-only).
    func hydrate(roomID: RoomID, repository: any RoomManagementRepository) async throws {
        try await hydrateTags(roomID: roomID, repository: repository)
    }

    /// Tags + assignments only — does not seed preset tags.
    func hydrateTags(roomID: RoomID, repository: any RoomManagementRepository) async throws {
        async let tags = repository.memberTags(roomID: roomID)
        async let assignments = repository.memberTagAssignments(roomID: roomID)
        replace(
            roomID: roomID,
            tags: try await tags,
            assignments: try await assignments
        )
    }

    /// Manager-only preset seed (owner or platform admin on official rooms).
    func ensureDefaultTagsIfCanManage(
        roomID: RoomID,
        canManage: Bool,
        repository: any RoomManagementRepository
    ) async -> String {
        guard canManage else { return "skipped-not-manager" }
        do {
            try await repository.ensureDefaultMemberTags(roomID: roomID)
            return "204"
        } catch {
            return "failed:\(PostgRESTValidationDetail.safeField(error.localizedDescription, max: 96))"
        }
    }
}
