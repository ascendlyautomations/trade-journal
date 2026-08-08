import Foundation

/// Tab-scoped helpers for retained stacks.
///
/// Thin façade over ``NavigationCoordinator`` for feature modules that only
/// need their own tab's push/pop vocabulary.
struct TabCoordinator: Sendable {
    let tab: TabIdentifier

    func rootDestination(for tab: TabIdentifier) -> AppDestination {
        .tab(tab)
    }

    func popToRootDestination() -> AppDestination {
        .popToRoot(tab)
    }
}
