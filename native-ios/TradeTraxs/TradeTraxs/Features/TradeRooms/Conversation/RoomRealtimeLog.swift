import Foundation
import os

#if DEBUG
enum RoomRealtimeLog {
    private static let logger = AppLog.realtime

    static func subscribed(roomID: RoomID, reason: String) {
        logger.debug(
            "[RoomRealtime] subscribed roomID=\(roomID.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    static func unsubscribed(roomID: RoomID, reason: String) {
        logger.debug(
            "[RoomRealtime] unsubscribed roomID=\(roomID.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }
}
#else
enum RoomRealtimeLog {
    static func subscribed(roomID: RoomID, reason: String) {}
    static func unsubscribed(roomID: RoomID, reason: String) {}
}
#endif
