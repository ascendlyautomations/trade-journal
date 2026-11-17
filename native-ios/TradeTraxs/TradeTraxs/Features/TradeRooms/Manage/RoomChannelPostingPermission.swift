import Foundation

/// Channel post permission — maps to `room_sections.allow_members_chat` (boolean).
enum RoomChannelPostingPermission: CaseIterable, Hashable {
    case everyone
    case moderatorsOnly

    static func from(allowMembersChat: Bool) -> RoomChannelPostingPermission {
        allowMembersChat ? .everyone : .moderatorsOnly
    }

    var allowMembersChat: Bool {
        switch self {
        case .everyone: return true
        case .moderatorsOnly: return false
        }
    }

    var summaryLabel: String {
        switch self {
        case .everyone: return "Everyone"
        case .moderatorsOnly: return "Moderators Only"
        }
    }
}