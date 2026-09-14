#if DEBUG
import Foundation

/// Concise DEBUG summaries for Profile persistent cache + reconciliation.
@MainActor
enum ProfilePersistentCacheProbe {
    private(set) static var profileID: String = "-"
    private(set) static var hit = false
    private(set) static var ageMs: Int = 0
    private(set) static var firstRenderMs: Int = 0
    private(set) static var reconcileMs: Int = 0
    private(set) static var inserted = 0
    private(set) static var updated = 0
    private(set) static var removed = 0
    private(set) static var source: String = "none"

    static func resetForTesting() {
        profileID = "-"
        hit = false
        ageMs = 0
        firstRenderMs = 0
        reconcileMs = 0
        inserted = 0
        updated = 0
        removed = 0
        source = "none"
    }

    static func recordDiskHit(
        profileID: String,
        ageMs value: Int,
        firstRenderMs renderMs: Int
    ) {
        self.profileID = profileID
        hit = true
        ageMs = value
        firstRenderMs = renderMs
        source = "disk"
        print("[ProfilePersistentCache] profile=\(profileID) hit=true ageMs=\(value)")
        print("[ProfilePersistentCache] firstRenderMs=\(renderMs)")
        print("[ProfilePersistentCache] source=disk")
    }

    static func recordNetworkBootstrap(profileID: String) {
        self.profileID = profileID
        hit = false
        source = "network"
        print("[ProfilePersistentCache] profile=\(profileID) hit=false ageMs=0")
        print("[ProfilePersistentCache] source=network")
    }

    static func recordReconcile(
        inserted: Int,
        updated: Int,
        removed: Int,
        durationMs: Int
    ) {
        self.inserted = inserted
        self.updated = updated
        self.removed = removed
        reconcileMs = durationMs
        DiskCacheIOProbe.noteReconciliation()
        print(
            "[ProfilePersistentCache] reconcileMs=\(durationMs) inserted=\(inserted) updated=\(updated) removed=\(removed)"
        )
    }

    static func recordSectionReconcile(
        section: String,
        inserted: Int,
        updated: Int,
        removed: Int
    ) {
        print(
            "[ProfilePersistentCache] section=\(section) inserted=\(inserted) updated=\(updated) removed=\(removed)"
        )
    }
}
#endif
