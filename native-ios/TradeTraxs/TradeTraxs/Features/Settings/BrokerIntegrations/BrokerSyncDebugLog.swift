import Foundation

#if DEBUG
nonisolated enum BrokerSyncDebugLog {
    static func syncHTTP(path: String, status: Int, bytes: Int) {
        print("[BrokerSync] path=\(path) httpStatus=\(status) bytes=\(bytes)")
    }

    static func syncReport(
        provider: BrokerIntegrationProvider,
        connectionID: String,
        accountMappingID: String,
        response: TradovateAccountSyncResponse
    ) {
        let summary = response.summary
        let resolution = BrokerSyncFailureResolution.from(response)
        let reconnectRequired = resolution == .reconnectRequired
        print(
            """
            [BrokerSync] provider=\(provider.rawValue) connectionID=\(connectionID) \
            accountMappingID=\(accountMappingID) result=\(summary.ok ? "ok" : "failed") \
            reconnectRequired=\(reconnectRequired) code=\(response.resolvedClientCode ?? "-") \
            imported=\(summary.tradesCreated) updated=\(summary.tradesUpdated) \
            previewEligible=\(summary.previewEligibleCount.map(String.init) ?? "-") \
            previewRows=\(summary.importPreviewTrades.count) persistCalled=\(summary.persistCalled.map { String($0) } ?? "-") \
            summaryStatus=\(summary.status) errorCode=\(summary.errorCode ?? "-")
            """
        )
        if reconnectRequired {
            print(
                """
                [BrokerSync] result=reconnectRequired reason=\(summary.error ?? response.errorCode ?? "-")
                """
            )
        }
    }
}
#else
nonisolated enum BrokerSyncDebugLog {
    static func syncHTTP(path: String, status: Int, bytes: Int) {}
    static func syncReport(
        provider: BrokerIntegrationProvider,
        connectionID: String,
        accountMappingID: String,
        response: TradovateAccountSyncResponse
    ) {}
}
#endif
