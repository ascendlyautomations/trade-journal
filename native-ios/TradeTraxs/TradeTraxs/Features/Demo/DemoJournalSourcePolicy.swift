import Foundation

/// Chooses rolling vs published snapshot rows for demo journal fields.
nonisolated enum DemoJournalSourcePolicy {
    /// TraxsPro Preview and bundled fallback always use the rolling journal.
    static var usesRollingJournal: Bool {
        if TraxsProPreviewRuntimeFlag.usesCanonicalJournalSampleData {
            return true
        }
        return DemoSnapshotStore.shared.current == nil
    }
}