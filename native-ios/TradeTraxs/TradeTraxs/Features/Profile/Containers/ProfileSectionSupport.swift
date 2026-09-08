import Foundation

nonisolated enum ProfileSectionSupport {
    /// Debug development sessions use `dev.*` IDs that are not in Supabase.
    static func isLocalDevelopmentProfile(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
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
            if hasLoaded, !loadedItems.isEmpty, snapshotItems.count < loadedItems.count {
                return (
                    OwnerProfileOptimisticStore.merging(overlay: snapshotItems, into: loadedItems),
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
                OwnerProfileOptimisticStore.merging(overlay: snapshotItems, into: loadedItems),
                true
            )
        }
        return (
            OwnerProfileOptimisticStore.merging(overlay: snapshotItems, into: loadedItems),
            hasLoaded
        )
    }
}
