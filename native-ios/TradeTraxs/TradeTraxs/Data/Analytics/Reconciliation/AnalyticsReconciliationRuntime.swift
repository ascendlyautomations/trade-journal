import Foundation

nonisolated enum AnalyticsReconciliationRuntime {
    nonisolated(unsafe) static var rpc: (any RPCClient)?
    nonisolated(unsafe) static var detailCache: DetailPresentationCache?

    static func configure(rpc: any RPCClient, detailCache: DetailPresentationCache) {
        self.rpc = rpc
        self.detailCache = detailCache
    }

    static func reset() {
        rpc = nil
        detailCache = nil
    }
}
