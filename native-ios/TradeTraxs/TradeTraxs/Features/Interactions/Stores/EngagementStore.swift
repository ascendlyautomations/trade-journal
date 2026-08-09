import Foundation
import Observation

/// Session-scoped engagement cache — shared by Profile lists and Detail screens.
@Observable
@MainActor
final class EngagementStore {
    private(set) var snapshots: [InteractionTarget: EngagementSnapshot] = [:]

    private let repository: any InteractionRepository
    private var loadedTargets: Set<InteractionTarget> = []
    /// Targets currently requested or in-flight — prevents duplicate network work.
    private var requestedTargets: Set<InteractionTarget> = []
    private var pendingTargets: Set<InteractionTarget> = []
    private var inFlightLikes: Set<InteractionTarget> = []
    private var prefetchTask: Task<Void, Never>?

    init(repository: any InteractionRepository) {
        self.repository = repository
    }

    func snapshot(for target: InteractionTarget) -> EngagementSnapshot {
        snapshots[target] ?? .empty
    }

    /// Inject cached engagement (list → detail, fixtures, screenshots).
    func seed(_ snapshot: EngagementSnapshot, for target: InteractionTarget) {
        snapshots[target] = snapshot
        loadedTargets.insert(target)
        requestedTargets.insert(target)
        pendingTargets.remove(target)
    }

    /// Prefetch counts for visible cards — batches IDs and never cancels in-flight work.
    func prefetch(_ targets: [InteractionTarget]) {
        let fresh = targets.filter {
            !loadedTargets.contains($0) && !requestedTargets.contains($0)
        }
        guard !fresh.isEmpty else { return }

        requestedTargets.formUnion(fresh)
        pendingTargets.formUnion(fresh)
        pumpPrefetchIfNeeded()
    }

    func toggleLike(on target: InteractionTarget) async {
        guard !inFlightLikes.contains(target) else { return }
        inFlightLikes.insert(target)
        defer { inFlightLikes.remove(target) }

        let previous = snapshot(for: target)
        let optimistic = previous.togglingLike()
        snapshots[target] = optimistic
        ExperienceHaptics.play(.selection)

        // Fixture / offline-dev content — keep optimistic state without network.
        if target.id.hasPrefix("dev-") {
            loadedTargets.insert(target)
            requestedTargets.insert(target)
            return
        }

        do {
            try await repository.setLiked(optimistic.viewerHasLiked, on: target)
            loadedTargets.insert(target)
            requestedTargets.insert(target)
        } catch {
            snapshots[target] = previous
            ExperienceHaptics.play(.warning)
        }
    }

    func applyCommentCountDelta(_ delta: Int, on target: InteractionTarget) {
        var snap = snapshot(for: target)
        snap.commentCount = max(0, snap.commentCount + delta)
        snapshots[target] = snap
        loadedTargets.insert(target)
        requestedTargets.insert(target)
    }

    func replaceCommentCount(_ count: Int, on target: InteractionTarget) {
        var snap = snapshot(for: target)
        snap.commentCount = max(0, count)
        snapshots[target] = snap
        loadedTargets.insert(target)
        requestedTargets.insert(target)
    }

    /// Drop engagement cache when the authenticated user changes.
    func removeAll() {
        prefetchTask?.cancel()
        prefetchTask = nil
        snapshots = [:]
        loadedTargets = []
        requestedTargets = []
        pendingTargets = []
        inFlightLikes = []
    }

    // MARK: - Private

    private func pumpPrefetchIfNeeded() {
        guard prefetchTask == nil else { return }
        guard !pendingTargets.isEmpty else { return }

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingTargets.isEmpty {
                let batch = Array(self.pendingTargets)
                self.pendingTargets.removeAll()
                do {
                    let map = try await self.repository.engagement(for: batch)
                    guard !Task.isCancelled else { return }
                    for (target, snap) in map {
                        // Respect seeds / prior loads that landed while the fetch was in flight.
                        guard !self.loadedTargets.contains(target) else { continue }
                        self.snapshots[target] = snap
                        self.loadedTargets.insert(target)
                    }
                } catch {
                    // Soft-fail — allow a later prefetch to retry these IDs.
                    self.requestedTargets.subtract(batch)
                }
            }
            self.prefetchTask = nil
            // Targets enqueued while the last batch was finishing.
            self.pumpPrefetchIfNeeded()
        }
    }
}
