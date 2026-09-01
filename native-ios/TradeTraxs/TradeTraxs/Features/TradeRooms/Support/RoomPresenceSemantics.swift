import Foundation

/// Web `lib/roomRealtimePresence.ts` — Realtime Trade Room presence rows.
nonisolated struct RoomPresenceWireUser: Sendable, Equatable, Hashable {
    var userID: String
    var username: String
    var avatarURL: String?
    var enteredAt: String
}

nonisolated struct RoomPresenceTrackConfig: Sendable, Equatable {
    var presenceKey: String
    var userID: String
    var username: String
    var avatarURL: String?
}

nonisolated enum RoomPresenceSemantics {
    /// Dedupe multiple device connections — newest `entered_at` wins per `user_id`.
    static func dedupeByUserID(
        _ state: [String: [RoomPresenceWireUser]]
    ) -> [RoomPresenceWireUser] {
        var byUser: [String: RoomPresenceWireUser] = [:]
        for rows in state.values {
            for row in rows where !row.userID.isEmpty {
                let existing = byUser[row.userID]
                if existing == nil || row.enteredAt > (existing?.enteredAt ?? "") {
                    byUser[row.userID] = row
                }
            }
        }
        return Array(byUser.values)
    }

    static func dedupeByUserID(
        _ state: [String: [[String: Any]]]
    ) -> [RoomPresenceWireUser] {
        var parsed: [String: [RoomPresenceWireUser]] = [:]
        for (key, metas) in state {
            parsed[key] = metas.compactMap(parseWireUser)
        }
        return dedupeByUserID(parsed)
    }

    static func parseWireUser(_ dict: [String: Any]) -> RoomPresenceWireUser? {
        guard let userID = dict["user_id"] as? String, !userID.isEmpty else { return nil }
        return RoomPresenceWireUser(
            userID: userID,
            username: dict["username"] as? String ?? "",
            avatarURL: dict["avatar_url"] as? String,
            enteredAt: dict["entered_at"] as? String ?? ""
        )
    }

    static func metas(from users: [RoomPresenceWireUser]) -> [[String: Any]] {
        users.map { user in
            var payload: [String: Any] = [
                "user_id": user.userID,
                "username": user.username,
                "entered_at": user.enteredAt,
            ]
            if let avatarURL = user.avatarURL {
                payload["avatar_url"] = avatarURL
            }
            return payload
        }
    }
}
