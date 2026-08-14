import Foundation
import UserNotifications

/// Foreground presentation policy — Instagram / Discord style.
///
/// - Always refresh badge + in-app Activity
/// - High-priority types may show a banner while active
/// - Likes / routine social stay silent in foreground (no spam)
enum PushNotificationPresentationPolicy {
    enum Priority: Equatable {
        case high
        case normal
        case silent
    }

    static func priority(for destination: NotificationDestination) -> Priority {
        let type = (destination.rawUserInfo["type"] ?? "").lowercased()
        switch destination.category {
        case .directMessage, .roomMention, .followRequest:
            return .high
        case .roomMessage:
            // Mentions already categorized; room replies stay high when flagged.
            if type.contains("reply") || destination.rawUserInfo["is_reply"] == "true" {
                return .high
            }
            return .normal
        case .tradingReport:
            return .normal
        case .activity:
            switch type {
            case "follow", "follow_request_accepted", "comment":
                if destination.rawUserInfo["comment_kind"] == "reply"
                    || destination.rawUserInfo["comment_kind"] == "mention"
                    || destination.rawUserInfo["is_reply"] == "true"
                    || destination.rawUserInfo["is_mention"] == "true"
                {
                    return .high
                }
                return type == "follow" ? .normal : .silent
            case "like", "like_batch", "like_milestone", "room_join":
                return .silent
            default:
                return .normal
            }
        case .unknown:
            return .normal
        }
    }

    static func foregroundOptions(
        for destination: NotificationDestination,
        bannersEnabled: Bool
    ) -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = [.list]
        guard bannersEnabled else { return options }

        switch priority(for: destination) {
        case .high:
            options.insert(.banner)
            options.insert(.sound)
        case .normal:
            options.insert(.banner)
        case .silent:
            break
        }
        return options
    }
}
