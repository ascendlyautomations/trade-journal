import Foundation

enum TradeRoomOwnerProfileLoader {
    @MainActor
    static func loadOwnerProfile(
        for room: TradeRoom,
        detailCache: DetailPresentationCache,
        profiles: any ProfileRepository
    ) async -> Profile? {
        if !ProfileIDQueryPolicy.isQueryable(room.ownerProfileID) {
            let system = TradeRoomOfficialOwnerPresentation.systemOwnerProfile(roomID: room.id)
            detailCache.seed(system)
            return system
        }
        if let cached = detailCache.profile(id: room.ownerProfileID) {
            return cached
        }
        return try? await SessionProfileStore.shared.profiles(
            ids: [room.ownerProfileID],
            detailCache: detailCache,
            repository: profiles
        ).first
    }
}
