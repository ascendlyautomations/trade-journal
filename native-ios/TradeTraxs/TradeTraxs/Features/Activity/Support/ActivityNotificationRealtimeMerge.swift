import Foundation

nonisolated enum ActivityNotificationRealtimeMerge {
    /// Merge from postgres `notifications` row payload (no join).
    static func notification(from recordPayload: Data) -> ActivityNotification? {
        guard let dto = PostgresChangeRecordCodec.decode(NotificationDTO.Item.self, from: recordPayload)
        else { return nil }
        return DefaultNotificationRepository.mapNotification(dto)
    }

    /// When presentation fields are insufficient for inbox rendering.
    static func needsRowHydration(_ notification: ActivityNotification) -> Bool {
        guard notification.kind.isInboxType else { return false }
        switch notification.kind {
        case .follow, .followRequest, .followRequestAccepted:
            return notification.actorProfileID == nil
        default:
            return false
        }
    }
}
