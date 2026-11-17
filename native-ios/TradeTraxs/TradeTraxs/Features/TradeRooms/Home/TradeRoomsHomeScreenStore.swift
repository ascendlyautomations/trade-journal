import Foundation

/// Stable Trade Rooms home view-model ownership across SwiftUI `View.init` re-evaluations.
///
/// `navigationDestination` rebuilds destination views on parent body updates; constructing
/// `TradeRoomsHomeViewModel` directly in `State(initialValue:)` allocates a new instance
/// on every init even when `@State` storage is preserved. This store returns one VM per host
/// for the mounted screen lifetime.
@MainActor
enum TradeRoomsHomeScreenStore {
    private static var viewModels: [TradeRoomNavigationHost: TradeRoomsHomeViewModel] = [:]
    private static var pendingDiscoveryScope: [TradeRoomNavigationHost: TradeRoomDiscoveryScope] = [:]

    static func viewModel(
        host: TradeRoomNavigationHost,
        make: () -> TradeRoomsHomeViewModel
    ) -> TradeRoomsHomeViewModel {
        if let existing = viewModels[host] {
            return existing
        }
        let created = make()
        viewModels[host] = created
        return created
    }

    static func retire(host: TradeRoomNavigationHost) {
        viewModels.removeValue(forKey: host)
        pendingDiscoveryScope.removeValue(forKey: host)
    }

    static func retireAll() {
        viewModels.removeAll()
        pendingDiscoveryScope.removeAll()
    }

    /// Deep links / onboarding — apply once when Trade Rooms home mounts (e.g. Getting Started → All).
    static func requestDiscoveryScope(
        _ scope: TradeRoomDiscoveryScope,
        host: TradeRoomNavigationHost
    ) {
        pendingDiscoveryScope[host] = scope
        if let existing = viewModels[host] {
            existing.selectDiscoveryScope(scope)
            pendingDiscoveryScope.removeValue(forKey: host)
        }
    }

    static func consumePendingDiscoveryScope(
        for host: TradeRoomNavigationHost
    ) -> TradeRoomDiscoveryScope? {
        pendingDiscoveryScope.removeValue(forKey: host)
    }
}
