import Foundation

nonisolated enum ProfileSectionSupport {
    /// Bundled local profiles — debug `dev.*` and production Explore Mode demo trader.
    static func isLocalDevelopmentProfile(_ id: ProfileID) -> Bool {
        DemoExperienceSupport.usesLocalBundledData(id)
    }

    static func message(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return UserFacingError.map(AppError.unknown(message: error.localizedDescription)).message
    }

    /// Reconciles a bootstrap snapshot with an already-loaded section list.
    ///
    /// Authoritative complete snapshots (`didLoad* == true`) replace the section when
    /// they are at least as complete as what is already visible. Optimistic-only snapshots
    /// merge into loaded items and never downgrade `hasLoaded`.
    static func reconcileSectionItems<T: Identifiable>(
        snapshotItems: [T],
        loadedItems: [T],
        hasLoaded: Bool,
        didLoadAuthoritative: Bool
    ) -> (items: [T], hasLoaded: Bool) where T.ID: Hashable {
        if didLoadAuthoritative {
            if hasLoaded, !loadedItems.isEmpty {
                return (
                    reconcileLoadedSnapshot(snapshot: snapshotItems, loaded: loadedItems),
                    true
                )
            }
            return (snapshotItems, true)
        }
        guard !snapshotItems.isEmpty else {
            return (loadedItems, hasLoaded)
        }
        if hasLoaded, !loadedItems.isEmpty {
            return (
                reconcileLoadedSnapshot(snapshot: snapshotItems, loaded: loadedItems),
                true
            )
        }
        return (
            OwnerProfileOptimisticStore.merging(overlay: snapshotItems, into: loadedItems),
            hasLoaded
        )
    }

    /// Keeps pagination tail while applying removals from a smaller profile snapshot.
    nonisolated static func reconcileLoadedSnapshot<T: Identifiable>(
        snapshot: [T],
        loaded: [T]
    ) -> [T] where T.ID: Hashable {
        guard !loaded.isEmpty else { return snapshot }
        let snapshotIDs = Set(snapshot.map(\.id))
        let loadedIDs = Set(loaded.map(\.id))
        let removedIDs = loadedIDs.subtracting(snapshotIDs)
        if removedIDs.isEmpty {
            return OwnerProfileOptimisticStore.merging(overlay: snapshot, into: loaded)
        }
        let paginationTail = loaded.filter {
            !snapshotIDs.contains($0.id) && !removedIDs.contains($0.id)
        }
        return OwnerProfileOptimisticStore.merging(overlay: snapshot, into: paginationTail)
    }
}
