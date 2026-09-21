import Foundation
import Testing
@testable import TradeTraxs

struct ProfileAnalyticsV2ShadowTests {
    @Test("Profile Analytics V2 bootstrap decodes and maps modes")
    func bootstrapDecode() throws {
        let data = Data(ProfileAnalyticsV2Fixtures.bootstrapAllMode.utf8)
        let wire = try JSONDecoder().decode(ProfileAnalyticsBootstrapV2.self, from: data)
        try wire.validateContractVersion()
        let applied = ProfileAnalyticsV2BootstrapApplier.apply(wire)
        #expect(applied.found)
        #expect(applied.publicRevision == 3)
        let all = applied.modeResults[.all]
        #expect(all?.filteredTradeCount == 2)
        #expect(all?.longTrades == 1)
    }

    @Test("Locked profile V2 bootstrap found=false")
    func lockedBootstrap() throws {
        let data = Data(ProfileAnalyticsV2Fixtures.bootstrapLocked.utf8)
        let wire = try JSONDecoder().decode(ProfileAnalyticsBootstrapV2.self, from: data)
        let applied = ProfileAnalyticsV2BootstrapApplier.apply(wire)
        #expect(!applied.found)
        #expect(applied.modeResults.isEmpty)
    }

    @Test("Public analytics revision decodes")
    func revisionDecode() throws {
        let data = Data(ProfileAnalyticsV2Fixtures.revisionPublic.utf8)
        let wire = try JSONDecoder().decode(ProfilePublicAnalyticsRevisionV1.self, from: data)
        try wire.validateContractVersion()
        #expect(wire.meta.found)
        #expect(wire.revisionInt == 7)
    }

    @Test("Parity comparator passes identical modes")
    func parityPass() {
        let sample = ProfileAnalyticsV2Fixtures.sampleResult(tradeCount: 4, equity: 120)
        let mismatches = ProfileAnalyticsV2Parity.compareModes(
            profileID: ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            v1: [.all: sample],
            v2: [.all: sample]
        )
        #expect(mismatches.isEmpty)
    }

    @Test("Parity comparator detects trade count drift")
    func parityDetectsDrift() {
        let v1 = ProfileAnalyticsV2Fixtures.sampleResult(tradeCount: 4, equity: 120)
        var v2 = v1
        v2.filteredTradeCount = 3
        let mismatches = ProfileAnalyticsV2Parity.compareModes(
            profileID: ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            v1: [.all: v1],
            v2: [.all: v2]
        )
        #expect(mismatches.contains { $0.field == "filtered_trade_count" })
    }

    @Test("Gate parity locked profile")
    func gateLocked() {
        let gate = ProfileAnalyticsV2Parity.compareGate(v1CanViewStatistics: false, v2Found: false)
        #expect(gate.matches)
    }

    @Test("Stale profile rejected after navigation subject change")
    func staleSubjectRejection() async {
        await ProfileAnalyticsV2ShadowSession.shared.reset()
        await ProfileAnalyticsV2ShadowSession.shared.setActiveSubjectProfile("profile-b")
        let stillA = await ProfileAnalyticsV2ShadowSession.shared.isActiveSubjectProfile("profile-a")
        #expect(!stillA)
        let stillB = await ProfileAnalyticsV2ShadowSession.shared.isActiveSubjectProfile("profile-b")
        #expect(stillB)
    }

    @Test("Viewer-scoped single-flight keys differ by viewer")
    func viewerFlightIsolation() {
        let a = BackendV2FlightKeys.profileAnalyticsV2Bootstrap(
            viewerID: "viewer-a",
            profileID: "subject"
        )
        let b = BackendV2FlightKeys.profileAnalyticsV2Bootstrap(
            viewerID: "viewer-b",
            profileID: "subject"
        )
        #expect(a != b)
    }

    @Test("Shadow dedupe prevents repeat within unchanged session")
    func shadowDedupe() async {
        await ProfileAnalyticsV2ShadowSession.shared.reset()
        let key = "1|viewer|subject|shadow"
        #expect(await ProfileAnalyticsV2ShadowSession.shared.beginShadowSessionKey(key))
        let second = await ProfileAnalyticsV2ShadowSession.shared.beginShadowSessionKey(key)
        #expect(second == false)
    }
}

enum ProfileAnalyticsV2Fixtures {
    static let bootstrapAllMode = """
    {"meta":{"contract_version":"v2","found":true,"server_time":"2026-09-21T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111","public_revision":3,"public_updated_at":"2026-09-21T19:00:00.000Z"},"data":{"profile_id":"22222222-2222-2222-2222-222222222222","modes":{"all":{"filtered_trade_count":2,"win_rate":0.5,"profit_factor":2,"average_winner":100,"average_loser":-50,"profit_per_trade":25,"biggest_win":100,"biggest_loss":-50,"long_trades":1,"max_win_streak":1,"max_loss_streak":1,"session_total":2,"session_breakdown":[{"label":"NY","count":2,"pct":100}],"current_equity":50,"equity_data":[{"index":0,"equity":0,"date":"2026-08-01T12:00:00.000Z"},{"index":1,"equity":50,"date":"2026-08-02T12:00:00.000Z"}]}}}}
    """

    static let bootstrapLocked = """
    {"meta":{"contract_version":"v2","found":false,"server_time":"2026-09-21T20:00:00.000Z","viewer_id":null,"public_revision":null,"public_updated_at":null},"data":{"profile_id":"33333333-3333-3333-3333-333333333333","modes":{}}}
    """

    static let revisionPublic = """
    {"meta":{"contract_version":"v1","found":true,"server_time":"2026-09-21T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"profile_id":"22222222-2222-2222-2222-222222222222","revision":7,"updated_at":"2026-09-21T19:00:00.000Z"}}
    """

    static func sampleResult(tradeCount: Int, equity: Decimal) -> ProfileStatisticsMetrics.Result {
        ProfileStatisticsMetrics.Result(
            filteredTradeCount: tradeCount,
            winRate: Decimal(0.5),
            profitFactor: Decimal(2),
            averageWinner: Decimal(100),
            averageLoser: Decimal(-50),
            profitPerTrade: Decimal(25),
            biggestWin: Decimal(100),
            biggestLoss: Decimal(-50),
            longTrades: 2,
            maxWinStreak: 2,
            maxLossStreak: 1,
            sessionTotal: tradeCount,
            sessionBreakdown: [ProfileStatisticsMetrics.SessionRow(label: "NY", count: tradeCount, pct: 100)],
            currentEquity: equity,
            equityData: [
                ProfileStatisticsMetrics.EquityPoint(index: 0, equity: 0),
                ProfileStatisticsMetrics.EquityPoint(index: 1, equity: equity),
            ]
        )
    }
}
