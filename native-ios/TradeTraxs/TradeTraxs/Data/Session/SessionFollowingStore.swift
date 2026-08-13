import Foundation

/// Session-scoped following-ID set — one `followers` edge SELECT per viewer when possible.
///
/// Feed, Stories, Explore, and Profile follow-state all share this. ID-only (not full profiles).
actor SessionFollowingStore {
    static let shared = SessionFollowingStore()

    private var idsByViewer: [String: Set<String>] = [:]
    private var inFlight: [String: Task<Set<String>, Error>] = [:]

    func cached(viewerID: String) -> Set<String>? {
        idsByViewer[viewerID]
    }

    /// Cache-first. `fetch` runs only on miss / force. Concurrent callers share one task.
    func followingIDs(
        viewerID: String,
        forceNetwork: Bool = false,
        fetch: @escaping @Sendable () async throws -> [String]
    ) async throws -> [String] {
        let key = viewerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }

        if !forceNetwork, let cached = idsByViewer[key] {
            await MainActor.run {
                SessionNetworkProbe.record(
                    .cacheHit,
                    resource: "following.ids",
                    detail: "count=\(cached.count)"
                )
            }
            return Array(cached).sorted()
        }

        if let existing = inFlight[key] {
            await MainActor.run {
                SessionNetworkProbe.record(.requestCoalesced, resource: "following.ids", detail: key)
            }
            return Array(try await existing.value).sorted()
        }

        await MainActor.run {
            SessionNetworkProbe.record(.cacheMiss, resource: "following.ids", detail: key)
            SessionNetworkProbe.record(.networkFetch, resource: "following.ids", detail: key)
        }

        let task = Task {
            let rows = try await fetch()
            return Set(
                rows
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let loaded = try await task.value
        idsByViewer[key] = loaded
        await MainActor.run {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "following.ids.seeded",
                detail: "count=\(loaded.count)"
            )
        }
        return Array(loaded).sorted()
    }

    func seed(viewerID: String, ids: Set<String>) {
        let key = viewerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        idsByViewer[key] = ids
    }

    func setFollowing(viewerID: String, targetID: String, isFollowing: Bool) {
        let key = viewerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var set = idsByViewer[key] ?? []
        if isFollowing {
            set.insert(targetID)
        } else {
            set.remove(targetID)
        }
        idsByViewer[key] = set
    }

    func invalidate(viewerID: String? = nil) {
        if let viewerID {
            idsByViewer[viewerID] = nil
            inFlight[viewerID]?.cancel()
            inFlight[viewerID] = nil
        } else {
            inFlight.values.forEach { $0.cancel() }
            idsByViewer = [:]
            inFlight = [:]
        }
    }
}
