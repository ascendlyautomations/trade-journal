import Foundation
import LiveKit

struct BroadcastProgramVideoPlaceholderPresentation: Equatable {
    var title: String
    var showsSpinner: Bool
    var accessibilityLabel: String
}

enum BroadcastProgramVideoConnectionPhase: Equatable {
    case connected
    case connecting
    case reconnecting
    case disconnected
    case other
}

/// Viewer / manage-stream program surface while LiveKit is up but video is not ready.
enum BroadcastProgramVideoPresentation {
    static func connectionPhase(from state: ConnectionState) -> BroadcastProgramVideoConnectionPhase {
        switch state {
        case .connected: return .connected
        case .connecting: return .connecting
        case .reconnecting: return .reconnecting
        case .disconnected: return .disconnected
        case .disconnecting: return .other
        @unknown default: return .other
        }
    }

    static func resolvePlaceholder(
        showsProgramVideoSurface: Bool,
        isLive: Bool,
        hasDisplayableVideo: Bool,
        connection: BroadcastProgramVideoConnectionPhase,
        isJoining: Bool,
        hostConnected: Bool?,
        primaryMediaPublisherConnected: Bool?,
        broadcastSourceIsObs: Bool,
        videoWasDisplayedBefore: Bool
    ) -> BroadcastProgramVideoPlaceholderPresentation? {
        guard showsProgramVideoSurface else { return nil }
        guard isLive else { return nil }
        guard !hasDisplayableVideo else { return nil }

        if connection == .connecting || connection == .reconnecting || isJoining {
            return preparingPresentation
        }

        if hostConnected == false {
            return BroadcastProgramVideoPlaceholderPresentation(
                title: "Waiting for broadcaster…",
                showsSpinner: true,
                accessibilityLabel: "Waiting for broadcaster"
            )
        }

        if broadcastSourceIsObs, primaryMediaPublisherConnected == false {
            return preparingPresentation
        }

        if videoWasDisplayedBefore {
            return BroadcastProgramVideoPlaceholderPresentation(
                title: "Waiting for video…",
                showsSpinner: true,
                accessibilityLabel: "Waiting for video"
            )
        }

        return preparingPresentation
    }

    private static let preparingPresentation = BroadcastProgramVideoPlaceholderPresentation(
        title: "Preparing Stream...",
        showsSpinner: true,
        accessibilityLabel: "Preparing stream"
    )
}