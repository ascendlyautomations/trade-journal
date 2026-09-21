import Foundation

/// Presentation-scoped generation + active subject for Profile analytics (Phase 7E).
actor ProfileAnalyticsGRDBSession {
    static let shared = ProfileAnalyticsGRDBSession()

    private var generation: UInt64 = 0
    private var activeSubjectProfileID: String?

    func reset() {
        generation &+= 1
        activeSubjectProfileID = nil
    }

    func currentGeneration() -> UInt64 {
        generation
    }

    func setActiveSubjectProfile(_ profileID: String) {
        activeSubjectProfileID = profileID
    }

    func isActiveSubjectProfile(_ profileID: String) -> Bool {
        activeSubjectProfileID == profileID
    }
}
