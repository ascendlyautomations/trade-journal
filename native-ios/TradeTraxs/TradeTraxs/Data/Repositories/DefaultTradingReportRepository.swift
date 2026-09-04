import Foundation

/// Native Trading Reports — mirrors web `ensureTradingReportsLoaded` + notify.
///
/// Report bodies are generated locally with ``TradingReportGenerator`` (web
/// `generateTradingReport.ts`). The only BFF call is optional notify.
actor DefaultTradingReportRepository: TradingReportRepository {
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let supabase: SupabaseInfrastructure

    private var snapshot: TradingReportsSnapshot?
    private var tradeFingerprint: String?
    private var cachedEligibleTrades: [Trade] = []
    private var yearlyCache: [String: TradingYearlyReport] = [:]
    private var notifiedKeys = Set<String>()

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        supabase: SupabaseInfrastructure
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.supabase = supabase
    }

    func ensureSnapshot(forceNetwork: Bool) async throws -> TradingReportsSnapshot {
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        let fingerprint = Self.fingerprint(eligible)

        if !forceNetwork,
           let snapshot,
           tradeFingerprint == fingerprint {
            return snapshot
        }

        let reports = TradingReportGenerator.generateAll(trades: eligible)
        let next = TradingReportsSnapshot(
            reports: reports,
            computedAt: Date().timeIntervalSince1970 * 1000
        )
        snapshot = next
        tradeFingerprint = fingerprint
        yearlyCache = [:]

        await maybeNotify(userID: await session.currentUserID?.rawValue, snapshot: next)
        return next
    }

    func report(
        for periodKey: TradingReportPeriodKey,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        let snapshot = try await ensureSnapshot(forceNetwork: forceNetwork)
        guard let report = snapshot.report(for: periodKey) else {
            throw AppError.unknown(message: "Report unavailable for \(periodKey.rawValue).")
        }
        return report
    }

    func availableYears(forceNetwork: Bool) async throws -> [Int] {
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        return TradingYearlyReportGenerator.availableYears(from: eligible)
    }

    func yearlyReport(
        for year: Int,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingYearlyReport {
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        let fingerprint = Self.fingerprint(eligible)
        let cacheKey = Self.yearlyCacheKey(year: year, filters: filters, fingerprint: fingerprint)
        if !forceNetwork, let cached = yearlyCache[cacheKey] {
            return cached
        }
        let report = TradingYearlyReportGenerator.generate(
            year: year,
            trades: eligible,
            filters: filters
        )
        yearlyCache[cacheKey] = report
        return report
    }

    func monthReport(
        for ref: TradingReportMonthRef,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        return TradingYearlyReportGenerator.generateMonthReport(
            ref: ref,
            trades: eligible,
            filters: filters
        )
    }

    // MARK: - Trade load

    private func loadEligibleTrades(forceNetwork: Bool) async throws -> [Trade] {
        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.reports")

        let loaded: [Trade]
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            loaded = ProfileTradeFixtures.samples(owner: profileID)
        } else {
            loaded = try await SessionOwnerTradesStore.shared.trades(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: forceNetwork
            )
        }

        let eligible = loaded.filter { $0.mode != .backtest }
        cachedEligibleTrades = eligible
        return eligible
    }

    // MARK: - Notify (web `requestTradingReportNotification`)

    private func maybeNotify(userID: String?, snapshot: TradingReportsSnapshot) async {
        guard let userID, !userID.hasPrefix("dev.") else { return }
        guard let transport = supabase.transport else { return }

        for periodKey: TradingReportPeriodKey in [.weeklyLast, .monthlyLast] {
            guard let report = snapshot.report(for: periodKey),
                  report.metrics.tradesTaken > 0
            else { continue }

            let notifyKey = "\(userID):\(periodKey.rawValue):\(report.periodStartIso)"
            guard !notifiedKeys.contains(notifyKey) else { continue }
            notifiedKeys.insert(notifyKey)

            let body = NotifyBody(
                periodKey: periodKey.rawValue,
                periodId: TradingReportPeriods.periodID(for: periodKey),
                kind: report.kind.rawValue,
                title: report.kind == .weekly
                    ? "Your Weekly Trading Report is Ready"
                    : "Your Monthly Trading Report is Ready",
                href: "/dashboard?report=\(periodKey.rawValue)"
            )

            do {
                let data = try transport.encodeJSON(body)
                _ = try await transport.send(
                    host: .bff,
                    path: "/api/trading-reports/notify",
                    method: .post,
                    body: data,
                    requiresAuthentication: true
                )
            } catch {
                // Best-effort — web also swallows notify failures.
            }
        }
    }

    private static func fingerprint(_ trades: [Trade]) -> String {
        guard !trades.isEmpty else { return "0" }
        let head = trades.first?.id.rawValue ?? ""
        let tail = trades.last?.id.rawValue ?? ""
        return "\(trades.count):\(head):\(tail)"
    }

    private static func yearlyCacheKey(
        year: Int,
        filters: TradingReportFilters,
        fingerprint: String
    ) -> String {
        let account: String = {
            switch filters.accountFilter {
            case .all: return "all"
            case .account(let id): return id.rawValue
            }
        }()
        return "\(fingerprint):year:\(year):account:\(account):mode:\(filters.accountMode.rawValue)"
    }

    private struct NotifyBody: Encodable {
        var periodKey: String
        var periodId: String
        var kind: String
        var title: String
        var href: String
    }
}
