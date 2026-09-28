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
    }

    static func retireAll() {
        viewModels.removeAll()
    }
}
