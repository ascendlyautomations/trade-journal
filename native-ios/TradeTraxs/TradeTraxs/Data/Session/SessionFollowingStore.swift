import Foundation

/// Session-scoped following state — canonical **complete** following ID set when marked complete.
///
/// Pairwise edges may exist without a complete set; absence in a partial/unknown set is not proof of not-following.
actor SessionFollowingStore {
    static let shared = SessionFollowingStore()

    enum Completeness: Sendable, Equatable {
        case unknown
        case complete(Set<String>)
    }

    private struct ViewerState: Sendable {
        var completeness: Completeness = .unknown
        /// Pairwise viewer→target edges from Profile headers / explicit patches.
        var pairwiseFollowing: [String: Bool] = [:]
        var pairwiseRequested: [String: Bool] = [:]
    }

    private var stateByViewer: [String: ViewerState] = [:]
    private var inFlight: [String: Task<Set<String>, Error>] = [:]

    func completeness(viewerID: String) -> Completeness {
        let key = normalizedViewer(viewerID)
        return stateByViewer[key]?.completeness ?? .unknown
    }

    func isComplete(viewerID: String) -> Bool {
        if case .complete = completeness(viewerID: viewerID) { return true }
        return false
    }

    /// Complete following IDs when known — nil when set is unknown/incomplete.
    func cached(viewerID: String) -> Set<String>? {
        let key = normalizedViewer(viewerID)
        guard case .complete(let ids) = stateByViewer[key]?.completeness else { return nil }
        return ids
    }

    /// Resolved follow edge when known — nil when relationship is unknown.
    func knownIsFollowing(viewerID: String, targetID: String) -> Bool? {
        let key = normalizedViewer(viewerID)
        let target = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        guard let state = stateByViewer[key] else { return nil }
        if case .complete(let ids) = state.completeness {
            return ids.contains(target)
        }
        return state.pairwiseFollowing[target]
    }

    func knownIsRequested(viewerID: String, targetID: String) -> Bool? {
        let key = normalizedViewer(viewerID)
        let target = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return stateByViewer[key]?.pairwiseRequested[target]
    }

    /// Cache-first network load — always marks the loaded set **complete**.
    func followingIDs(
        viewerID: String,
        forceNetwork: Bool = false,
        fetch: @escaping @Sendable () async throws -> [String]
    ) async throws -> [String] {
        let key = normalizedViewer(viewerID)
        guard !key.isEmpty else { return [] }

        if !forceNetwork, let cached = cached(viewerID: key) {
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
        seedComplete(viewerID: key, ids: loaded)
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
        seedComplete(viewerID: viewerID, ids: ids)
    }

    func seedComplete(viewerID: String, ids: Set<String>) {
        let key = normalizedViewer(viewerID)
        guard !key.isEmpty else { return }
        var state = stateByViewer[key] ?? ViewerState()
        state.completeness = .complete(ids)
        for id in ids {
            state.pairwiseFollowing[id] = true
            state.pairwiseRequested[id] = false
        }
        stateByViewer[key] = state
    }

    func seedPairwiseEdge(viewerID: String, targetID: String, isFollowing: Bool) {
        let key = normalizedViewer(viewerID)
        let target = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !target.isEmpty else { return }
        var state = stateByViewer[key] ?? ViewerState()
        state.pairwiseFollowing[target] = isFollowing
        if isFollowing {
            state.pairwiseRequested[target] = false
        }
        stateByViewer[key] = state
    }

    func setPairwiseRequested(viewerID: String, targetID: String, isRequested: Bool) {
        let key = normalizedViewer(viewerID)
        let target = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !target.isEmpty else { return }
        var state = stateByViewer[key] ?? ViewerState()
        state.pairwiseRequested[target] = isRequested
        if isRequested {
            state.pairwiseFollowing[target] = false
        }
        stateByViewer[key] = state
    }

    func setFollowing(viewerID: String, targetID: String, isFollowing: Bool) {
        let key = normalizedViewer(viewerID)
        let target = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !target.isEmpty else { return }
        var state = stateByViewer[key] ?? ViewerState()
        state.pairwiseFollowing[target] = isFollowing
        if isFollowing {
            state.pairwiseRequested[target] = false
        }
        if case .complete(var ids) = state.completeness {
            if isFollowing {
                ids.insert(target)
            } else {
                ids.remove(target)
            }
            state.completeness = .complete(ids)
        }
        stateByViewer[key] = state
    }

    func invalidate(viewerID: String? = nil) {
        if let viewerID {
            let key = normalizedViewer(viewerID)
            stateByViewer[key] = nil
            inFlight[key]?.cancel()
            inFlight[key] = nil
        } else {
            inFlight.values.forEach { $0.cancel() }
            stateByViewer = [:]
            inFlight = [:]
        }
    }

    private func normalizedViewer(_ viewerID: String) -> String {
        viewerID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
