import Foundation

/// One-shot presentation hints for ``TradeEntryHubView`` (e.g. notification deep links).
enum TradeEntryLaunchIntent {
    private static var pendingHubTab: TradeEntryHubView.Tab?

    static func prepare(hubTab: TradeEntryHubView.Tab) {
        pendingHubTab = hubTab
    }

    static func consumeHubTab() -> TradeEntryHubView.Tab? {
        defer { pendingHubTab = nil }
        return pendingHubTab
    }
}
