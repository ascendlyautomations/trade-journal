import Foundation

nonisolated enum RoomMemberCountRealtimeSemantics {
    /// Active membership delta from a `room_members` postgres row (+1 join, -1 leave).
    static func membershipDelta(
        kind: MessageRealtimeSignal.Kind,
        record: [String: Any]?,
        oldRecord: [String: Any]?
    ) -> Int? {
        switch kind {
        case .insert:
            guard isActiveMember(record) else { return nil }
            return 1
        case .delete:
            guard isActiveMember(oldRecord ?? record) else { return nil }
            return -1
        case .update:
            let wasActive = isActiveMember(oldRecord)
            let isActive = isActiveMember(record)
            if wasActive == isActive { return nil }
            return isActive ? 1 : -1
        }
    }

    private static func isActiveMember(_ record: [String: Any]?) -> Bool {
        guard let record, record["room_id"] != nil else { return false }
        if record["left_at"] is NSNull { return true }
        if let leftAt = record["left_at"] as? String { return leftAt.isEmpty }
        return true
    }
}
