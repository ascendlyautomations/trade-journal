import Foundation

/// Shared Trade Room management authorization — mirrors backend `can_manage_trade_room`.
enum TradeRoomManagementPermission {
    /// `entitlement.flags.is_admin` from session bootstrap (`admin_users` on the server).
    @MainActor
    static var isPlatformAdmin: Bool {
        SessionBootstrapStore.shared.isPlatformAdmin
    }

    static func canManage(
        room: TradeRoom,
        viewerID: ProfileID?,
        isPlatformAdmin: Bool
    ) -> Bool {
        guard let viewerID else { return false }
        if room.ownerProfileID == viewerID { return true }
        return isPlatformAdmin && room.roomKind == .official
    }

    @MainActor
    static func canManage(room: TradeRoom, viewerID: ProfileID?) -> Bool {
        canManage(room: room, viewerID: viewerID, isPlatformAdmin: isPlatformAdmin)
    }
}
