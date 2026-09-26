import Foundation

#if DEBUG
/// DEBUG instrumentation for first-view Clip egress (AVPlayer vs cache-fill URLSession).
nonisolated enum ClipColdTestTrace {
    enum Event: String, Sendable {
        case cacheMiss
        case remotePlaybackStarted
        case cacheFillStarted
        case cacheFillCompleted
        case cacheFillCancelled
    }

    enum RequestPurpose: String, Sendable {
        case playback
        case cacheFill
    }

    private struct ClipMetrics {
        var clipID: String
        var canonicalKey: String
        var remoteURL: URL?
        var assetBytes: Int64?
        var playbackNetworkRequests: Int = 0
        var playbackObservedBytes: Int64 = 0
        var cacheFillNetworkRequests: Int = 0
        var cacheFillBytes: Int64 = 0
        var cachePersisted: Bool = false
        var activeFillRequestID: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var metricsByClipID: [String: ClipMetrics] = [:]
    nonisolated(unsafe) private static var summaryTasks: [String: Task<Void, Never>] = [:]

    nonisolated static func resetAll() {
        lock.lock()
        for task in summaryTasks.values {
            task.cancel()
        }
        summaryTasks.removeAll()
        metricsByClipID.removeAll()
        lock.unlock()
        print("[ClipColdTest] event=sessionReset")
    }

    nonisolated static func log(
        clipID: String,
        canonicalKey: String,
        role: String,
        event: Event,
        requestPurpose: RequestPurpose,
        url: URL?,
        expectedAssetBytes: Int64? = nil,
        transferredBytes: Int64? = nil,
        requestID: String? = nil
    ) {
        let roleLabel = normalizedRole(role)
        let urlString = url?.absoluteString ?? "unknown"
        let expected = expectedAssetBytes.map(String.init) ?? "unknown"
        let transferred = transferredBytes.map(String.init) ?? "unknown"
        let reqID = requestID ?? "unknown"

        print(
            """
            [ClipColdTest] clipID=\(clipID) canonicalKey=\(canonicalKey) role=\(roleLabel) \
            event=\(event.rawValue) requestPurpose=\(requestPurpose.rawValue) url=\(urlString) \
            expectedAssetBytes=\(expected) transferredBytes=\(transferred) requestID=\(reqID)
            """
        )

        lock.lock()
        var metrics = metricsByClipID[clipID] ?? ClipMetrics(
            clipID: clipID,
            canonicalKey: canonicalKey,
            remoteURL: url
        )
        metrics.canonicalKey = canonicalKey
        if let url { metrics.remoteURL = url }
        if let expectedAssetBytes, expectedAssetBytes > 0 {
            metrics.assetBytes = expectedAssetBytes
        }

        switch event {
        case .cacheMiss, .remotePlaybackStarted:
            break
        case .cacheFillStarted:
            metrics.cacheFillNetworkRequests += 1
            metrics.activeFillRequestID = requestID
        case .cacheFillCompleted:
            if let transferredBytes, transferredBytes > 0 {
                metrics.cacheFillBytes += transferredBytes
                metrics.assetBytes = metrics.assetBytes ?? transferredBytes
                metrics.cachePersisted = true
            }
            metrics.activeFillRequestID = nil
        case .cacheFillCancelled:
            metrics.activeFillRequestID = nil
        }
        metricsByClipID[clipID] = metrics
        lock.unlock()

        scheduleSummary(clipID: clipID)
    }

    nonisolated static func recordPlaybackTransfer(
        clipID: String,
        canonicalKey: String,
        role: String,
        url: URL?,
        deltaBytes: Int64,
        sessionItemBytes: Int64,
        accessLogEventIndex: Int
    ) {
        guard deltaBytes > 0 || sessionItemBytes > 0 else { return }

        let requestID = "avplayer-\(clipID)-event-\(accessLogEventIndex)"
        log(
            clipID: clipID,
            canonicalKey: canonicalKey,
            role: role,
            event: .remotePlaybackStarted,
            requestPurpose: .playback,
            url: url,
            expectedAssetBytes: nil,
            transferredBytes: deltaBytes,
            requestID: requestID
        )

        lock.lock()
        var metrics = metricsByClipID[clipID] ?? ClipMetrics(
            clipID: clipID,
            canonicalKey: canonicalKey,
            remoteURL: url
        )
        if deltaBytes > 0 {
            metrics.playbackNetworkRequests += 1
        }
        metrics.playbackObservedBytes = max(metrics.playbackObservedBytes, sessionItemBytes)
        metricsByClipID[clipID] = metrics
        lock.unlock()

        scheduleSummary(clipID: clipID)
    }

    nonisolated static func noteKnownAssetBytes(clipID: String, bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        if var metrics = metricsByClipID[clipID] {
            metrics.assetBytes = bytes
            metricsByClipID[clipID] = metrics
        } else {
            metricsByClipID[clipID] = ClipMetrics(
                clipID: clipID,
                canonicalKey: "",
                remoteURL: nil,
                assetBytes: bytes
            )
        }
        lock.unlock()
    }

    nonisolated static func noteCachePersisted(clipID: String, assetBytes: Int64) {
        lock.lock()
        if var metrics = metricsByClipID[clipID] {
            metrics.cachePersisted = true
            if assetBytes > 0 {
                metrics.assetBytes = assetBytes
            }
            metricsByClipID[clipID] = metrics
        }
        lock.unlock()
        scheduleSummary(clipID: clipID)
    }

    // MARK: - Private

    private static func normalizedRole(_ role: String) -> String {
        switch role {
        case "prefetch": return "prefetch"
        default: return "active"
        }
    }

    private static func scheduleSummary(clipID: String) {
        lock.lock()
        summaryTasks[clipID]?.cancel()
        summaryTasks[clipID] = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            emitSummary(clipID: clipID)
        }
        lock.unlock()
    }

    private static func emitSummary(clipID: String) {
        lock.lock()
        guard let metrics = metricsByClipID[clipID] else {
            lock.unlock()
            return
        }
        lock.unlock()

        Task {
            var cachePersisted = metrics.cachePersisted
            var resolvedAssetBytes = metrics.assetBytes
            if let remoteURL = metrics.remoteURL {
                let onDisk = await ClipVideoDeliveryService.shared.debug_isPersisted(remoteURL: remoteURL)
                cachePersisted = cachePersisted || onDisk
                if resolvedAssetBytes == nil {
                    resolvedAssetBytes = await ClipVideoDeliveryService.shared.knownAssetBytes(for: remoteURL)
                }
            }

            let assetBytes = resolvedAssetBytes.map(String.init) ?? "unknown"
            let totalObserved = metrics.playbackObservedBytes + metrics.cacheFillBytes
            let duplicate = possibleDuplicateFullTransfer(
                assetBytes: resolvedAssetBytes,
                playbackBytes: metrics.playbackObservedBytes,
                cacheFillBytes: metrics.cacheFillBytes
            )

            print(
                """
                [ClipColdTestSummary] clipID=\(clipID) assetBytes=\(assetBytes) \
                playbackNetworkRequests=\(metrics.playbackNetworkRequests) \
                playbackObservedBytes=\(metrics.playbackObservedBytes) \
                cacheFillNetworkRequests=\(metrics.cacheFillNetworkRequests) \
                cacheFillBytes=\(metrics.cacheFillBytes) \
                totalObservedNetworkBytes=\(totalObserved) \
                possibleDuplicateFullTransfer=\(duplicate) \
                cachePersisted=\(cachePersisted)
                """
            )
        }
    }

    private static func possibleDuplicateFullTransfer(
        assetBytes: Int64?,
        playbackBytes: Int64,
        cacheFillBytes: Int64
    ) -> String {
        guard let assetBytes, assetBytes > 0 else { return "unknown" }
        guard playbackBytes > 0, cacheFillBytes > 0 else {
            if playbackBytes > 0 || cacheFillBytes > 0 { return "false" }
            return "unknown"
        }
        let playbackFraction = Double(playbackBytes) / Double(assetBytes)
        let fillFraction = Double(cacheFillBytes) / Double(assetBytes)
        if playbackFraction >= 0.45, fillFraction >= 0.85 {
            return "true"
        }
        if playbackFraction >= 0.85, fillFraction >= 0.45 {
            return "true"
        }
        return "false"
    }
}
#else
nonisolated enum ClipColdTestTrace {
    nonisolated static func resetAll() {}
}
#endif
