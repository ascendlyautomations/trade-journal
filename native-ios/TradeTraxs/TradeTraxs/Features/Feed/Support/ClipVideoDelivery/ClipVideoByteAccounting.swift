import Foundation

#if DEBUG
/// Approximate split of Clip network bytes (AVPlayer access log vs TradeTraxs cache fill).
nonisolated enum ClipVideoByteAccounting {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var avPlayerBytes: Int64 = 0
    nonisolated(unsafe) private static var cacheFillBytes: Int64 = 0
    nonisolated(unsafe) private static var diagnosticProbeBytes: Int64 = 0

    nonisolated static func recordAVPlayerDelta(clipID: String, bytes: Int64, role: String) {
        guard bytes > 0 else { return }
        lock.lock()
        avPlayerBytes += bytes
        lock.unlock()
        print(
            """
            [ClipDelivery] byteAccounting clipID=\(clipID) role=\(role) \
            avPlayerBytes=\(bytes) avPlayerTotal=\(avPlayerBytes) \
            cacheFillTotal=\(cacheFillBytes) diagnosticProbeTotal=\(diagnosticProbeBytes)
            """
        )
    }

    nonisolated static func recordCacheFill(clipID: String, bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        cacheFillBytes += bytes
        lock.unlock()
        print(
            """
            [ClipDelivery] byteAccounting clipID=\(clipID) \
            cacheFillBytes=\(bytes) cacheFillTotal=\(cacheFillBytes) \
            avPlayerTotal=\(avPlayerBytes)
            """
        )
    }

    nonisolated static func recordDiagnosticProbe(bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        diagnosticProbeBytes += bytes
        lock.unlock()
    }

    nonisolated static func resetSession() {
        lock.lock()
        avPlayerBytes = 0
        cacheFillBytes = 0
        diagnosticProbeBytes = 0
        lock.unlock()
    }

    nonisolated static func snapshot() -> (avPlayer: Int64, cacheFill: Int64, probes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        return (avPlayerBytes, cacheFillBytes, diagnosticProbeBytes)
    }
}
#else
nonisolated enum ClipVideoByteAccounting {
    nonisolated static func recordAVPlayerDelta(clipID: String, bytes: Int64, role: String) {}
    nonisolated static func recordCacheFill(clipID: String, bytes: Int64) {}
    nonisolated static func recordDiagnosticProbe(bytes: Int64) {}
    nonisolated static func resetSession() {}
}
#endif
