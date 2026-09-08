import Foundation

/// Why a Feed bootstrap was requested — one log line per load in DEBUG builds.
nonisolated enum FeedLoadTrigger: String, Sendable {
    case initial
    case pullRefresh
    case realtime
    case navigationReturn
    case sessionChanged
    case followingChanged
    case scopeChanged
    case contentFilterChanged
    case contentMutation
    case journalMutation
    case pagination
}

#if DEBUG
nonisolated enum FeedLoadProbe {
    nonisolated(unsafe) private(set) static var recordedTriggers: [FeedLoadTrigger] = []

    static func record(_ trigger: FeedLoadTrigger) {
        recordedTriggers.append(trigger)
        print("[Feed] feed.load trigger=\(trigger.rawValue)")
    }

    static func resetForTesting() {
        recordedTriggers = []
    }
}
#else
nonisolated enum FeedLoadProbe {
    static func record(_ trigger: FeedLoadTrigger) {}
}
#endif
