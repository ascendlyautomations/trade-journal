import Foundation

/// Batched `rpc_v1_product_events_ingest` — failures are ignored (never block UX).
actor ProductAnalyticsIngestQueue {
    static let shared = ProductAnalyticsIngestQueue()

    private var queue: [[String: Any]] = []
    private var flushTask: Task<Void, Never>?
    private let maxBatch = 25
    private let flushDelayNs: UInt64 = 12_000_000_000

    func enqueue(_ row: [String: Any], supabase: SupabaseInfrastructure) {
        queue.append(row)
        let eventName = row["event_name"] as? String
        let shouldFlushImmediately =
            queue.count >= maxBatch
            || eventName == ProductAnalyticsEventName.sessionStarted.rawValue
            || eventName == ProductAnalyticsEventName.appOpened.rawValue
        if shouldFlushImmediately {
            Task { await self.flush(supabase: supabase) }
            return
        }
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(nanoseconds: flushDelayNs)
            await self.flush(supabase: supabase)
        }
    }

    func flush(supabase: SupabaseInfrastructure) async {
        flushTask?.cancel()
        flushTask = nil
        guard !queue.isEmpty else { return }
        let batch = Array(queue.prefix(maxBatch))
        queue.removeFirst(min(maxBatch, queue.count))
        let body = try? JSONSerialization.data(withJSONObject: ["p_batch": batch], options: [])
        guard let body else { return }
        _ = try? await supabase.database.rpcData(
            functionName: "rpc_v1_product_events_ingest",
            parametersJSON: body
        )
        if !queue.isEmpty {
            await flush(supabase: supabase)
        }
    }
}

nonisolated struct DefaultAnalyticsRepository: AnalyticsRepository {
    private let supabase: SupabaseInfrastructure?

    init(supabase: SupabaseInfrastructure? = nil) {
        self.supabase = supabase
    }

    func track(event: String, properties: [String: String]) async {
        guard let supabase, supabase.client.isConfigured else { return }
        var props = properties
        let dedupeKey = props.removeValue(forKey: "dedupe_key")
        let sessionRaw = props.removeValue(forKey: "session_id") ?? UUID().uuidString
        let sessionId = UUID(uuidString: sessionRaw) ?? UUID()
        var rpcProps: [String: String] = [:]
        for (key, value) in props where key != "session_id" {
            if [
                "screen_id",
                "profile_id",
                "feature",
                "signup_flow_source",
                "entry_point",
                "preview_feature",
            ].contains(key) {
                rpcProps[key] = String(value.prefix(128))
            }
        }
        var row: [String: Any] = [
            "event_name": event,
            "platform": ProductAnalyticsPlatform.ios.rawValue,
            "session_id": sessionId.uuidString,
        ]
        if let dedupeKey, !dedupeKey.isEmpty {
            row["dedupe_key"] = String(dedupeKey.prefix(256))
        }
        if !rpcProps.isEmpty {
            row["props"] = rpcProps
        }
        await ProductAnalyticsIngestQueue.shared.enqueue(row, supabase: supabase)
    }

    func flushPendingEvents() async {
        guard let supabase, supabase.client.isConfigured else { return }
        await ProductAnalyticsIngestQueue.shared.flush(supabase: supabase)
    }
}