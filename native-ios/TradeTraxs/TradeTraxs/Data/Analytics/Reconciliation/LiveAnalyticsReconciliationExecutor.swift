import Foundation

nonisolated struct LiveAnalyticsReconciliationExecutor: AnalyticsReconciliationExecuting {
    func reconcileDashboard(
        viewerID: ProfileID,
        hintRevision: Int64?,
        generation: UInt64
    ) async throws -> AnalyticsDashboardReconcileResult {
        _ = hintRevision
        guard let rpc = AnalyticsReconciliationRuntime.rpc else {
            throw AnalyticsReconciliationExecutorError.missingRuntime("rpc")
        }
        let started = Date()
        let flightKey = AnalyticsReconciliationFlightKeys.dashboardV3(viewerID: viewerID.rawValue)
        let encoded = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
            let repo = AnalyticsDashboardBootstrapRepository(rpc: rpc)
            let bootstrap = try await repo.load()
            return try JSONEncoder().encode(bootstrap)
        }
        let bootstrap = try JSONDecoder().decode(AnalyticsDashboardBootstrapV3.self, from: encoded)
        try Task.checkCancellation()

        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: viewerID.rawValue,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: bootstrap.data.revisionInt,
                savedAt: Date(),
                payload: bootstrap
            )
        )

        await AnalyticsDashboardShadowWriter.ingestBootstrap(
            viewerID: viewerID,
            bootstrap: bootstrap
        )

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        await AnalyticsReconciliationUIApply.postDashboardCommitted(
            viewerID: viewerID,
            serverRevision: bootstrap.data.revisionInt,
            viewerGeneration: generation
        )
        return AnalyticsDashboardReconcileResult(
            serverRevision: bootstrap.data.revisionInt,
            elapsedMs: elapsed
        )
    }

    func reconcileCalendar(
        intent: AnalyticsCalendarRangeIntent,
        generation: UInt64
    ) async throws -> AnalyticsCalendarReconcileResult {
        guard let rpc = AnalyticsReconciliationRuntime.rpc else {
            throw AnalyticsReconciliationExecutorError.missingRuntime("rpc")
        }
        let accountID = intent.accountScope == AnalyticsScopeKeys.allAccountsQuery
            ? nil
            : intent.accountScope
        let mode = intent.modeScope == AnalyticsScopeKeys.allModesQuery
            ? nil
            : intent.modeScope

        let started = Date()
        let flightKey = AnalyticsReconciliationFlightKeys.calendarRange(
            viewerID: intent.viewerID.rawValue,
            start: intent.startDate,
            end: intent.endDate,
            accountScope: intent.accountScope,
            modeScope: intent.modeScope
        )
        let encoded = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
            let payload = try await AnalyticsCalendarBootstrapLoader.loadDailyRange(
                rpc: rpc,
                start: intent.startDate,
                end: intent.endDate,
                accountID: accountID,
                mode: mode
            )
            return try JSONEncoder().encode(payload)
        }
        let payload = try JSONDecoder().decode(AnalyticsDailyRangeBootstrapV1.self, from: encoded)
        try Task.checkCancellation()

        await AnalyticsShadowWriter.ingestCalendarDailyRange(
            viewerID: intent.viewerID,
            payload: payload,
            startDate: intent.startDate,
            endDate: intent.endDate,
            queryAccountID: accountID,
            queryMode: mode
        )

        persistCalendarMonthCacheIfNeeded(
            viewerID: intent.viewerID,
            payload: payload,
            startDate: intent.startDate,
            endDate: intent.endDate,
            modeFilter: mode
        )

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        await AnalyticsReconciliationUIApply.postCalendarCommitted(
            viewerID: intent.viewerID,
            intent: intent,
            serverRevision: payload.revisionInt,
            viewerGeneration: generation
        )
        return AnalyticsCalendarReconcileResult(
            serverRevision: payload.revisionInt,
            rowsWritten: payload.days.count,
            elapsedMs: elapsed
        )
    }

    func reconcileAccountCharts(
        intent: AccountChartsReconcileIntent,
        generation: UInt64
    ) async throws {
        _ = intent
        _ = generation
        await MainActor.run {
            DashboardAnalyticsAccountChartsStore.shared.invalidate()
        }
    }

    private func persistCalendarMonthCacheIfNeeded(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        startDate: String,
        endDate: String,
        modeFilter: String?
    ) {
        guard let startComponents = AnalyticsCalendarDay.components(from: startDate),
              let endComponents = AnalyticsCalendarDay.components(from: endDate),
              startComponents.year == endComponents.year,
              startComponents.month == endComponents.month,
              let bounds = AnalyticsCalendarDay.civilMonthDateBounds(
                  year: startComponents.year,
                  month: startComponents.month
              ),
              bounds.start == startDate,
              bounds.end == endDate
        else { return }

        let monthKey = String(format: "%04d-%02d", startComponents.year, startComponents.month)
        let blob = CalendarAnalyticsMonthDiskCache.Blob(
            viewerID: viewerID.rawValue,
            monthKey: monthKey,
            modeFilter: modeFilter,
            contractVersion: BackendV2Versioning.contractVersion,
            schemaVersion: CalendarAnalyticsMonthDiskCache.schemaVersion,
            revision: payload.revisionInt,
            savedAt: Date(),
            payload: payload
        )
        CalendarAnalyticsMonthDiskCache.save(blob)
    }
}

enum AnalyticsReconciliationExecutorError: Error {
    case missingRuntime(String)
    case viewerGenerationMismatch
    case grdbPersistFailed(String)
}
