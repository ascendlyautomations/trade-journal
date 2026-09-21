import Foundation

#if DEBUG
/// DEBUG-only cold-start and post-hydration shadow reads (utility priority — never blocks UI).
enum AnalyticsShadowReadCoordinator {
    private static var coldStartProbeRanForViewer: Set<String> = []
    private static let lock = NSLock()

    static func scheduleColdStartProbeIfNeeded(viewerID: ProfileID) {
        let key = viewerID.rawValue.lowercased()
        lock.lock()
        let shouldRun = !coldStartProbeRanForViewer.contains(key)
        if shouldRun { coldStartProbeRanForViewer.insert(key) }
        lock.unlock()
        guard shouldRun else { return }

        Task(priority: .utility) {
            await runColdStartProbe(viewerID: viewerID)
        }
    }

    static func runColdStartProbe(viewerID: ProfileID) async {
        let openStarted = Date()
        let store = AnalyticsLocalStore()
        do {
            _ = try await store.syncState(viewerID: viewerID)
            let openMs = Int(Date().timeIntervalSince(openStarted) * 1000)
            AnalyticsGRDBProbe.logOpen(elapsedMs: openMs)

            if let disk = DashboardAnalyticsDiskCache.load(viewerID: viewerID) {
                let revision = disk.revision
                let read = try await store.readDashboardSnapshot(
                    viewerID: viewerID,
                    requiredRevision: revision
                )
                AnalyticsGRDBProbe.logDashboardReadParity(
                    viewerID: viewerID.rawValue,
                    revision: revision,
                    scope: "coldStart",
                    preset: "snapshot",
                    state: read.state,
                    parity: read.state == .available,
                    elapsedMs: 0
                )
            }

            if let month = CalendarMonthID.currentOptional() {
                let cacheKey = month.cacheKey
                if let calDisk = CalendarAnalyticsMonthDiskCache.load(
                    viewerID: viewerID,
                    monthKey: cacheKey,
                    modeFilter: nil
                ),
                    let bounds = AnalyticsCalendarDay.civilMonthDateBounds(
                        year: month.year,
                        month: month.month
                    )
                {
                    let read = try await store.readCalendarRange(
                        viewerID: viewerID,
                        startDate: bounds.start,
                        endDate: bounds.end,
                        queryAccountID: nil,
                        queryMode: nil,
                        requiredRevision: calDisk.revision
                    )
                    AnalyticsGRDBProbe.logCalendarReadParity(
                        viewerID: viewerID.rawValue,
                        range: "\(bounds.start)...\(bounds.end)",
                        requiredRevision: calDisk.revision,
                        state: read.state,
                        localRows: read.dailyRows.count,
                        currentRows: calDisk.payload.days.count,
                        parity: read.state == .available,
                        elapsedMs: 0
                    )
                }
            }

            _ = await AnalyticsDatabase.shared.storageByteEstimate()
        } catch {
            AnalyticsGRDBProbe.logShadowMismatch("coldStartProbe \(error)")
        }
    }

    static func resetColdStartProbeForTests() {
        lock.lock()
        coldStartProbeRanForViewer.removeAll()
        lock.unlock()
    }
}

private extension CalendarMonthID {
    static func currentOptional(now: Date = Date()) -> CalendarMonthID? {
        CalendarMonthID.current(now: now)
    }
}
#endif
