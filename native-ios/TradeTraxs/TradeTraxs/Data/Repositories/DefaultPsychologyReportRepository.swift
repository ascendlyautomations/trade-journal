import Foundation

actor DefaultPsychologyReportRepository: PsychologyReportRepository {
    private let trades: any TradeRepository
    private let dailyCheckIns: any TraderDailyCheckInRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let tradingPreferences: (any TradingPreferencesRepository)?

    private var snapshot: PsychologyReportsSnapshot?
    private var fingerprint: String?

    init(
        trades: any TradeRepository,
        dailyCheckIns: any TraderDailyCheckInRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        tradingPreferences: (any TradingPreferencesRepository)? = nil
    ) {
        self.trades = trades
        self.dailyCheckIns = dailyCheckIns
        self.session = session
        self.detailCache = detailCache
        self.tradingPreferences = tradingPreferences
    }

    func ensureSnapshot(forceNetwork: Bool) async throws -> PsychologyReportsSnapshot {
        let (eligibleTrades, checkIns, loadedFingerprint) = try await loadInputs(forceNetwork: forceNetwork)
        let preferences = await loadPreferences()
        let fp = loadedFingerprint + ":" + PreferenceComplianceEngine.fingerprint(preferences)

        if !forceNetwork, let snapshot, fingerprint == fp {
            return snapshot
        }

        let next = PsychologyReportGenerator.generateAll(
            trades: eligibleTrades,
            checkIns: checkIns,
            preferences: preferences
        )
        snapshot = next
        fingerprint = fp
        await MainActor.run {
            PsychologyReportSessionStore.shared.update(next)
        }
        return next
    }

    func report(for reportID: ReportID, forceNetwork: Bool) async throws -> PsychologyReport {
        let snap = try await ensureSnapshot(forceNetwork: forceNetwork)
        guard let report = snap.report(for: reportID) else {
            throw AppError.unknown(message: "Psychology report unavailable.")
        }
        return report
    }

    private func loadInputs(forceNetwork: Bool) async throws -> ([Trade], [TraderDailyCheckIn], String) {
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

        let startKey = CheckInHistoryAggregator.startDateKey()
        let endKey = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
        let checkIns: [TraderDailyCheckIn]
        if profileID == DemoExperienceSupport.profileID {
            checkIns = DemoCanonicalDataset.checkIns()
        } else if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            checkIns = []
        } else {
            checkIns = try await dailyCheckIns.checkIns(
                for: profileID,
                from: startKey,
                to: endKey
            )
        }

        let fp = Self.fingerprint(trades: eligible, checkIns: checkIns)
        return (eligible, checkIns, fp)
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

    private static func fingerprint(trades: [Trade], checkIns: [TraderDailyCheckIn]) -> String {
        let tradeHead = trades.first?.id.rawValue ?? ""
        let tradeTail = trades.last?.id.rawValue ?? ""
        let checkInTail = checkIns.first?.updatedAt.timeIntervalSince1970.description ?? "0"
        return "\(trades.count):\(checkIns.count):\(tradeHead):\(tradeTail):\(checkInTail)"
    }
}
