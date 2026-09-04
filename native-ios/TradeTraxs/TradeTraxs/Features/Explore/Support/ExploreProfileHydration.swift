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

    /// Batch-hydrate trader avatars; merge embedded rows without treating missing avatars as final.
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
        #if DEBUG
        var traces: [ExploreHydrationDiagnostics.TraderAvatarTrace] = []
        #endif

        for var suggestion in suggestions {
            let profileID = suggestion.profile.id
            let bootstrapHasAvatar = suggestion.profile.avatar != nil

            if let authoritative = authoritativeProfiles[profileID] {
                suggestion.profile = suggestion.profile.mergingCachedPresentation(with: authoritative)
                if suggestion.profile.avatar != nil {
                    detailCache.seed(suggestion.profile)
                    confirmedAbsent.remove(profileID)
                }
            }

            let beforeCacheMerge = suggestion.profile.avatar
            if let cached = detailCache.profile(id: profileID), cached.avatar != nil {
                suggestion.profile = suggestion.profile.mergingCachedPresentation(with: cached)
                if suggestion.profile.avatar != nil {
                    confirmedAbsent.remove(profileID)
                }
            }
            #if DEBUG
            let cachePreservedAvatar = beforeCacheMerge == nil && suggestion.profile.avatar != nil
            #endif

            if suggestion.profile.avatar != nil {
                merged.append(suggestion)
                #if DEBUG
                traces.append(
                    ExploreHydrationDiagnostics.TraderAvatarTrace(
                        profileID: profileID,
                        bootstrapHasAvatar: bootstrapHasAvatar,
                        batchRequired: false,
                        batchHasAvatar: nil,
                        cachePreservedAvatar: cachePreservedAvatar,
                        finalHasAvatar: true
                    )
                )
                #endif
                continue
            }

            needsBatch.append(profileID)
            merged.append(suggestion)
            #if DEBUG
            traces.append(
                ExploreHydrationDiagnostics.TraderAvatarTrace(
                    profileID: profileID,
                    bootstrapHasAvatar: bootstrapHasAvatar,
                    batchRequired: true,
                    batchHasAvatar: nil,
                    cachePreservedAvatar: cachePreservedAvatar,
                    finalHasAvatar: suggestion.profile.avatar != nil
                )
            )
            #endif
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
            ExploreHydrationDiagnostics.logTraderAvatars(traces)
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
            acceptCached: { profile in
                profile.avatar != nil
                    || (absentSnapshot.contains(profile.id) && !forceNetwork)
            }
        )) ?? []

        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        for profileID in unique {
            let profile = detailCache.profile(id: profileID) ?? byID[profileID]
            guard let profile else { continue }
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
        for index in traces.indices where traces[index].batchRequired {
            let profileID = traces[index].profileID
            let final = hydrated.first(where: { $0.id == profileID })?.profile
            traces[index].batchHasAvatar = final?.avatar != nil
            traces[index].finalHasAvatar = final?.avatar != nil
        }
        ExploreHydrationDiagnostics.logProfiles(
            requested: suggestions.count,
            resolved: hydrated.filter { isAvatarResolved($0.profile, confirmedAbsent: confirmedAbsent) }.count,
            withAvatar: hydrated.filter { $0.profile.avatar != nil }.count
        )
        ExploreHydrationDiagnostics.logTraderAvatars(traces)
        #endif

        return (hydrated, metrics)
    }
}
