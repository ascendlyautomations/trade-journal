import Foundation

enum LiveBroadcastDeepLinkHandler {
    @MainActor
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "tradetraxs" else { return false }
        guard url.host?.lowercased() == "live-broadcast" else { return false }

        let path = url.path.lowercased()
        let roomQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "room" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            let coordinator = RoomBroadcastCoordinator.shared
            switch path {
            case "/return":
                if let roomQuery, !roomQuery.isEmpty {
                    let roomID = RoomID(roomQuery)
                    let title = coordinator.watchSession?.roomTitle ?? "Trade Room"
                    if coordinator.isWatchingRoom(roomID) {
                        coordinator.presentViewer()
                    } else {
                        await coordinator.watch(roomID: roomID, roomTitle: title)
                        coordinator.presentViewer()
                    }
                } else if coordinator.isWatching {
                    coordinator.presentViewer()
                }
            case "/leave":
                await coordinator.leaveWatch()
            default:
                break
            }
        }
        return true
    }
}
