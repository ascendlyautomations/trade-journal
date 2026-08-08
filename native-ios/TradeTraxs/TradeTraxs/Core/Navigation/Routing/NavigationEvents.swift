import Foundation

/// Navigation lifecycle events for logging / future analytics.
///
/// Not a service locator — observers subscribe via coordinator hooks later.
enum NavigationEvent: Sendable, Equatable {
    case sessionPhaseChanged(SessionPhase)
    case tabSelected(TabIdentifier)
    case createActionInvoked
    case pushed(tab: TabIdentifier, description: String)
    case popped(tab: TabIdentifier)
    case poppedToRoot(TabIdentifier)
    case sheetPresented(SheetDestination)
    case fullScreenPresented(FullScreenDestination)
    case presentationDismissed
    case deepLinkResolved(AppDestination)
    case deepLinkFailed(String)
    case notificationResolved(AppDestination)
    case notificationFailed(String)
    case stateRestored
    case statePersisted
}
