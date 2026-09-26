import Foundation

#if DEBUG
enum ClipVideoDeliveryDebugControls {
    /// Clears only `Application Support/TradeTraxsPersistentCache/ClipVideoCache/` and in-memory delivery state.
    static func clearClipVideoCache() async {
        await ClipVideoDeliveryService.shared.clearPersistentCacheForColdTest()
        print("[ClipColdTest] event=clipVideoCacheCleared")
    }
}
#endif
