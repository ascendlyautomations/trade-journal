import Foundation

#if DEBUG
/// DEBUG timing for dedicated Clips pager autoplay — one log line per milestone per clip.
nonisolated enum ClipsPagerPlaybackProbe {
    nonisolated(unsafe) private static var pageActiveAt: [String: CFAbsoluteTime] = [:]
    nonisolated(unsafe) private static var loggedEvents: Set<String> = []

    static func resetForTesting() {
        pageActiveAt.removeAll()
        loggedEvents.removeAll()
    }

    static func pageBecameActive(clipID: String, index: Int?) {
        pageActiveAt[clipID] = CFAbsoluteTimeGetCurrent()
        let indexLabel = index.map(String.init) ?? "nil"
        print("[ClipsPagerPlayback] clipID=\(clipID) index=\(indexLabel) event=pageBecameActive")
    }

    static func playRequested(clipID: String) {
        logOnce(clipID: clipID, event: "playRequested") {
            let dt = dtFromActiveMs(clipID: clipID) ?? -1
            print("[ClipsPagerPlayback] clipID=\(clipID) event=playRequested dtFromActiveMs=\(dt)")
        }
    }

    static func firstFrame(clipID: String) {
        logOnce(clipID: clipID, event: "firstFrame") {
            let dt = dtFromActiveMs(clipID: clipID) ?? -1
            print("[ClipsPagerPlayback] clipID=\(clipID) event=firstFrame dtFromActiveMs=\(dt)")
        }
    }

    private static func dtFromActiveMs(clipID: String) -> Int? {
        guard let start = pageActiveAt[clipID] else { return nil }
        return Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private static func logOnce(clipID: String, event: String, body: () -> Void) {
        let key = "\(clipID)|\(event)"
        guard loggedEvents.insert(key).inserted else { return }
        body()
    }
}

nonisolated enum ClipsPagerPrefetchProbe {
    nonisolated(unsafe) private static var loggedEvents: Set<String> = []

    static func resetForTesting() {
        loggedEvents.removeAll()
    }

    static func prepareStarted(clipID: String, index: Int) {
        logOnce("\(clipID)|prepareStarted") {
            print("[ClipsPagerPrefetch] clipID=\(clipID) index=\(index) event=prepareStarted")
        }
    }

    static func prepareReady(clipID: String, index: Int) {
        logOnce("\(clipID)|prepareReady") {
            print("[ClipsPagerPrefetch] clipID=\(clipID) index=\(index) event=prepareReady")
        }
    }

    static func cancelled(clipID: String, index: Int?) {
        let indexLabel = index.map(String.init) ?? "nil"
        logOnce("\(clipID)|cancelled") {
            print("[ClipsPagerPrefetch] clipID=\(clipID) index=\(indexLabel) event=cancelled")
        }
    }

    private static func logOnce(_ key: String, body: () -> Void) {
        guard loggedEvents.insert(key).inserted else { return }
        body()
    }
}
#else
nonisolated enum ClipsPagerPlaybackProbe {
    static func resetForTesting() {}
    static func pageBecameActive(clipID: String, index: Int?) {}
    static func playRequested(clipID: String) {}
    static func firstFrame(clipID: String) {}
}

nonisolated enum ClipsPagerPrefetchProbe {
    static func resetForTesting() {}
    static func prepareStarted(clipID: String, index: Int) {}
    static func prepareReady(clipID: String, index: Int) {}
    static func cancelled(clipID: String, index: Int?) {}
}
#endif
