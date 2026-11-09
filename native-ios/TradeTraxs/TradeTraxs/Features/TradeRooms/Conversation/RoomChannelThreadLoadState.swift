import Foundation

/// Per-channel message thread load lifecycle for Trade Room conversations.
nonisolated enum RoomChannelThreadLoadState: Equatable, Sendable {
    case unloaded
    case loading
    case loadedEmpty
    case loaded
    case failed

    var isTerminal: Bool {
        switch self {
        case .loaded, .loadedEmpty, .failed:
            return true
        case .unloaded, .loading:
            return false
        }
    }

    var isDisplayReady: Bool {
        self == .loaded || self == .loadedEmpty
    }

    var hasTranscript: Bool {
        self == .loaded
    }

    init(diskIsLoaded: Bool, messageCount: Int) {
        guard diskIsLoaded else {
            self = .unloaded
            return
        }
        self = messageCount > 0 ? .loaded : .loadedEmpty
    }

    var diskIsLoaded: Bool {
        isDisplayReady
    }
}
