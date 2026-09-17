import Foundation

enum ProfileSectionInitialLoad {
    /// True while ``ProfileScreenViewModel`` still owns the first authoritative section payload.
    static func awaitingScreenBootstrap(
        isScreenOwned: Bool,
        snapshot: ProfileState,
        didLoadSection: Bool,
        sectionItemsEmpty: Bool,
        localItemsEmpty: Bool
    ) -> Bool {
        guard isScreenOwned, localItemsEmpty, !didLoadSection, sectionItemsEmpty else { return false }
        return snapshot.phase == .loading
    }

    /// Plan state + deferred fetch when bootstrap omitted this section. No inout — caller assigns once, then kicks load.
    struct BootstrapMissingSectionPlan: Equatable, Sendable {
        var nextState: ProfileSectionLoadState?
        var kickDeferredLoad: Bool
    }

    /// Bootstrap snapshot omitted this section (Stage 1 / partial publish). Never downgrade a completed load to loading.
    static func planWhenBootstrapOmitsSectionPayload(
        snapshot: ProfileState,
        hasLoaded: Bool,
        itemsEmpty: Bool,
        itemCount: Int,
        currentState: ProfileSectionLoadState,
        awaitingScreenBootstrap: Bool
    ) -> BootstrapMissingSectionPlan {
        if hasLoaded {
            return BootstrapMissingSectionPlan(
                nextState: itemsEmpty ? .empty : .loaded(itemCount: itemCount),
                kickDeferredLoad: false
            )
        }

        var nextState: ProfileSectionLoadState?
        if (snapshot.phase == .loading || snapshot.didBootstrap), itemsEmpty {
            nextState = .loading
        } else if itemsEmpty, case .idle = currentState {
            nextState = .loading
        }

        let kickDeferredLoad = !awaitingScreenBootstrap && !hasLoaded
        return BootstrapMissingSectionPlan(
            nextState: nextState,
            kickDeferredLoad: kickDeferredLoad
        )
    }

    /// Applies ``BootstrapMissingSectionPlan`` without re-entering ``state`` while mutating it.
    @MainActor
    static func applyBootstrapMissingSectionPlan(
        _ plan: BootstrapMissingSectionPlan,
        setState: (ProfileSectionLoadState) -> Void,
        kickDeferredLoad: () -> Void
    ) {
        if let nextState = plan.nextState {
            setState(nextState)
        }
        if plan.kickDeferredLoad {
            kickDeferredLoad()
        }
    }
}

@MainActor
final class ProfileSectionFailureGrace {
    private var task: Task<Void, Never>?
    private static let graceNanoseconds: UInt64 = 650_000_000

    func cancel() {
        task?.cancel()
        task = nil
    }

    func scheduleIfNeeded(
        message: String,
        shouldPresent: @escaping @MainActor () -> Bool,
        present: @escaping @MainActor (String) -> Void
    ) {
        cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.graceNanoseconds)
            guard !Task.isCancelled else { return }
            guard shouldPresent() else { return }
            present(message)
        }
    }
}
