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

nonisolated enum FeedLoadTrace {
    nonisolated(unsafe) private static var requestCounter: UInt64 = 0

    static func log(
        trigger: FeedLoadTrigger,
        generation: UInt64,
        scope: FeedScope,
        filter: FeedContentFilter,
        caller: String,
        cacheSource: String,
        networkRequired: Bool
    ) {
        requestCounter &+= 1
        print(
            """
            [FeedLoadTrace] trigger=\(trigger.rawValue) generation=\(generation) scope=\(scope.rawValue) filter=\(filter.rpcValue) caller=\(caller) cacheSource=\(cacheSource) networkRequired=\(networkRequired) requestID=\(requestCounter)
            """
        )
    }

    static func resetForTesting() {
        requestCounter = 0
    }
}
#else
nonisolated enum FeedLoadProbe {
    static func record(_ trigger: FeedLoadTrigger) {}
}

nonisolated enum FeedLoadTrace {
    static func log(
        trigger: FeedLoadTrigger,
        generation: UInt64,
        scope: FeedScope,
        filter: FeedContentFilter,
        caller: String,
        cacheSource: String,
        networkRequired: Bool
    ) {}
}
#endif
