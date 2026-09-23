import Foundation

#if DEBUG
/// Shadow-read parity — compares GRDB reconstruction to production analytical state (no UI effect).
nonisolated enum AnalyticsShadowReadParity {
    private static let moneyTolerance = 0.01

    static func validateCalendarAfterIngest(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        startDate: String,
        endDate: String,
        queryAccountID: String?,
        queryMode: String?,
        accountFilter: DashboardAccountFilter,
        modeFilter: String?
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        let started = Date()
        do {
            let read = try await store.readCalendarRange(
                viewerID: viewerID,
                startDate: startDate,
                endDate: endDate,
                queryAccountID: queryAccountID,
                queryMode: queryMode,
                requiredRevision: payload.revisionInt
            )
            let parity = calendarParity(
                read: read,
                payload: payload,
                accountFilter: accountFilter,
                modeFilter: modeFilter,
                startDate: startDate,
                endDate: endDate
            )
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            AnalyticsGRDBProbe.logCalendarReadParity(
                viewerID: viewerID.rawValue,
                range: "\(startDate)...\(endDate)",
                requiredRevision: payload.revisionInt,
                state: read.state,
                localRows: read.dailyRows.count,
                currentRows: payload.days.count,
                parity: parity,
                elapsedMs: elapsed
            )
            _ = await AnalyticsDatabase.shared.storageByteEstimate()
        } catch {
            AnalyticsGRDBProbe.logShadowMismatch("calendarRead \(error)")
        }
    }

    static func validateCalendarAgainstAuthoritative(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        startDate: String,
        endDate: String,
        queryAccountID: String?,
        queryMode: String?,
        accountFilter: DashboardAccountFilter,
        modeFilter: String?,
        year: Int,
        month: Int
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        let started = Date()
        do {
            let read = try await store.readCalendarRange(
                viewerID: viewerID,
                startDate: startDate,
                endDate: endDate,
                queryAccountID: queryAccountID,
                queryMode: queryMode,
                requiredRevision: payload.revisionInt
            )
            let parity = calendarMonthParity(
                read: read,
                payload: payload,
                accountFilter: accountFilter,
                modeFilter: modeFilter,
                year: year,
                month: month
            )
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            AnalyticsGRDBProbe.logCalendarReadParity(
                viewerID: viewerID.rawValue,
                range: "\(startDate)...\(endDate)",
                requiredRevision: payload.revisionInt,
                state: read.state,
                localRows: read.wireRows.count,
                currentRows: payload.days.count,
                parity: parity,
                elapsedMs: elapsed
            )
        } catch {
            AnalyticsGRDBProbe.logShadowMismatch("calendarAuthoritativeRead \(error)")
        }
    }

    static func validateDashboardSnapshot(
        viewerID: ProfileID,
        bootstrap: AnalyticsDashboardBootstrapV3
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        let revision = bootstrap.data.revisionInt
        let started = Date()
        do {
            let read = try await store.readDashboardSnapshot(
                viewerID: viewerID,
                requiredRevision: revision
            )
            let parity = dashboardSnapshotParity(read: read, bootstrap: bootstrap)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            AnalyticsGRDBProbe.logDashboardReadParity(
                viewerID: viewerID.rawValue,
                revision: revision,
                scope: "bootstrap",
                preset: "all",
                state: read.state,
                parity: parity,
                elapsedMs: elapsed
            )
            compareDashboardJSONDisk(viewerID: viewerID, bootstrap: bootstrap, grdb: read)
        } catch {
            AnalyticsGRDBProbe.logShadowMismatch("dashboardRead \(error)")
        }
    }

    static func validateAccountChartsRead(
        viewerID: ProfileID,
        accountID: TradingAccountID,
        revision: Int64,
        response: AnalyticsDashboardAccountChartsV3
    ) async {
        let store = AnalyticsLocalStore.sharedStore()
        let started = Date()
        do {
            let read = try await store.readDashboardAccountCharts(
                viewerID: viewerID,
                accountID: accountID,
                requiredRevision: revision
            )
            var parity = read.state == .available
            if read.state == .available {
                for (key, wire) in response.data.presets {
                    guard let local = read.presets[key] else {
                        AnalyticsGRDBProbe.logShadowMismatch("accountChartsRead missing preset \(key)")
                        parity = false
                        continue
                    }
                    if local.equity.points.count != wire.equity.points.count {
                        AnalyticsGRDBProbe.logShadowMismatch("accountChartsRead equity \(key)")
                        parity = false
                    }
                }
            } else {
                parity = false
            }
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            AnalyticsGRDBProbe.logAccountChartsReadParity(
                viewerID: viewerID.rawValue,
                account: accountID.rawValue,
                revision: revision,
                state: read.state,
                presets: read.presets.count,
                parity: parity,
                elapsedMs: elapsed
            )
        } catch {
            AnalyticsGRDBProbe.logShadowMismatch("accountChartsRead \(error)")
        }
    }

    // MARK: - Calendar

    private static func calendarParity(
        read: AnalyticsCalendarRangeReadResult,
        payload: AnalyticsDailyRangeBootstrapV1,
        accountFilter: DashboardAccountFilter,
        modeFilter: String?,
        startDate: String,
        endDate: String
    ) -> Bool {
        guard read.state == .available else {
            AnalyticsGRDBProbe.logShadowMismatch("calendarRead state=\(read.state)")
            return false
        }
        let rpcScoped = CalendarAnalyticsAggregator.filteredRows(
            payload.days,
            accountFilter: accountFilter,
            modeFilter: modeFilter
        )
        let localScoped = CalendarAnalyticsAggregator.filteredRows(
            read.wireRows,
            accountFilter: accountFilter,
            modeFilter: modeFilter
        )
        return rowSetParity(rpcScoped, localScoped)
    }

    private static func calendarMonthParity(
        read: AnalyticsCalendarRangeReadResult,
        payload: AnalyticsDailyRangeBootstrapV1,
        accountFilter: DashboardAccountFilter,
        modeFilter: String?,
        year: Int,
        month: Int
    ) -> Bool {
        guard read.state == .available else { return false }
        let fromRPC = CalendarAnalyticsAggregator.buildMonth(
            year: year,
            month: month,
            rows: payload.days,
            accountFilter: accountFilter,
            modeFilter: modeFilter
        )
        let fromGRDB = CalendarAnalyticsAggregator.buildMonth(
            year: year,
            month: month,
            rows: read.wireRows,
            accountFilter: accountFilter,
            modeFilter: modeFilter
        )
        return monthParity(fromRPC, fromGRDB)
    }

    private static func monthParity(_ a: TradingCalendarMonth, _ b: TradingCalendarMonth) -> Bool {
        var ok = true
        if a.monthSummary.netPnL != b.monthSummary.netPnL {
            logCalendarMetric("monthNetPnL", "\(a.monthSummary.netPnL)", "\(b.monthSummary.netPnL)")
            ok = false
        }
        if a.monthSummary.tradeCount != b.monthSummary.tradeCount {
            logCalendarMetric("monthTradeCount", "\(a.monthSummary.tradeCount)", "\(b.monthSummary.tradeCount)")
            ok = false
        }
        if a.days.count != b.days.count {
            logCalendarMetric("dayKeyCount", "\(a.days.count)", "\(b.days.count)")
            ok = false
        }
        for (key, summaryA) in a.days {
            guard let summaryB = b.days[key] else {
                logCalendarMetric("missingDay", key, "nil")
                ok = false
                continue
            }
            if summaryA.netPnL != summaryB.netPnL || summaryA.tradeCount != summaryB.tradeCount {
                logCalendarMetric(
                    "day|\(key)",
                    "pnl=\(summaryA.netPnL) trades=\(summaryA.tradeCount)",
                    "pnl=\(summaryB.netPnL) trades=\(summaryB.tradeCount)"
                )
                ok = false
            }
        }
        return ok
    }

    private static func rowSetParity(_ a: [AnalyticsDailyStatRowV1], _ b: [AnalyticsDailyStatRowV1]) -> Bool {
        if a.count != b.count {
            logCalendarMetric("rowCount", "\(a.count)", "\(b.count)")
            return false
        }
        let keyedA = Dictionary(uniqueKeysWithValues: a.map { (rowIdentity($0), $0) })
        for row in b {
            let key = rowIdentity(row)
            guard let other = keyedA[key] else {
                logCalendarMetric("missingRow", key, "nil")
                return false
            }
            if abs((row.net_pnl.value ?? 0) - (other.net_pnl.value ?? 0)) > moneyTolerance {
                logCalendarMetric("net_pnl|\(key)", "\(row.net_pnl.value ?? 0)", "\(other.net_pnl.value ?? 0)")
                return false
            }
            if row.trade_count != other.trade_count {
                logCalendarMetric("trade_count|\(key)", "\(row.trade_count)", "\(other.trade_count)")
                return false
            }
        }
        return true
    }

    private static func rowIdentity(_ row: AnalyticsDailyStatRowV1) -> String {
        let account = row.account_id ?? AnalyticsScopeKeys.nullAccountRow
        let mode = row.mode_effective ?? AnalyticsScopeKeys.allModesQuery
        return "\(row.calendar_day)|\(mode)|\(account)"
    }

    private static func logCalendarMetric(_ field: String, _ left: String, _ right: String) {
        AnalyticsGRDBProbe.logShadowMismatch("calendarRead \(field) current=\(left) grdb=\(right)")
    }

    // MARK: - Dashboard

    private static func dashboardSnapshotParity(
        read: AnalyticsDashboardSnapshotReadResult,
        bootstrap: AnalyticsDashboardBootstrapV3
    ) -> Bool {
        guard read.state == .available, let snapshot = read.snapshot else {
            AnalyticsGRDBProbe.logShadowMismatch("dashboardRead state=\(read.state)")
            return false
        }
        var ok = true
        for (key, bundle) in bootstrap.data.aggregatePresets {
            guard let local = snapshot.aggregatePresets[key] else {
                AnalyticsGRDBProbe.logShadowMismatch("dashboardRead missing aggregate \(key)")
                ok = false
                continue
            }
            if !metricsWireMatch(bundle.metrics, local.metrics) {
                ok = false
            }
            if bundle.equity.points.count != local.equity.points.count {
                AnalyticsGRDBProbe.logShadowMismatch("dashboardRead equity \(key)")
                ok = false
            }
        }
        return ok
    }

    private static func metricsWireMatch(
        _ a: AnalyticsDashboardMetricsWireV1,
        _ b: AnalyticsDashboardMetricsWireV1
    ) -> Bool {
        a.trade_count == b.trade_count
            && a.win_count == b.win_count
            && abs((a.net_pnl.value ?? 0) - (b.net_pnl.value ?? 0)) <= moneyTolerance
    }

    private static func compareDashboardJSONDisk(
        viewerID: ProfileID,
        bootstrap: AnalyticsDashboardBootstrapV3,
        grdb: AnalyticsDashboardSnapshotReadResult
    ) {
        guard let disk = DashboardAnalyticsDiskCache.load(viewerID: viewerID) else { return }
        if disk.revision != bootstrap.data.revisionInt {
            AnalyticsGRDBProbe.logShadowMismatch(
                "jsonDisk revision=\(disk.revision) bootstrap=\(bootstrap.data.revisionInt)"
            )
        }
        if grdb.state == .available, let snapshot = grdb.snapshot {
            let diskPresets = disk.payload.data.aggregatePresets
            for key in AnalyticsLocalDashboardPolicy.aggregatePresetKeys {
                guard
                    let jsonBundle = diskPresets[key],
                    let grdbBundle = snapshot.aggregatePresets[key]
                else { continue }
                if jsonBundle.metrics.trade_count != grdbBundle.metrics.trade_count {
                    AnalyticsGRDBProbe.logShadowMismatch(
                        "jsonVsGrdb trade_count preset=\(key) json=\(jsonBundle.metrics.trade_count) grdb=\(grdbBundle.metrics.trade_count)"
                    )
                }
            }
            print(
                "[AnalyticsGRDB][JsonVsGrdb] note=meta.accounts payout_total not stored in GRDB dashboard tables"
            )
        }
    }
}
#endif
