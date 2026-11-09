import LiveKit

enum BroadcastChromeVisibility {
    static func shouldShowObsHostBar(
        hasHostBarSession: Bool,
        isLivePublic: Bool,
        isManageSheetPresented: Bool
    ) -> Bool {
        guard hasHostBarSession, isLivePublic else { return false }
        return !isManageSheetPresented
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
