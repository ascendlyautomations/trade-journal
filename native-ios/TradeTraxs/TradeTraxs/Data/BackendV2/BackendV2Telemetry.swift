import Foundation
import os

/// Development-only Backend V2 instrumentation (no analytics service).
nonisolated struct BackendV2TelemetryEvent: Sendable {
    var rpcName: String
    var success: Bool
    var executionMs: Double
    var decodeMs: Double?
    var payloadBytes: Int?
    var cacheHit: Bool?
    var cacheMiss: Bool?
    var errorCode: String?
    var flagName: String?
}

nonisolated enum BackendV2Telemetry {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "BackendV2"
    )

    nonisolated(unsafe) private static var enabled = true
    nonisolated(unsafe) private static var sink: (@Sendable (BackendV2TelemetryEvent) -> Void)?

    static func setEnabled(_ value: Bool) {
        enabled = value
    }

    static func setSink(_ next: (@Sendable (BackendV2TelemetryEvent) -> Void)?) {
        sink = next
    }

    static func record(_ event: BackendV2TelemetryEvent) {
        guard enabled else { return }
        if let sink {
            sink(event)
            return
        }
        #if DEBUG
        let cache: String = {
            if event.cacheHit == true { return "hit" }
            if event.cacheMiss == true { return "miss" }
            return "n/a"
        }()
        logger.debug(
            "\(event.rpcName, privacy: .public) \(event.success ? "ok" : "fail", privacy: .public) exec=\(event.executionMs, format: .fixed(precision: 1))ms decode=\(event.decodeMs ?? -1, format: .fixed(precision: 1))ms bytes=\(event.payloadBytes ?? -1) cache=\(cache, privacy: .public)"
        )
        #endif
    }
}
