import Foundation

/// Native Trading Reports, mirrors web `ensureTradingReportsLoaded`.
///
/// Report bodies are generated locally with ``TradingReportGenerator`` (web
/// `generateTradingReport.ts`). Weekly push is scheduled by Supabase pg_cron.
actor DefaultTradingReportRepository: TradingReportRepository {
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let tradingPreferences: (any TradingPreferencesRepository)?

    private var snapshot: TradingReportsSnapshot?
    private var tradeFingerprint: String?
    private var cachedEligibleTrades: [Trade] = []
    private var yearlyCache: [String: TradingYearlyReport] = [:]
    private var customReportCache: [String: TradingReport] = [:]
    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        tradingPreferences: (any TradingPreferencesRepository)? = nil
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.tradingPreferences = tradingPreferences
    }

    func ensureSnapshot(forceNetwork: Bool) async throws -> TradingReportsSnapshot {
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        let accounts = try await loadAccounts(forceNetwork: forceNetwork)
        let filters = await ReportsTradeScope.filtersFromSession()
        let preferences = await loadPreferences()
        let copyGroups = await copyTradingMenuGroups()
        let scoped = ReportsTradeScope.scopedTrades(
            from: eligible,
            accounts: accounts,
            filters: filters,
            copyTradingGroups: copyGroups
        )
        let fingerprint = Self.fingerprint(eligible)
            + ":" + PreferenceComplianceEngine.fingerprint(preferences)
            + ":" + ReportsTradeScope.filtersFingerprint(filters)

        if !forceNetwork,
           let snapshot,
           tradeFingerprint == fingerprint {
            return snapshot
        }

        let reports = TradingReportGenerator.generateAll(trades: scoped, preferences: preferences)
        let next = TradingReportsSnapshot(
            reports: reports,
            computedAt: Date().timeIntervalSince1970 * 1000
        )
        snapshot = next
        tradeFingerprint = fingerprint
        yearlyCache = [:]
        customReportCache = [:]

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
        let accounts = try await loadAccounts(forceNetwork: forceNetwork)
        let filters = await ReportsTradeScope.filtersFromSession()
        let copyGroups = await copyTradingMenuGroups()
        let scoped = ReportsTradeScope.scopedTrades(
            from: eligible,
            accounts: accounts,
            filters: filters,
            copyTradingGroups: copyGroups
        )
        return TradingYearlyReportGenerator.availableYears(from: scoped)
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
        let copyGroups = await copyTradingMenuGroups()
        let report = TradingYearlyReportGenerator.generate(
            year: year,
            trades: eligible,
            filters: filters,
            copyTradingGroups: copyGroups
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
        let copyGroups = await copyTradingMenuGroups()
        return TradingYearlyReportGenerator.generateMonthReport(
            ref: ref,
            trades: eligible,
            filters: filters,
            copyTradingGroups: copyGroups
        )
    }

    func weekReport(
        mondayKey: String,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        let accounts = try await loadAccounts(forceNetwork: forceNetwork)
        let copyGroups = await copyTradingMenuGroups()
        let scoped = ReportsTradeScope.scopedTrades(
            from: eligible,
            accounts: accounts,
            filters: filters,
            copyTradingGroups: copyGroups
        )
        let preferences = await loadPreferences()
        guard let week = TradingReportWeekRef.parse(reportID: ReportID("week:\(mondayKey)")) else {
            throw AppError.unknown(message: "Report unavailable for week \(mondayKey).")
        }
        return TradingReportGenerator.generate(
            trades: scoped,
            week: week,
            preferences: preferences
        )
    }

    func customReport(
        for ref: TradingReportCustomRangeRef,
        filters: TradingReportFilters,
        forceNetwork: Bool
    ) async throws -> TradingReport {
        guard let interval = ref.interval else {
            throw AppError.unknown(message: "Invalid custom date range.")
        }
        let eligible = try await loadEligibleTrades(forceNetwork: forceNetwork)
        let fingerprint = Self.fingerprint(eligible)
        let cacheKey = Self.customCacheKey(ref: ref, filters: filters, fingerprint: fingerprint)
        if !forceNetwork, let cached = customReportCache[cacheKey] {
            return cached
        }
        let preferences = await loadPreferences()
        let copyGroups = await copyTradingMenuGroups()
        let report = TradingReportGenerator.generateCustomRange(
            trades: eligible,
            interval: interval,
            filters: filters,
            copyTradingGroups: copyGroups,
            preferences: preferences
        )
        customReportCache[cacheKey] = report
        return report
    }

    private func loadPreferences() async -> PreferenceRuleContext? {
        guard let tradingPreferences else { return nil }
        let userID = await session.currentUserID
        guard let userID else { return nil }
        let profileID = ProfileID(userID.rawValue)
        do {
            async let global = tradingPreferences.globalPreferences(for: profileID)
            async let overrides = tradingPreferences.accountOverrides(for: profileID)
            async let revisions = tradingPreferences.revisions(for: profileID)
            return PreferenceRuleContext(
                revisions: try await revisions,
                global: try await global,
                overrides: try await overrides
            )
        } catch {
            return nil
        }
    }

    private func copyTradingMenuGroups() async -> [CopyTradingGroup] {
        let userID = await session.currentUserID
        let demoActive = await AppLaunchController.shared.isDemoExperienceActive
        guard case .viewer(let profileID) = SessionViewerIdentity.resolve(
            userID: userID,
            demoExperienceActive: demoActive
        ) else {
            return []
        }
        return await MainActor.run {
            OwnerAccountFilterMenuSupport.copyGroups(for: profileID)
        }
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
        if let bundle = await MainActor.run(body: { TraxsProPreviewSupport.reportsJournalBundle(for: profileID) }) {
            loaded = bundle.trades
        } else if JournalSampleDataPolicy.usesCanonicalJournalData(for: profileID) {
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

    private func loadAccounts(forceNetwork: Bool) async throws -> [TradingAccount] {
        let userID = await session.currentUserID
        let demoActive = await AppLaunchController.shared.isDemoExperienceActive
        guard case .viewer(let profileID) = SessionViewerIdentity.resolve(
            userID: userID,
            demoExperienceActive: demoActive
        ) else {
            return []
        }
        if let bundle = await MainActor.run(body: { TraxsProPreviewSupport.reportsJournalBundle(for: profileID) }) {
            return bundle.accounts
        }
        if JournalSampleDataPolicy.usesCanonicalJournalData(for: profileID) {
            return DemoCanonicalDataset.accounts()
        }
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            return []
        }
        return try await trades.accounts(for: profileID)
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
        return "\(fingerprint):year:\(year):\(ReportsTradeScope.filtersFingerprint(filters))"
    }

    private static func customCacheKey(
        ref: TradingReportCustomRangeRef,
        filters: TradingReportFilters,
        fingerprint: String
    ) -> String {
        return "\(fingerprint):custom:\(ref.startKey):\(ref.endKey):\(ReportsTradeScope.filtersFingerprint(filters))"
    }
}
