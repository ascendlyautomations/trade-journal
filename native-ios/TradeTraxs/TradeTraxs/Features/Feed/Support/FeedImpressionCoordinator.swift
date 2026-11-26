import Foundation

/// Batched feed impression recording (`rpc_v1_feed_record_impressions`).
@MainActor
final class FeedImpressionCoordinator {
    static let shared = FeedImpressionCoordinator()

  private struct Item: Hashable {
        let contentKind: String
        let contentID: String
    }

    private var pending: Set<Item> = []
    private var flushTask: Task<Void, Never>?
    private let maxBatch = 50

    private init() {}

    func trackVisibleContent(kind: String, contentID: String) {
        guard BackendV2FeatureFlags.isEnabled(.feedRotatingRank) else { return }
        pending.insert(Item(contentKind: kind, contentID: contentID))
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await self.flush()
            self.flushTask = nil
        }
    }

    func flushIfNeeded(rpc: (any RPCClient)?) async {
        guard !pending.isEmpty, let rpc else { return }
        await flush(using: rpc)
    }

    private func flush(using rpc: (any RPCClient)? = nil) async {
        guard !pending.isEmpty else { return }
        let batch = Array(pending.prefix(maxBatch))
        for item in batch { pending.remove(item) }

        struct Payload: Encodable {
            var content_kind: String
            var content_id: String
        }

        let items = batch.map {
            Payload(content_kind: $0.contentKind, content_id: $0.contentID)
        }
        struct Args: Encodable { var p_items: [Payload] }
        guard let body = try? JSONEncoder().encode(Args(p_items: items)) else { return }
        guard let rpc else { return }

        do {
            _ = try await rpc.call(
                functionName: BackendV2Versioning.RPCName.feedRecordImpressions.rawValue,
                jsonBody: body
            )
        } catch {
            #if DEBUG
            print("[FeedImpressionCoordinator] flush failed: \(error)")
            #endif
        }
    }
}