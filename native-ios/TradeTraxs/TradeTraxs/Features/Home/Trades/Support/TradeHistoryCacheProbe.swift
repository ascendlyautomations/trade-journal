#if DEBUG
import Foundation

/// Concise DEBUG summaries for Trade History owner-cache first render.
@MainActor
enum TradeHistoryCacheProbe {
    private(set) static var hit = false
    private(set) static var complete = false
    private(set) static var tradeCount = 0
    private(set) static var firstRenderMs = 0
    private(set) static var networkRequired = false
    private(set) static var reason: String = "none"

    static func resetForTesting() {
        hit = false
        complete = false
        tradeCount = 0
        firstRenderMs = 0
        networkRequired = false
        reason = "none"
    }

    static func recordDiskHit(complete isComplete: Bool, trades: Int, firstRenderMs ms: Int) {
        hit = true
        complete = isComplete
        tradeCount = trades
        firstRenderMs = ms
        networkRequired = false
        reason = isComplete ? "completeOwnerCache" : "partialOwnerCache"
        print("[TradeHistoryCache] hit=true complete=\(isComplete) trades=\(trades)")
        print("[TradeHistoryCache] firstRenderMs=\(ms)")
        print("[TradeHistoryCache] networkRequired=false reason=\(reason)")
    }

    static func recordNetworkRequired(reason value: String) {
        hit = false
        networkRequired = true
        reason = value
        print("[TradeHistoryCache] hit=false complete=false trades=0")
        print("[TradeHistoryCache] networkRequired=true reason=\(value)")
    }
}
#endif
