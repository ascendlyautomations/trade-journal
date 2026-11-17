import Foundation

/// In-memory GRDB presentation cache — avoids repeated full-table reads and JSON decode per cold path.
nonisolated enum AnalyticsDashboardGRDBSessionCache {
    struct PresentationSnapshot: Sendable {
        var revision: Int64
        var snapshot: AnalyticsLocalDashboardV3Snapshot
        var aggregateCharts: [String: AnalyticsDashboardChartsPresetV1]
    }

    private struct ViewerEntry: Sendable {
        var presentation: PresentationSnapshot?
        var accountCharts: [String: [String: AnalyticsDashboardChartsPresetV1]]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [String: ViewerEntry] = [:]

    static func presentationSnapshot(
        viewerID: ProfileID,
        revision: Int64
    ) -> PresentationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[normalized(viewerID)],
              let presentation = entry.presentation,
              presentation.revision == revision
        else { return nil }
        return presentation
    }

    static func storePresentation(
        viewerID: ProfileID,
        presentation: PresentationSnapshot
    ) {
        lock.lock()
        defer { lock.unlock() }
        let key = normalized(viewerID)
        var entry = entries[key] ?? ViewerEntry(presentation: nil, accountCharts: [:])
        entry.presentation = presentation
        entries[key] = entry
    }

    static func aggregateCharts(
        viewerID: ProfileID,
        revision: Int64
    ) -> [String: AnalyticsDashboardChartsPresetV1]? {
        lock.lock()
        defer { lock.unlock() }
        guard let presentation = entries[normalized(viewerID)]?.presentation,
              presentation.revision == revision,
              !presentation.aggregateCharts.isEmpty
        else { return nil }
        return presentation.aggregateCharts
    }

    static func accountCharts(
        viewerID: ProfileID,
        accountScopeKey: String,
        revision: Int64
    ) -> [String: AnalyticsDashboardChartsPresetV1]? {
        lock.lock()
        defer { lock.unlock() }
        guard let stored = entries[normalized(viewerID)]?.accountCharts[accountScopeKey],
              !stored.isEmpty
        else { return nil }
        return stored
    }

    static func storeAccountCharts(
        viewerID: ProfileID,
        accountScopeKey: String,
        revision: Int64,
        presets: [String: AnalyticsDashboardChartsPresetV1]
    ) {
        lock.lock()
        defer { lock.unlock() }
        let key = normalized(viewerID)
        var entry = entries[key] ?? ViewerEntry(presentation: nil, accountCharts: [:])
        entry.accountCharts[accountScopeKey] = presets
        if var presentation = entry.presentation, presentation.revision != revision {
            presentation.revision = revision
            entry.presentation = presentation
        }
        entries[key] = entry
    }

    static func invalidate(viewerID: ProfileID) {
        lock.lock()
        entries[normalized(viewerID)] = nil
        lock.unlock()
    }

    static func resetAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    static func decodeAggregateChartPresets(
        from bundles: [DashboardChartBundleRecord]
    ) -> [String: AnalyticsDashboardChartsPresetV1] {
        var presets: [String: AnalyticsDashboardChartsPresetV1] = [:]
        for bundle in bundles {
            if let decoded = try? bundle.decodedCharts() {
                presets[bundle.preset_key] = decoded
            }
        }
        return presets
    }

    private static func normalized(_ viewerID: ProfileID) -> String {
        viewerID.rawValue.lowercased()
    }
}