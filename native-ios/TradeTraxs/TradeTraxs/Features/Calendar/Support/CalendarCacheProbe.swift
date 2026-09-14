#if DEBUG
import Foundation

/// Concise DEBUG summaries for Calendar owner-cache month render.
@MainActor
enum CalendarCacheProbe {
    private(set) static var month: String = "-"
    private(set) static var hit = false
    private(set) static var complete = false
    private(set) static var tradeCount = 0
    private(set) static var firstRenderMs = 0
    private(set) static var networkRequired = false
    private(set) static var reason: String = "none"

    static func resetForTesting() {
        month = "-"
        hit = false
        complete = false
        tradeCount = 0
        firstRenderMs = 0
        networkRequired = false
        reason = "none"
    }

    static func recordDiskHit(
        month value: String,
        complete isComplete: Bool,
        trades: Int,
        firstRenderMs ms: Int
    ) {
        month = value
        hit = true
        complete = isComplete
        tradeCount = trades
        firstRenderMs = ms
        networkRequired = false
        reason = isComplete ? "completeOwnerCache" : "partialOwnerCache"
        print("[CalendarCache] month=\(value) hit=true complete=\(isComplete) trades=\(trades)")
        print("[CalendarCache] firstRenderMs=\(ms)")
        print("[CalendarCache] networkRequired=false reason=\(reason)")
    }

    static func recordNetworkRequired(month value: String, reason valueReason: String) {
        month = value
        hit = false
        networkRequired = true
        reason = valueReason
        print("[CalendarCache] month=\(value) hit=false complete=false trades=0")
        print("[CalendarCache] networkRequired=true reason=\(valueReason)")
    }
}
#endif
