import Foundation

/// Shared Trade Room management authorization, mirrors backend `can_manage_trade_room`.
enum TradeRoomManagementPermission {
    /// `entitlement.flags.is_admin` from session bootstrap (`admin_users` on the server).
    @MainActor
    static var isPlatformAdmin: Bool {
        SessionBootstrapStore.shared.isPlatformAdmin
    }

    static func isViewerOwner(room: TradeRoom, viewerID: ProfileID?) -> Bool {
        guard let viewerID else { return false }
        return room.ownerProfileID == viewerID
    }

    static func canManage(
        room: TradeRoom,
        viewerID: ProfileID?,
        isPlatformAdmin: Bool
    ) -> Bool {
        guard let viewerID else { return false }
        if isViewerOwner(room: room, viewerID: viewerID) { return true }
        return isPlatformAdmin && room.roomKind == .official
    }

    @MainActor
    static func canManage(room: TradeRoom, viewerID: ProfileID?) -> Bool {
        canManage(room: room, viewerID: viewerID, isPlatformAdmin: isPlatformAdmin)
    }
}
