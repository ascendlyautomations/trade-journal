import Foundation

#if DEBUG
nonisolated enum AnalyticsShadowParity {
    private static let moneyTolerance = 0.01

    static func validate(
        viewerID: ProfileID,
        payload: AnalyticsDailyRangeBootstrapV1,
        scope: AnalyticsLocalStore.IngestScope,
        localRows: [AnalyticsDailyStatRecord],
        coverage: AnalyticsRangeCoverageRecord?
    ) -> Bool {
        let started = Date()
        var parity = true

        if payload.days.count != localRows.count {
            logMismatch(
                "rowCount rpc=\(payload.days.count) local=\(localRows.count)"
            )
            parity = false
        }

        let localByIdentity = Dictionary(uniqueKeysWithValues: localRows.map { ($0.identityKey(), $0) })
        for row in payload.days {
            let key = AnalyticsDailyStatRecord.from(
                row: row,
                viewerID: viewerID.rawValue,
                ingestedRevision: payload.revisionInt
            ).identityKey()
            guard let local = localByIdentity[key] else {
                logMismatch("missing local identity=\(key)")
                parity = false
                continue
            }
            if !metricsMatch(row: row, local: local) {
                parity = false
            }
        }

        let coverageOK = coverage != nil
            && coverage?.server_revision == payload.revisionInt
            && coverage?.start_date == scope.startDate
            && coverage?.end_date == scope.endDate

        if !coverageOK {
            logMismatch("coverage missing or revision/range mismatch")
            parity = false
        }

        if payload.revisionInt != (coverage?.server_revision ?? -1) {
            logMismatch("revision rpc=\(payload.revisionInt) coverage=\(coverage?.server_revision ?? -1)")
            parity = false
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AnalyticsGRDBProbe.logShadowParity(
            viewerID: viewerID.rawValue,
            range: "\(scope.startDate)...\(scope.endDate)",
            mode: scope.modeScope,
            rpcRows: payload.days.count,
            localRows: localRows.count,
            revision: payload.revisionInt,
            coverage: coverageOK,
            parity: parity,
            elapsedMs: elapsed
        )
        return parity
    }

    private static func metricsMatch(row: AnalyticsDailyStatRowV1, local: AnalyticsDailyStatRecord) -> Bool {
        var ok = true
        func checkInt(_ field: String, _ a: Int, _ b: Int) {
            if a != b {
                logMismatch("\(field) rpc=\(a) local=\(b)")
                ok = false
            }
        }
        func checkDouble(_ field: String, _ a: Double, _ b: Double) {
            if abs(a - b) > moneyTolerance {
                logMismatch("\(field) rpc=\(a) local=\(b)")
                ok = false
            }
        }
        checkInt("trade_count", row.trade_count, local.trade_count)
        checkInt("win_count", row.win_count, local.win_count)
        checkInt("loss_count", row.loss_count, local.loss_count)
        checkInt("breakeven_count", row.breakeven_count, local.breakeven_count)
        checkDouble("net_pnl", row.net_pnl.value ?? 0, local.net_pnl)
        checkDouble("gross_profit", row.gross_profit.value ?? 0, local.gross_profit)
        checkDouble("gross_loss", row.gross_loss.value ?? 0, local.gross_loss)
        checkInt("long_count", row.long_count ?? 0, local.long_count)
        checkDouble("long_pnl", row.long_pnl?.value ?? 0, local.long_pnl)
        checkInt("short_count", row.short_count ?? 0, local.short_count)
        checkDouble("short_pnl", row.short_pnl?.value ?? 0, local.short_pnl)
        checkDouble("sum_rr", row.sum_rr?.value ?? 0, local.sum_rr)
        checkInt("rr_count", row.rr_count ?? 0, local.rr_count)
        checkDouble("sum_hold_seconds", row.sum_hold_seconds?.value ?? 0, local.sum_hold_seconds)
        checkInt("hold_count", row.hold_count ?? 0, local.hold_count)
        if let lw = row.largest_win?.value {
            checkDouble("largest_win", lw, local.largest_win ?? 0)
        } else if local.largest_win != nil {
            logMismatch("largest_win rpc=nil local=\(local.largest_win!)")
            ok = false
        }
        if let ll = row.largest_loss?.value {
            checkDouble("largest_loss", ll, local.largest_loss ?? 0)
        } else if local.largest_loss != nil {
            logMismatch("largest_loss rpc=nil local=\(local.largest_loss!)")
            ok = false
        }
        return ok
    }

    private static func logMismatch(_ detail: String) {
        AnalyticsGRDBProbe.logShadowMismatch(detail)
    }
}
#endif
