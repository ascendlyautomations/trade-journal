import Foundation

/// Dashboard hero equity + personal drawdown floor — mirrors web `useDashboardLiveAccountBundle`.
///
/// Balance levels come only from ``LivePersonalDrawdownEngine``; never apply
/// ``DashboardEquityHeroPresentation/chartPoints`` (V3 cumulative P&amp;L offset).
nonisolated enum DashboardLivePersonalDrawdownHeroSeries {
  struct Input: Sendable {
    var account: TradingAccount
    var lifetimeTrades: [Trade]
    var ledgerEntries: [AccountPayoutEntry]
    var period: LivePersonalDrawdownEngine.PeriodContext
  }

  /// Chart-ready points for ``ProfileEquityCurveView``, or `nil` when drawdown is not configured.
  static func resolve(_ input: Input) -> [ProfileStatisticsMetrics.EquityPoint]? {
    guard let config = LivePersonalDrawdownEngine.config(from: input.account) else { return nil }
    let samples = LivePersonalDrawdownEngine.computeEquitySeries(
      account: input.account,
      config: config,
      lifetimeTrades: input.lifetimeTrades,
      ledgerEntries: input.ledgerEntries,
      period: input.period
    )
    guard !samples.isEmpty else { return nil }
    return ProfileStatisticsMetrics.chartOrderedEquityPoints(
      LivePersonalDrawdownEngine.mapToEquityPoints(samples)
    )
  }

  static func usesLivePersonalDrawdownSeries(for account: TradingAccount?) -> Bool {
    guard let account else { return false }
    return LivePersonalDrawdownEngine.config(from: account) != nil
  }
}