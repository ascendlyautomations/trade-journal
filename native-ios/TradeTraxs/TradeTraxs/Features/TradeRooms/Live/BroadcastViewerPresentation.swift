import Foundation

/// Viewer livestream UI — one LiveKit session; presentation does not connect/disconnect.
enum BroadcastViewerPresentation: String, Equatable, Sendable {
    case off
    case mini
    case expanded
}

/// Persisted snap corner for the floating mini-player (in-app, not PiP).
enum BroadcastMiniPlayerCorner: String, CaseIterable, Codable, Sendable, Equatable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    static let defaultCorner: BroadcastMiniPlayerCorner = .bottomTrailing
}