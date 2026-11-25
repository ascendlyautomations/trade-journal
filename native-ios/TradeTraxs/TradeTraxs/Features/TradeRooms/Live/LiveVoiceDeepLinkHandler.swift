import Foundation

enum LiveVoiceDeepLinkHandler {
    @MainActor
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "tradetraxs" else { return false }
        guard url.host?.lowercased() == "live-voice" else { return false }

        let path = url.path.lowercased()
        Task { @MainActor in
            switch path {
            case "/leave":
                await RoomLiveVoiceCoordinator.shared.leave()
            case "/mute":
                await RoomLiveVoiceCoordinator.shared.toggleMute()
            default:
                break
            }
        }
        return true
    }
}
