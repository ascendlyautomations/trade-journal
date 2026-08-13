import Foundation
import Observation

/// Session-scoped profile entity cache — one batched SELECT for missing IDs.
///
/// Features must not call `profiles.profile(id:)` in a loop. Use ``profiles(ids:)``.
@Observable
@MainActor
final class SessionProfileStore {
    static let shared = SessionProfileStore()

    private var inFlight: [String: Task<[Profile], Error>] = [:]

    private init() {}

    func cached(id: ProfileID, detailCache: DetailPresentationCache) -> Profile? {
        detailCache.profile(id: id)
    }

    /// Cache-first. Networks only for IDs not already seeded. Concurrent identical
    /// missing-ID sets share one in-flight request.
    func profiles(
        ids: [ProfileID],
        detailCache: DetailPresentationCache,
        repository: any ProfileRepository,
        forceNetwork: Bool = false
    ) async throws -> [Profile] {
        let unique = Array(Set(ids)).filter { !$0.rawValue.isEmpty }
        guard !unique.isEmpty else { return [] }

        var hit: [Profile] = []
        var missing: [ProfileID] = []
        for id in unique {
            if !forceNetwork, let cached = detailCache.profile(id: id) {
                hit.append(cached)
            } else {
                missing.append(id)
            }
        }

        if missing.isEmpty {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "profiles.batch",
                detail: "count=\(hit.count)"
            )
            return sorted(hit)
        }

        SessionNetworkProbe.record(
            .cacheMiss,
            resource: "profiles.batch",
            detail: "missing=\(missing.count) hit=\(hit.count)"
        )

        let key = missing.map(\.rawValue).sorted().joined(separator: ",")
        if let existing = inFlight[key] {
            SessionNetworkProbe.record(.requestCoalesced, resource: "profiles.batch", detail: key)
            let fetched = try await existing.value
            return sorted(merge(hit, fetched))
        }

        SessionNetworkProbe.record(
            .networkFetch,
            resource: "profiles.batch",
            detail: "ids=\(missing.count)"
        )
        let cache = detailCache
        let task = Task {
            let fetched = try await repository.profiles(ids: missing)
            // Seed before waiters resume so coalesced callers observe cache hits.
            for profile in fetched {
                cache.seed(profile)
            }
            return fetched
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let fetched = try await task.value
        return sorted(merge(hit, fetched))
    }

    func seed(_ profiles: [Profile], detailCache: DetailPresentationCache) {
        for profile in profiles {
            detailCache.seed(profile)
        }
        if !profiles.isEmpty {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "profiles.embedSeed",
                detail: "count=\(profiles.count)"
            )
        }
    }

    func upsert(_ profile: Profile, detailCache: DetailPresentationCache) {
        SessionNetworkProbe.record(.realtimeUpdate, resource: "profiles", detail: profile.id.rawValue)
        detailCache.seed(profile)
    }

    func invalidate() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        SessionNetworkProbe.record(.cacheInvalidated, resource: "profiles.batch", detail: "all")
    }

    private func merge(_ a: [Profile], _ b: [Profile]) -> [Profile] {
        var map = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
        for profile in b {
            map[profile.id] = profile
        }
        return Array(map.values)
    }

    private func sorted(_ profiles: [Profile]) -> [Profile] {
        profiles.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
