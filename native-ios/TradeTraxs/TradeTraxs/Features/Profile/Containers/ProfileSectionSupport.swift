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
    /// A resolved first page updates rows inside its date window. It does not drop
    /// later pages that were already loaded. An empty snapshot is not proof that a
    /// loaded section is empty.
    static func reconcileSectionItems<T: Identifiable>(
        snapshotItems: [T],
        loadedItems: [T],
        hasLoaded: Bool,
        didLoadAuthoritative: Bool,
        orderedBy date: KeyPath<T, Date>
    ) -> (items: [T], hasLoaded: Bool) where T.ID: Hashable {
        if didLoadAuthoritative {
            if hasLoaded, !loadedItems.isEmpty {
                return (
                    reconcileLoadedSnapshot(
                        snapshot: snapshotItems,
                        loaded: loadedItems,
                        orderedBy: date
                    ),
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
                reconcileLoadedSnapshot(
                    snapshot: snapshotItems,
                    loaded: loadedItems,
                    orderedBy: date
                ),
                true
            )
        }
        return (
            OwnerProfileOptimisticStore.merging(overlay: snapshotItems, into: loadedItems),
            hasLoaded
        )
    }

    /// Merges a first-page snapshot into rows already loaded.
    ///
    /// Rows newer than the page stay (a publish the response has not caught up to).
    /// Rows inside the page window that the snapshot omits were deleted, made private,
    /// or excluded by the active server filter. Rows older than a partial page stay.
    /// A complete snapshot (`snapshotIsPartial == false`) replaces that older tail.
    /// An empty snapshot leaves the loaded rows in place.
    nonisolated static func reconcileLoadedSnapshot<T: Identifiable>(
        snapshot: [T],
        loaded: [T],
        orderedBy date: KeyPath<T, Date>,
        snapshotIsPartial: Bool = true
    ) -> [T] where T.ID: Hashable {
        guard !loaded.isEmpty else { return snapshot }
        guard !snapshot.isEmpty else { return loaded }
        let snapshotIDs = Set(snapshot.map(\.id))
        let newest = snapshot.map { $0[keyPath: date] }.max()
        let oldest = snapshot.map { $0[keyPath: date] }.min()
        var pending: [T] = []
        var tail: [T] = []
        for item in loaded where !snapshotIDs.contains(item.id) {
            let stamp = item[keyPath: date]
            if let newest, stamp > newest {
                pending.append(item)
            } else if snapshotIsPartial, let oldest, stamp < oldest {
                tail.append(item)
            }
        }
        return pending + snapshot + tail
    }

    /// Upserts a page into rows already on screen.
    ///
    /// A refresh adds and updates rows. It does not treat a short page as proof
    /// that everything else was deleted. Explicit deletes remove rows separately.
    nonisolated static func mergeKeepingExisting<T: Identifiable>(
        incoming: [T],
        loaded: [T],
        orderedBy date: KeyPath<T, Date>
    ) -> [T] where T.ID: Hashable {
        guard !incoming.isEmpty else { return loaded }
        guard !loaded.isEmpty else { return incoming }
        var byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        for item in incoming {
            byID[item.id] = item
        }
        return byID.values.sorted { $0[keyPath: date] > $1[keyPath: date] }
    }

    /// Applies one server page without letting a short page replace a longer list.
    ///
    /// An empty page leaves the loaded rows in place. A page smaller than half the
    /// loaded list is merged in and does not delete rows. A normal page still drops
    /// rows the server omitted inside its window, and a complete page can drop the
    /// older tail.
    nonisolated static func applyingLoadedPage<T: Identifiable>(
        incoming: [T],
        loaded: [T],
        orderedBy date: KeyPath<T, Date>,
        pageIsComplete: Bool
    ) -> [T] where T.ID: Hashable {
        guard !incoming.isEmpty else { return loaded }
        let suspiciousShrink = incoming.count * 2 < loaded.count
        if loaded.isEmpty || suspiciousShrink {
            return mergeKeepingExisting(
                incoming: incoming,
                loaded: loaded,
                orderedBy: date
            )
        }
        return reconcileLoadedSnapshot(
            snapshot: incoming,
            loaded: loaded,
            orderedBy: date,
            snapshotIsPartial: !pageIsComplete
        )
    }
}
