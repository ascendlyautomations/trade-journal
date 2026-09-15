import Foundation

/// Channel post permission — maps to `room_sections.allow_members_chat` (boolean).
enum RoomChannelPostingPermission: CaseIterable, Hashable {
    case everyone
    case ownersOnly

    static func from(allowMembersChat: Bool) -> RoomChannelPostingPermission {
        allowMembersChat ? .everyone : .ownersOnly
    }

    var allowMembersChat: Bool {
        switch self {
        case .everyone: return true
        case .ownersOnly: return false
        }
    }

    var summaryLabel: String {
        switch self {
        case .everyone: return "Everyone"
        case .ownersOnly: return "Owners Only"
        }
    }
}
