import Foundation

actor DefaultPsychologyReportRepository: PsychologyReportRepository {
    private let trades: any TradeRepository
    private let dailyCheckIns: any TraderDailyCheckInRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache

    private var snapshot: PsychologyReportsSnapshot?
    private var fingerprint: String?

    init(
        trades: any TradeRepository,
        dailyCheckIns: any TraderDailyCheckInRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) {
        self.trades = trades
        self.dailyCheckIns = dailyCheckIns
        self.session = session
        self.detailCache = detailCache
    }

    func ensureSnapshot(forceNetwork: Bool) async throws -> PsychologyReportsSnapshot {
        let (eligibleTrades, checkIns, fp) = try await loadInputs(forceNetwork: forceNetwork)

        if !forceNetwork, let snapshot, fingerprint == fp {
            return snapshot
        }

        let next = PsychologyReportGenerator.generateAll(trades: eligibleTrades, checkIns: checkIns)
        snapshot = next
        fingerprint = fp
        await MainActor.run {
            PsychologyReportSessionStore.shared.update(next)
        }
        return next
    }

    func report(for reportID: ReportID, forceNetwork: Bool) async throws -> PsychologyReport {
        if let cached = await MainActor.run(body: { PsychologyReportSessionStore.shared.report(for: reportID) }) {
            return cached
        }
        let snap = try await ensureSnapshot(forceNetwork: forceNetwork)
        guard let report = snap.report(for: reportID) else {
            throw AppError.unknown(message: "Psychology report unavailable.")
        }
        return report
    }

    private func loadInputs(forceNetwork: Bool) async throws -> ([Trade], [TraderDailyCheckIn], String) {
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

        let startKey = CheckInHistoryAggregator.startDateKey()
        let endKey = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
        let checkIns: [TraderDailyCheckIn]
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
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

    private static func fingerprint(trades: [Trade], checkIns: [TraderDailyCheckIn]) -> String {
        let tradeHead = trades.first?.id.rawValue ?? ""
        let tradeTail = trades.last?.id.rawValue ?? ""
        let checkInTail = checkIns.first?.updatedAt.timeIntervalSince1970.description ?? "0"
        return "\(trades.count):\(checkIns.count):\(tradeHead):\(tradeTail):\(checkInTail)"
    }
}
