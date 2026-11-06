import LiveKit

/// When the persistent voice bar (and leave control) should remain visible.
enum LiveVoiceChromeVisibility {
    static func shouldShowBar(
        hasSession: Bool,
        connectionState: ConnectionState,
        isLeaving: Bool,
        isJoining: Bool
    ) -> Bool {
        if isLeaving || isJoining { return true }
        guard hasSession else { return false }
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
