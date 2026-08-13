import Foundation

/// Display copy for Activity rows — mirrors web `lib/notificationsDisplay.ts` semantics.
nonisolated enum ActivityNotificationFormatting {
    static func actorDisplayName(
        profile: Profile?,
        fallback: String = "Someone"
    ) -> String {
        if let name = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let username = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }
        return fallback
    }

    static func engagementTargetLabel(for notification: ActivityNotification) -> String {
        if notification.commentID != nil { return "comment" }
        if notification.reelID != nil { return "clip" }
        if notification.achievementPostID != nil { return "achievement" }
        if notification.postID != nil || notification.profilePostID != nil { return "post" }
        if notification.tradeID != nil { return "trade" }
        return "post"
    }

    static func primaryText(
        for notification: ActivityNotification,
        actorName: String
    ) -> String {
        switch notification.kind {
        case .like:
            return "\(actorName) liked your \(engagementTargetLabel(for: notification))"
        case .comment:
            let preview = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if preview.isEmpty {
                return "\(actorName) commented on your \(engagementTargetLabel(for: notification))"
            }
            let clipped = preview.count > 80 ? String(preview.prefix(77)) + "…" : preview
            return "\(actorName) commented: \"\(clipped)\""
        case .follow:
            return "\(actorName) started following you"
        case .followRequest:
            return "\(actorName) requested to follow you"
        case .followRequestAccepted:
            return "\(actorName) accepted your follow request"
        case .roomJoin:
            if let room = notification.roomName?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty {
                return "\(actorName) joined \(room)"
            }
            return "\(actorName) joined your room"
        case .roomMention:
            let roomLabel = roomChannelTitle(
                roomName: notification.roomName,
                sectionName: notification.sectionName
            )
            if let preview = notification.messagePreview?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty
            {
                let clipped = preview.count > 60 ? String(preview.prefix(57)) + "…" : preview
                return "\(actorName) mentioned you in \(roomLabel): \"\(clipped)\""
            }
            return "\(actorName) mentioned you in \(roomLabel)"
        case .affiliateReferral:
            if !notification.title.isEmpty, notification.title != notification.kind.rawValue {
                return notification.title
            }
            return "New affiliate referral"
        case .affiliateCommissionEarned:
            if !notification.title.isEmpty, notification.title != notification.kind.rawValue {
                return notification.title
            }
            return "Affiliate commission earned"
        case .tradingReport:
            if !notification.title.isEmpty, notification.title != notification.kind.rawValue {
                return notification.title
            }
            return "Your trading report is ready"
        case .message, .system:
            if !notification.title.isEmpty {
                return notification.title
            }
            return notification.body.isEmpty ? "Activity update" : notification.body
        }
    }

    static func secondaryText(for notification: ActivityNotification) -> String? {
        switch notification.kind {
        case .affiliateReferral, .affiliateCommissionEarned, .tradingReport:
            let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        default:
            return nil
        }
    }

    static func roomChannelTitle(roomName: String?, sectionName: String?) -> String {
        let room = roomName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawSection = sectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let section: String = {
            guard !rawSection.isEmpty else { return "" }
            if rawSection.hasPrefix("#") { return rawSection }
            return "#\(rawSection)"
        }()
        if !room.isEmpty, !section.isEmpty { return "\(room) • \(section)" }
        if !room.isEmpty { return room }
        if !section.isEmpty { return section }
        return "Trade Room"
    }

    static func relativeTimestamp(_ date: Date, now: Date = .now) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3_600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h" }
        if interval < 86_400 * 7 { return "\(Int(interval / 86_400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
