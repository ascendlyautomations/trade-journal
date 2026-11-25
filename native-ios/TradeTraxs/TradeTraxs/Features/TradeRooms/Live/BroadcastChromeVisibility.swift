import LiveKit

enum BroadcastChromeVisibility {
    /// OBS hosts use the floating mini-player when minimized; no tab-bar “You're streaming” banner.
    static func shouldShowObsHostBar(
        hasHostBarSession: Bool,
        isLivePublic: Bool,
        isManageSheetPresented: Bool
    ) -> Bool {
        _ = (hasHostBarSession, isLivePublic, isManageSheetPresented)
        return false
    }

    static func shouldShowBar(
        isWatching: Bool,
        connectionState: ConnectionState,
        isBusy: Bool,
        hasWatchSession: Bool
    ) -> Bool {
        if isBusy, hasWatchSession { return true }
        guard isWatching else { return false }
        switch connectionState {
        case .disconnected:
            return false
        case .connecting, .connected, .reconnecting, .disconnecting:
            return true
        @unknown default:
            return true
        }
    }
}
