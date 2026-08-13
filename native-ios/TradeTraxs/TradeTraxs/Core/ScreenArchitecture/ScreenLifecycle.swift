import Foundation

/// Standard screen / domain lifecycle API.
///
/// Every Profile / Feed / Messaging-style owner should expose these entry points
/// (directly or via thin wrappers over existing `loadIfNeeded` / `stopRealtime` names).
///
/// Prefer composition: a screen view model holds repositories + state and *calls*
/// a ``ScreenBootstrap`` type — do not inherit a base view-model class.
@MainActor
protocol ScreenLifecycle: AnyObject {
    associatedtype State: ScreenStateModeling

    var state: State { get }

    /// First paint: no-op when already bootstrapped (unless the feature opts into force).
    func bootstrapIfNeeded() async

    /// Explicit refresh (pull-to-refresh or equivalent). May re-run bootstrap with `force`.
    func refresh() async

    /// Pagination page-in. No-op for non-paginated screens.
    func loadMore() async

    /// Begin realtime subscriptions for this screen / domain.
    func subscribeRealtime()

    /// Tear down realtime subscriptions.
    func unsubscribeRealtime()
}

/// Optional realtime event intake for screens that mutate state from channel payloads.
@MainActor
protocol ScreenRealtimeHandling: AnyObject {
    associatedtype Event

    func handleRealtimeEvent(_ event: Event)
}

extension ScreenLifecycle {
    func loadMore() async {}
    func subscribeRealtime() {}
    func unsubscribeRealtime() {}
}
