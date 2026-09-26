import Foundation
import Observation

/// Compares dashboard cache owners without treating case or surrounding space as a different user.
nonisolated enum DashboardSessionIsolation {
    static func normalizedOwner(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func ownersMatch(_ owner: String, _ activeViewerID: String?) -> Bool {
        guard let activeViewerID else { return false }
        let left = normalizedOwner(owner)
        let right = normalizedOwner(activeViewerID)
        return !left.isEmpty && left == right
    }
}

/// Authenticated viewer the dashboard is allowed to render.
///
/// Logout locks display immediately. The next login binds a new viewer before cached
/// rows may paint. Viewer-keyed disk and GRDB rows are not deleted here.
@MainActor
@Observable
final class SessionViewerGate {
    static let shared = SessionViewerGate()

    private(set) var epoch: UInt64 = 0
    private(set) var activeViewerID: String?
    private(set) var displayLocked = false

    /// Tests and screenshot sessions that never bind a viewer.
    var allowsUnscopedFallback: Bool {
        !displayLocked && activeViewerID == nil
    }

    func bind(_ rawViewerID: String) {
        let next = DashboardSessionIsolation.normalizedOwner(rawViewerID)
        guard !next.isEmpty else { return }
        if activeViewerID == next, !displayLocked { return }
        epoch &+= 1
        activeViewerID = next
        displayLocked = false
    }

    func endSession() {
        epoch &+= 1
        activeViewerID = nil
        displayLocked = true
    }

    func allowsDisplay(owner: String) -> Bool {
        if allowsUnscopedFallback { return true }
        return DashboardSessionIsolation.ownersMatch(owner, activeViewerID)
    }

    func resetForTesting() {
        epoch = 0
        activeViewerID = nil
        displayLocked = false
    }
}

/// In-memory Dashboard presentation reset. Does not delete viewer-keyed disk or GRDB.
@MainActor
enum DashboardSessionBoundary {
    static func resetInMemoryPresentation() {
        SessionViewerGate.shared.endSession()
        DashboardViewModel.resetAllForSessionBoundary()
        DashboardAnalyticsAggregateChartsStore.shared.invalidate()
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
    }
}
