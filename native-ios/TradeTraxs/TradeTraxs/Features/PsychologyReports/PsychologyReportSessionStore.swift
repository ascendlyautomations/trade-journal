import Foundation

@MainActor
final class PsychologyReportSessionStore {
    static let shared = PsychologyReportSessionStore()

    private(set) var snapshot: PsychologyReportsSnapshot?
    private(set) var aiSummaries: [ReportID: String] = [:]
    private(set) var aiSummaryHashes: [ReportID: String] = [:]

    private init() {}

    func update(_ snapshot: PsychologyReportsSnapshot) {
        self.snapshot = snapshot
        invalidateStaleAI(with: snapshot)
    }

    func report(for id: ReportID) -> PsychologyReport? {
        snapshot?.report(for: id)
    }

    func applyAISummary(_ summary: String, reportID: ReportID, factsHash: String) {
        aiSummaries[reportID] = summary
        aiSummaryHashes[reportID] = factsHash
    }

    func cachedAISummary(for reportID: ReportID, factsHash: String) -> String? {
        guard aiSummaryHashes[reportID] == factsHash else { return nil }
        return aiSummaries[reportID]
    }

    func invalidate() {
        snapshot = nil
        aiSummaries.removeAll()
        aiSummaryHashes.removeAll()
    }

    private func invalidateStaleAI(with snapshot: PsychologyReportsSnapshot) {
        for (id, hash) in aiSummaryHashes {
            if snapshot.report(for: id)?.factsHash != hash {
                aiSummaries.removeValue(forKey: id)
                aiSummaryHashes.removeValue(forKey: id)
            }
        }
    }
}

@MainActor
final class CheckInHistorySessionStore {
    static let shared = CheckInHistorySessionStore()

    private(set) var summaries: [CheckInHistoryDaySummary] = []
    private(set) var checkIns: [TraderDailyCheckIn] = []
    private(set) var trades: [Trade] = []

    private init() {}

    func update(
        summaries: [CheckInHistoryDaySummary],
        checkIns: [TraderDailyCheckIn],
        trades: [Trade]
    ) {
        self.summaries = summaries
        self.checkIns = checkIns
        self.trades = trades
    }

    func detail(for dateKey: String) -> CheckInDayDetail {
        CheckInHistoryAggregator.buildDetail(
            dateKey: dateKey,
            checkIns: checkIns,
            trades: trades
        )
    }

    func refreshCheckIn(_ checkIn: TraderDailyCheckIn) {
        if let index = checkIns.firstIndex(where: { $0.checkInDate == checkIn.checkInDate }) {
            checkIns[index] = checkIn
        } else {
            checkIns.append(checkIn)
        }
        summaries = CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: trades)
    }

    func invalidate() {
        summaries = []
        checkIns = []
        trades = []
    }
}
