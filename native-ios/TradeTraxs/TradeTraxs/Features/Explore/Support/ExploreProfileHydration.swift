import Foundation

/// Explore-only profile avatar hydration — does not alter global SessionProfileStore policy.
enum ExploreProfileHydration {
    struct Metrics: Sendable {
        var batchRequestCount: Int = 0
    }

    /// Avatar is known: present on profile, or batch/API confirmed absence.
    static func isAvatarResolved(_ profile: Profile, confirmedAbsent: Set<ProfileID>) -> Bool {
        profile.avatar != nil || confirmedAbsent.contains(profile.id)
    }

    /// Batch-hydrate trader avatars; prefer authoritative API rows over partial cache seeds.
    static func hydrateTraders(
        _ suggestions: [ExploreTraderSuggestion],
        authoritativeProfiles: [ProfileID: Profile],
        detailCache: DetailPresentationCache,
        repository: any ProfileRepository,
        confirmedAbsent: inout Set<ProfileID>,
        forceNetwork: Bool = false
    ) async -> ([ExploreTraderSuggestion], Metrics) {
        guard !suggestions.isEmpty else { return ([], Metrics()) }

        var needsBatch: [ProfileID] = []
        var merged: [ExploreTraderSuggestion] = []

        for var suggestion in suggestions {
            let profileID = suggestion.profile.id
            if let authoritative = authoritativeProfiles[profileID] {
                suggestion.profile = suggestion.profile.mergingCachedPresentation(with: authoritative)
                detailCache.seed(suggestion.profile)
                if suggestion.profile.avatar == nil {
                    confirmedAbsent.insert(profileID)
                } else {
                    confirmedAbsent.remove(profileID)
                }
                merged.append(suggestion)
                continue
            }

            if let cached = detailCache.profile(id: profileID), cached.avatar != nil {
                suggestion.profile = suggestion.profile.mergingCachedPresentation(with: cached)
            }

            if isAvatarResolved(suggestion.profile, confirmedAbsent: confirmedAbsent) {
                merged.append(suggestion)
                continue
            }

            needsBatch.append(profileID)
            merged.append(suggestion)
        }

        let unique = Array(Set(needsBatch))
        var metrics = Metrics()
        guard !unique.isEmpty else {
            #if DEBUG
            ExploreHydrationDiagnostics.logProfiles(
                requested: suggestions.count,
                resolved: merged.filter { isAvatarResolved($0.profile, confirmedAbsent: confirmedAbsent) }.count,
                withAvatar: merged.filter { $0.profile.avatar != nil }.count
            )
            #endif
            return (merged, metrics)
        }

        metrics.batchRequestCount = 1
        let absentSnapshot = confirmedAbsent
        let fetched = (try? await SessionProfileStore.shared.profiles(
            ids: unique,
            detailCache: detailCache,
            repository: repository,
            forceNetwork: forceNetwork,
            acceptCached: { isAvatarResolved($0, confirmedAbsent: absentSnapshot) }
        )) ?? []

        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        for profileID in unique {
            guard let profile = byID[profileID] ?? detailCache.profile(id: profileID) else { continue }
            detailCache.seed(profile)
            if profile.avatar == nil {
                confirmedAbsent.insert(profileID)
            } else {
                confirmedAbsent.remove(profileID)
            }
        }

        let hydrated = merged.map { suggestion -> ExploreTraderSuggestion in
            guard needsBatch.contains(suggestion.profile.id) else { return suggestion }
            var copy = suggestion
            if let profile = byID[suggestion.profile.id] ?? detailCache.profile(id: suggestion.profile.id) {
                copy.profile = copy.profile.mergingCachedPresentation(with: profile)
            }
            return copy
        }

        #if DEBUG
        ExploreHydrationDiagnostics.logProfiles(
            requested: suggestions.count,
            resolved: hydrated.filter { isAvatarResolved($0.profile, confirmedAbsent: confirmedAbsent) }.count,
            withAvatar: hydrated.filter { $0.profile.avatar != nil }.count
        )
        #endif

        return (hydrated, metrics)
    }
}
