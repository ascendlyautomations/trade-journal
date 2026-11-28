import Foundation

/// Batched feed impression recording (`rpc_v1_feed_record_impressions`).
@MainActor
final class FeedImpressionCoordinator {
    static let shared = FeedImpressionCoordinator()

    private struct Item: Hashable {
        let contentKind: String
        let contentID: String
        let surface: String
    }

    private var rpc: (any RPCClient)?
    private var boundViewerID: String?
    private var pendingByViewer: [String: Set<Item>] = [:]
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private let maxBatch = 50
    private let debounceNanoseconds: UInt64 = 4_000_000_000

    private init() {}

    func configure(rpc: (any RPCClient)?, viewerID: ProfileID?) {
        self.rpc = rpc
        if let viewerID {
            let raw = viewerID.rawValue
            if boundViewerID != raw {
                boundViewerID = raw
            }
        }
    }

    func clearViewer(_ viewerID: ProfileID) {
        let raw = viewerID.rawValue
        pendingByViewer.removeValue(forKey: raw)
        if boundViewerID == raw {
            boundViewerID = nil
        }
    }

    func resetForSessionBoundary() {
        flushTask?.cancel()
        flushTask = nil
        pendingByViewer.removeAll(keepingCapacity: false)
        boundViewerID = nil
        isFlushing = false
    }

    func trackVisibleContent(kind: String, contentID: String, surface: String = "feed") {
        guard BackendV2FeatureFlags.recordsCreatorContentViews else { return }
        guard let viewerID = boundViewerID else { return }
        let trimmedID = contentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        let item = Item(contentKind: kind, contentID: trimmedID, surface: surface)
        var bucket = pendingByViewer[viewerID, default: []]
        bucket.insert(item)
        pendingByViewer[viewerID] = bucket
        FeedRotatingRankProbe.impressionQualified(kind: kind, contentID: trimmedID)
        scheduleFlush(for: viewerID)
    }

    func flushIfNeeded(rpc: (any RPCClient)?, viewerID: ProfileID?) async {
        let client = rpc ?? self.rpc
        guard let viewerID, let client else { return }
        await flush(viewerID: viewerID.rawValue, rpc: client)
    }

    func flushAllPending(rpc: (any RPCClient)?, viewerID: ProfileID?) async {
        await flushIfNeeded(rpc: rpc, viewerID: viewerID)
    }

    private func scheduleFlush(for viewerID: String) {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            let client = self.rpc
            if let client {
                await self.flush(viewerID: viewerID, rpc: client)
            }
            self.flushTask = nil
        }
    }

    private func flush(viewerID: String, rpc: any RPCClient) async {
        guard !isFlushing else { return }
        guard var pending = pendingByViewer[viewerID], !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !pending.isEmpty {
            let batch = Array(pending.prefix(maxBatch))
            let batchSet = Set(batch)
            pending.subtract(batchSet)

            struct Payload: Encodable {
                var content_kind: String
                var content_id: String
                var surface: String
            }

            let items = batch.map {
                Payload(
                    content_kind: $0.contentKind,
                    content_id: $0.contentID,
                    surface: $0.surface
                )
            }
            struct Args: Encodable { var p_items: [Payload] }
            guard let body = try? JSONEncoder().encode(Args(p_items: items)) else {
                pending.formUnion(batchSet)
                pendingByViewer[viewerID] = pending
                return
            }

            do {
                _ = try await rpc.call(
                    functionName: BackendV2Versioning.RPCName.feedRecordImpressions.rawValue,
                    jsonBody: body
                )
                pendingByViewer[viewerID] = pending
                FeedRotatingRankProbe.impressionUploaded(count: batch.count, viewerID: viewerID)
            } catch {
                pending.formUnion(batchSet)
                pendingByViewer[viewerID] = pending
                FeedRotatingRankProbe.impressionUploadFailed(count: batch.count, error: error)
                return
            }
        }
        if pending.isEmpty {
            pendingByViewer.removeValue(forKey: viewerID)
        } else {
            pendingByViewer[viewerID] = pending
        }
    }
}