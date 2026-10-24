import Foundation

/// Native Trading Reports — mirrors web `ensureTradingReportsLoaded`.
///
/// Report bodies are generated locally with ``TradingReportGenerator`` (web
/// `generateTradingReport.ts`). Weekly push is server-scheduled (Vercel cron).
actor DefaultTradingReportRepository: TradingReportRepository {
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache

    private var snapshot: TradingReportsSnapshot?
    private var tradeFingerprint: String?
    private var cachedEligibleTrades: [Trade] = []
    private var yearlyCache: [String: TradingYearlyReport] = [:]
    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
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
        let demoActive = await AppLaunchController.shared.isDemoExperienceActive
        guard case .viewer(let profileID) = SessionViewerIdentity.resolve(
            userID: userID,
            demoExperienceActive: demoActive
        ) else {
            throw AppError.unknown(message: SessionViewerIdentity.sessionUnavailableMessage)
        }
        let latestUserID = await session.currentUserID
        guard SessionViewerIdentity.shouldCommit(
            resolved: profileID,
            userID: latestUserID,
            demoExperienceActive: await AppLaunchController.shared.isDemoExperienceActive
        ) else {
            throw AppError.unknown(message: SessionViewerIdentity.sessionUnavailableMessage)
        }

        let loaded: [Trade]
        if profileID == DemoExperienceSupport.profileID {
            loaded = DemoCanonicalDataset.trades()
        } else if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
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
}
