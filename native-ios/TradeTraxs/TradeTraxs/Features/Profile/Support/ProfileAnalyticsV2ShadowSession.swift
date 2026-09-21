import Foundation

/// Viewer-scoped generation + per-profile shadow dedupe (Phase 7D — no UI effect).
actor ProfileAnalyticsV2ShadowSession {
    static let shared = ProfileAnalyticsV2ShadowSession()

    private var generation: UInt64 = 0
    private var completedKeys: Set<String> = []
    private var activeSubjectProfileID: String?

    func reset() {
        generation &+= 1
        completedKeys.removeAll()
        activeSubjectProfileID = nil
    }

    func setActiveSubjectProfile(_ profileID: String) {
        activeSubjectProfileID = profileID
    }

    func isActiveSubjectProfile(_ profileID: String) -> Bool {
        activeSubjectProfileID == profileID
    }

    func currentGeneration() -> UInt64 {
        generation
    }

    /// Returns false when this profile session already shadowed (unchanged visit).
    func beginShadowSessionKey(_ key: String) -> Bool {
        if completedKeys.contains(key) {
            return false
        }
        completedKeys.insert(key)
        return true
    }

    func clearShadowKeys(forSubjectProfile profileID: String) {
        completedKeys = completedKeys.filter { !$0.contains("|\(profileID)|") }
    }
}
