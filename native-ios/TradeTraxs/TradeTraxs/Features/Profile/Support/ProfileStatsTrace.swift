import Foundation

#if DEBUG
enum ProfileStatsTrace {
    private static var loadStartedAt: [String: Date] = [:]

    static func loadStart(subject: String) {
        loadStartedAt[subject] = Date()
        print("[ProfileStatsTrace] loadStart subject=\(subject)")
    }

    static func cacheHit(subject: String, tradeCount: Int) {
        print("[ProfileStatsTrace] cacheHit subject=\(subject) trades=\(tradeCount)")
    }

    static func cacheMiss(subject: String) {
        print("[ProfileStatsTrace] cacheMiss subject=\(subject)")
    }

    static func firstRender(subject: String, source: String) {
        let ms = elapsedMs(subject: subject)
        print("[ProfileStatsTrace] firstRender elapsedMs=\(ms) source=\(source) subject=\(subject)")
    }

    static func revisionStart(subject: String) {
        print("[ProfileStatsTrace] revisionStart subject=\(subject)")
    }

    static func revisionEnd(subject: String, outcome: String) {
        let ms = elapsedMs(subject: subject)
        print("[ProfileStatsTrace] revisionEnd elapsedMs=\(ms) outcome=\(outcome) subject=\(subject)")
    }

    static func bootstrapStart(subject: String) {
        print("[ProfileStatsTrace] bootstrapStart subject=\(subject)")
    }

    static func bootstrapEnd(subject: String, outcome: String) {
        let ms = elapsedMs(subject: subject)
        print("[ProfileStatsTrace] bootstrapEnd elapsedMs=\(ms) outcome=\(outcome) subject=\(subject)")
    }

    static func applyAccepted(subject: String, source: String) {
        print("[ProfileStatsTrace] applyAccepted source=\(source) subject=\(subject)")
    }

    static func applyRejected(subject: String, reason: String) {
        print("[ProfileStatsTrace] applyRejected reason=\(reason) subject=\(subject)")
    }

    static func finalState(subject: String, state: String) {
        let ms = elapsedMs(subject: subject)
        print("[ProfileStatsTrace] finalState=\(state) elapsedMs=\(ms) subject=\(subject)")
        loadStartedAt.removeValue(forKey: subject)
    }

    private static func elapsedMs(subject: String) -> Int {
        guard let started = loadStartedAt[subject] else { return -1 }
        return Int(Date().timeIntervalSince(started) * 1000)
    }
}
#else
enum ProfileStatsTrace {
    static func loadStart(subject: String) {}
    static func cacheHit(subject: String, tradeCount: Int) {}
    static func cacheMiss(subject: String) {}
    static func firstRender(subject: String, source: String) {}
    static func revisionStart(subject: String) {}
    static func revisionEnd(subject: String, outcome: String) {}
    static func bootstrapStart(subject: String) {}
    static func bootstrapEnd(subject: String, outcome: String) {}
    static func applyAccepted(subject: String, source: String) {}
    static func applyRejected(subject: String, reason: String) {}
    static func finalState(subject: String, state: String) {}
}
#endif
