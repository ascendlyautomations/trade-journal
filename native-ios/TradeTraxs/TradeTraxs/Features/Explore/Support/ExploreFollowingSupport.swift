import Foundation

@MainActor
enum ExploreFollowingSupport {
    static func loadFollowingIDs(
        viewerID: ProfileID,
        detailCache: DetailPresentationCache,
        profiles: any ProfileRepository
    ) async -> Set<ProfileID> {
        if let cached = detailCache.viewerFollowingIDs() {
            return cached
        }
        if let shared = await SessionFollowingStore.shared.cached(viewerID: viewerID.rawValue) {
            let ids = Set(shared.map { ProfileID($0) })
            detailCache.seedViewerFollowingIDs(ids)
            return ids
        }
        if let disk = RelationshipFollowingPersistence.loadComplete(for: viewerID) {
            let ids = Set(disk.map { ProfileID($0) })
            await SessionFollowingStore.shared.seedComplete(viewerID: viewerID.rawValue, ids: Set(disk))
            detailCache.seedViewerFollowingIDs(ids)
            return ids
        }
        do {
            let page = try await profiles.following(of: viewerID, page: PageRequest(limit: 500))
            let ids = Set(page.items.map(\.id))
            await SessionFollowingStore.shared.seedComplete(
                viewerID: viewerID.rawValue,
                ids: Set(ids.map(\.rawValue))
            )
            detailCache.seedViewerFollowingIDs(ids)
            let generation = RelationshipWriteGeneration.bump(viewerID: viewerID)
            RelationshipFollowingPersistence.saveComplete(
                ids: ids.map(\.rawValue),
                viewerID: viewerID,
                generation: generation
            )
            return ids
        } catch {
            return []
        }
    }

    /// Suggested-trader lists — people you do not follow first, then followed (deduped).
    static func mergeDiscoverableFirst(
        discoverable: [ExploreTraderSuggestion],
        following: [ExploreTraderSuggestion]
    ) -> [ExploreTraderSuggestion] {
        var seen = Set<ProfileID>()
        var merged: [ExploreTraderSuggestion] = []
        for trader in discoverable where seen.insert(trader.id).inserted {
            merged.append(trader)
        }
        for trader in following where seen.insert(trader.id).inserted {
            merged.append(trader)
        }
        return merged
    }

    static func orderingSuggestedTraders(
        _ traders: [ExploreTraderSuggestion],
        followingIDs: Set<ProfileID>,
        profile: (ExploreTraderSuggestion) -> Profile
    ) -> [ExploreTraderSuggestion] {
        let notFollowing = traders.filter { !followingIDs.contains($0.id) }
        let followingOnly = traders.filter { followingIDs.contains($0.id) }
        return ExploreTraderRanking.preservingOrderPreferringProfilePictures(notFollowing, profile: profile)
            + ExploreTraderRanking.preservingOrderPreferringProfilePictures(followingOnly, profile: profile)
    }

    static func suggestions(
        for followingIDs: Set<ProfileID>,
        viewerID: ProfileID,
        detailCache: DetailPresentationCache,
        profiles: any ProfileRepository,
        confirmedAbsent: inout Set<ProfileID>
    ) async -> [ExploreTraderSuggestion] {
        let targets = followingIDs
            .filter { $0 != viewerID }
            .subtracting(FeedBlockedAuthorsFilter.shared.blockedPeerIDs)
        guard !targets.isEmpty else { return [] }

        let ordered = targets.sorted { $0.rawValue < $1.rawValue }
        let absentForCacheAcceptance = confirmedAbsent
        let fetched = (try? await SessionProfileStore.shared.profiles(
            ids: ordered,
            detailCache: detailCache,
            repository: profiles,
            acceptCached: { profile in
                ExploreProfileHydration.isAvatarResolved(
                    profile,
                    confirmedAbsent: absentForCacheAcceptance
                )
                    || !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )) ?? []

        var suggestions: [ExploreTraderSuggestion] = []
        for profile in fetched {
            detailCache.seed(profile)
            if profile.avatar == nil {
                confirmedAbsent.insert(profile.id)
            } else {
                confirmedAbsent.remove(profile.id)
            }
            let score = ExploreTraderRanking.score(profile: profile)
            suggestions.append(
                ExploreTraderSuggestion(
                    profile: profile,
                    followerCount: 0,
                    score: score,
                    identityLine: ExploreTraderRanking.identityLine(for: profile)
                )
            )
        }
        suggestions.sort { lhs, rhs in
            lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
                == .orderedAscending
        }
        return suggestions
    }
}
