import Foundation
import Testing
@testable import TradeTraxs

struct DashboardAnalyticsV3Tests {
    @Test("Preset key maps dashboard date ranges")
    func presetKeys() {
        #expect(DashboardAnalyticsMapper.presetKey(for: .sevenDays) == "d7")
        #expect(DashboardAnalyticsMapper.presetKey(for: .thirtyDays) == "d30")
        #expect(DashboardAnalyticsMapper.presetKey(for: .all) == "all")
    }

    @Test("Composer win rate uses trade count denominator")
    func winRate() {
        let ingredients = DashboardAnalyticsComposer.Ingredients(
            tradeCount: 4,
            winCount: 3,
            lossCount: 1,
            breakevenCount: 0,
            netPnL: 10,
            grossProfit: 12,
            grossLoss: -2,
            longCount: 2,
            longPnL: 8,
            shortCount: 2,
            shortPnL: 2,
            sumRR: 4,
            rrCount: 2,
            sumHoldSeconds: 600,
            holdCount: 2,
            largestWin: 5,
            largestLoss: -2
        )
        #expect(DashboardAnalyticsComposer.winRate(ingredients) == Decimal(3) / Decimal(4))
        #expect(DashboardAnalyticsComposer.profitFactor(ingredients) == Decimal(12) / Decimal(2))
    }

    @Test("All Accounts d30 uses aggregate preset metrics")
    func aggregateSelection() throws {
        let bootstrap = try makeBootstrap()
        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .all,
            dateRange: .thirtyDays
        )
        #expect(bundle?.metrics.trade_count == 11)
        #expect(bundle?.metrics.net_pnl.value == 3063.5)
    }

    @Test("Account A d30 uses account metrics not aggregate")
    func accountASelection() throws {
        let bootstrap = try makeBootstrap()
        let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(accountA),
            dateRange: .thirtyDays
        )
        #expect(bundle?.metrics.trade_count == 1)
        #expect(bundle?.metrics.net_pnl.value == 500)
    }

    @Test("Account B d30 uses distinct metrics")
    func accountBSelection() throws {
        let bootstrap = try makeBootstrap()
        let accountB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(accountB),
            dateRange: .thirtyDays
        )
        #expect(bundle?.metrics.trade_count == 7)
        #expect(bundle?.metrics.net_pnl.value == -36.5)
    }

    @Test("Switching preset preserves account metrics source")
    func presetSwitchKeepsAccount() throws {
        let bootstrap = try makeBootstrap()
        let accountB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let d90 = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(accountB),
            dateRange: .ninetyDays
        )
        #expect(d90?.metrics.trade_count == 7)
    }

    @Test("Expanded V3 distributions map into visual chart summary")
    func expandedDistributionsSummary() throws {
        let distributionsJSON = """
        {
          "sessions": [
            {"label":"New York","count":5,"pct":50,"trade_count":5,"net_pnl":1200,"wins":3,"losses":2,"win_rate":60}
          ],
          "symbols": [
            {"ticker":"MNQ","trades":8,"net_pnl":2840,"wins":5,"win_rate":62.5,"avg_rr":1.2}
          ],
          "daily": {
            "best_day_pnl": 900,
            "worst_day_pnl": -400,
            "avg_day_pnl": 120,
            "consistency_pct": 55,
            "trading_days": 10
          },
          "streaks": {
            "current_streak": 3,
            "current_type": "win",
            "max_win_streak": 5,
            "max_loss_streak": 2
          },
          "weekday_bars": [],
          "weekday_heatmap": [],
          "hour_bars": [],
          "hour_heatmap": [],
          "hour_highlights": {"best_hour": 10, "worst_hour": 15, "best_pnl": 500, "worst_pnl": -200},
          "hold_histogram": [],
          "hold_extremes": {
            "fastest_winner_seconds": 120,
            "fastest_winner_pnl": 50,
            "longest_winner_seconds": 3600,
            "longest_winner_pnl": 200
          },
          "long_short": [],
          "long_short_detail": {
            "long": {"trades": 6, "net_pnl": 3240, "wins": 4, "losses": 2, "win_rate": 66.7},
            "short": {"trades": 4, "net_pnl": 820, "wins": 2, "losses": 2, "win_rate": 50}
          },
          "long_trade_count": 6,
          "short_trade_count": 4,
          "strategies": {
            "best": {"strategy":"Opening Drive","trades":5,"net_pnl":1100,"win_rate":80},
            "worst": {"strategy":"Fade","trades":4,"net_pnl":-300,"win_rate":25}
          }
        }
        """
        let distributions = try JSONDecoder().decode(
            AnalyticsDashboardDistributionsWireV1.self,
            from: Data(distributionsJSON.utf8)
        )
        let metrics = AnalyticsDashboardMetricsWireV1(
            trade_count: 10,
            win_count: 6,
            loss_count: 4,
            breakeven_count: 0,
            net_pnl: PostgresFlexibleDouble(4060),
            gross_profit: PostgresFlexibleDouble(5000),
            gross_loss: PostgresFlexibleDouble(-940),
            long_count: 6,
            long_pnl: PostgresFlexibleDouble(3240),
            short_count: 4,
            short_pnl: PostgresFlexibleDouble(820),
            sum_rr: PostgresFlexibleDouble(0),
            rr_count: 0,
            sum_hold_seconds: PostgresFlexibleDouble(0),
            hold_count: 0,
            largest_win: nil,
            largest_loss: nil
        )
        let bundle = AnalyticsDashboardPresetBundleV1(
            preset: "d30",
            start: "2026-08-01",
            end: "2026-08-31",
            metrics: metrics,
            equity: AnalyticsDashboardEquityWireV1(
                points: [],
                max_drawdown: PostgresFlexibleDouble(0),
                current_equity: PostgresFlexibleDouble(0)
            ),
            distributions: distributions,
            insights: []
        )
        let summary = DashboardAnalyticsMapper.summary(from: bundle, payoutTotal: nil)
        #expect(summary.sessionPerformance.first?.netPnL == 1200)
        #expect(summary.symbolPerformance.first?.ticker == "MNQ")
        #expect(summary.dailyPerformance?.consistencyPct == 55)
        #expect(summary.streaks?.currentStreak == 3)
        #expect(summary.hourHighlights?.bestHour == 10)
        #expect(summary.longShortComparison?.long?.netPnL == 3240)
        #expect(summary.holdExtremes.count == 2)
        #expect(summary.strategyHighlights?.best?.strategy == "Opening Drive")
    }

    @Test("Missing account metrics never falls back to aggregate")
    func missingAccountMetrics() throws {
        let bootstrap = try makeBootstrap()
        let missing = TradingAccountID("00000000-0000-0000-0000-000000000099")
        let resolution = DashboardAnalyticsMapper.resolve(
            in: bootstrap,
            accountFilter: .account(missing),
            dateRange: .thirtyDays
        )
        if case .accountMetricsMissing = resolution {
            #expect(Bool(true))
        } else {
            Issue.record("Expected accountMetricsMissing, got \(resolution)")
        }
        #expect(
            DashboardAnalyticsMapper.bundle(
                in: bootstrap,
                accountFilter: .account(missing),
                dateRange: .thirtyDays
            ) == nil
        )
    }

    @Test("Equity chart widen requires at least two trades in preset metrics")
    func equityChartWidenRequiresTwoTrades() throws {
        let widenTo90 = try makeBootstrapWithAggregateTradeCounts([
            "d7": 1,
            "d30": 1,
            "d90": 4,
            "ytd": 8,
            "all": 8,
        ])
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .sevenDays,
                analyticsBootstrap: widenTo90,
                accountFilter: .all
            ) == .ninetyDays
        )
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .thirtyDays,
                analyticsBootstrap: widenTo90,
                accountFilter: .all
            ) == .ninetyDays
        )

        let widenToYTD = try makeBootstrapWithAggregateTradeCounts([
            "d7": 0,
            "d30": 1,
            "d90": 1,
            "ytd": 8,
            "all": 8,
        ])
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .thirtyDays,
                analyticsBootstrap: widenToYTD,
                accountFilter: .all
            ) == .ytd
        )

        let onlyAll = try makeBootstrapWithAggregateTradeCounts([
            "d7": 1,
            "d30": 1,
            "d90": 1,
            "ytd": 1,
            "all": 2,
        ])
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .sevenDays,
                analyticsBootstrap: onlyAll,
                accountFilter: .all
            ) == .all
        )

        let singleTrade = try makeBootstrapWithAggregateTradeCounts([
            "d7": 1,
            "d30": 1,
            "d90": 1,
            "ytd": 1,
            "all": 1,
        ])
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .thirtyDays,
                analyticsBootstrap: singleTrade,
                accountFilter: .all
            ) == .all
        )

        let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        var accountOneTrade = try makeBootstrap()
        accountOneTrade = try makeBootstrapWithAccountTradeCounts(
            accountOneTrade,
            accountID: accountA,
            counts: ["d30": 1, "d90": 1, "all": 1]
        )
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .thirtyDays,
                analyticsBootstrap: accountOneTrade,
                accountFilter: .account(accountA)
            ) == .all
        )

        accountOneTrade = try makeBootstrapWithAccountTradeCounts(
            accountOneTrade,
            accountID: accountA,
            counts: ["d30": 1, "d90": 3, "all": 3]
        )
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .thirtyDays,
                analyticsBootstrap: accountOneTrade,
                accountFilter: .account(accountA)
            ) == .ninetyDays
        )
    }

    @Test("User-selected preset is never auto-widened for equity chart")
    func equityChartHonorsUserSelectedRange() throws {
        let bootstrap = try makeBootstrapWithAggregateTradeCounts([
            "d7": 0,
            "d30": 0,
            "d90": 4,
            "ytd": 8,
            "all": 8,
        ])
        #expect(
            DashboardEquityChartRangeResolver.effectiveRange(
                requested: .thirtyDays,
                analyticsBootstrap: bootstrap,
                accountFilter: .all,
                allowAutomaticWiden: false
            ) == .thirtyDays
        )
    }

    @Test("Empty user-selected range carries prior equity as flat chart")
    func equityChartFlatCarryForwardForEmptySelectedRange() throws {
        let bootstrap = try makeBootstrapWithAggregateTradeCounts([
            "d30": 0,
            "d90": 4,
            "all": 4,
        ])
        let charts: [String: AnalyticsDashboardChartsPresetV1] = [
            "d30": AnalyticsDashboardChartsPresetV1(
                preset: "d30",
                start: "2026-08-23",
                end: "2026-09-21",
                equity: AnalyticsDashboardEquityWireV1(
                    points: [],
                    max_drawdown: PostgresFlexibleDouble(0),
                    current_equity: PostgresFlexibleDouble(0)
                ),
                distributions: Self.emptyDistributions,
                insights: []
            ),
            "all": AnalyticsDashboardChartsPresetV1(
                preset: "all",
                start: "2020-01-01",
                end: "2026-09-21",
                equity: AnalyticsDashboardEquityWireV1(
                    points: [
                        AnalyticsDashboardEquityPointWireV1(
                            t: "2026-06-01T12:00:00.000Z",
                            v: PostgresFlexibleDouble(52_000),
                            i: 0
                        ),
                        AnalyticsDashboardEquityPointWireV1(
                            t: "2026-07-01T12:00:00.000Z",
                            v: PostgresFlexibleDouble(53_500),
                            i: 1
                        ),
                    ],
                    max_drawdown: PostgresFlexibleDouble(0),
                    current_equity: PostgresFlexibleDouble(53_500)
                ),
                distributions: Self.emptyDistributions,
                insights: []
            ),
        ]
        guard let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .all,
            dateRange: .thirtyDays,
            accountCharts: charts
        ) else {
            Issue.record("Missing d30 bundle")
            return
        }
        let base = DashboardAnalyticsMapper.summary(from: bundle, payoutTotal: nil)
        #expect(base.tradeCount == 0)
        #expect(base.equityData.isEmpty)
        let chart = DashboardEquityChartSeries.carryForwardFlatIfNeeded(
            summary: base,
            presetBundle: bundle,
            analyticsBootstrap: bootstrap,
            accountFilter: .all,
            accountCharts: charts
        )
        #expect(chart.equityData.count == 2)
        #expect(chart.equityData[0].equity == 53_500)
        #expect(chart.equityData[1].equity == 53_500)
        #expect(chart.currentEquity == 53_500)
    }

    @Test("All Accounts charts overlay supplies equity without changing KPI metrics")
    func aggregateChartsOverlay() throws {
        let bootstrap = try makeBootstrap()
        let charts: [String: AnalyticsDashboardChartsPresetV1] = [
            "d30": AnalyticsDashboardChartsPresetV1(
                preset: "d30",
                start: "2026-08-23",
                end: "2026-09-21",
                equity: AnalyticsDashboardEquityWireV1(
                    points: [
                        AnalyticsDashboardEquityPointWireV1(
                            t: "2026-09-01T15:00:00.000Z",
                            v: PostgresFlexibleDouble(3242.5),
                            i: 0
                        ),
                    ],
                    max_drawdown: PostgresFlexibleDouble(100),
                    current_equity: PostgresFlexibleDouble(3242.5)
                ),
                distributions: Self.emptyDistributions,
                insights: []
            ),
        ]
        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .all,
            dateRange: .thirtyDays,
            accountCharts: charts
        )
        #expect(bundle?.metrics.trade_count == 11)
        #expect(bundle?.metrics.net_pnl.value == 3063.5)
        #expect(bundle?.equity.current_equity.value == 3242.5)
        #expect(bundle?.equity.points.count == 1)
    }

    @Test("Account charts overlay does not replace KPI metrics")
    func chartsDoNotOverwriteMetrics() throws {
        let bootstrap = try makeBootstrap()
        let accountA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let charts: [String: AnalyticsDashboardChartsPresetV1] = [
            "d30": AnalyticsDashboardChartsPresetV1(
                preset: "d30",
                start: "2026-08-23",
                end: "2026-09-21",
                equity: AnalyticsDashboardEquityWireV1(
                    points: [
                        AnalyticsDashboardEquityPointWireV1(
                            t: "2026-09-01T15:00:00.000Z",
                            v: PostgresFlexibleDouble(999),
                            i: 0
                        ),
                    ],
                    max_drawdown: PostgresFlexibleDouble(0),
                    current_equity: PostgresFlexibleDouble(999)
                ),
                distributions: Self.emptyDistributions,
                insights: []
            ),
        ]
        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(accountA),
            dateRange: .thirtyDays,
            accountCharts: charts
        )
        #expect(bundle?.metrics.trade_count == 1)
        #expect(bundle?.metrics.net_pnl.value == 500)
        #expect(bundle?.equity.points.count == 1)
        #expect(bundle?.equity.current_equity.value == 999)
    }

    @Test("UUID lookup is case-insensitive")
    func caseInsensitiveAccountID() throws {
        let bootstrap = try makeBootstrap()
        let upper = TradingAccountID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: .account(upper),
            dateRange: .thirtyDays
        )
        #expect(bundle?.metrics.trade_count == 1)
    }

    @Test("V3 contract decodes compact payload")
    func decodeContract() throws {
        let json = """
        {
          "meta": {
            "contract_version": "v1",
            "server_time": "2026-09-21T12:00:00.000Z",
            "viewer_id": "00000000-0000-0000-0000-000000000001"
          },
          "data": {
            "revision": 2,
            "as_of_et": "2026-09-21",
            "payout_total": 0,
            "accounts": [],
            "presets": {
                "d30": {
                  "preset": "d30",
                  "start": "2026-08-23",
                  "end": "2026-09-21",
                  "metrics": {
                    "trade_count": 1,
                    "win_count": 1,
                    "loss_count": 0,
                    "breakeven_count": 0,
                    "net_pnl": 100,
                    "gross_profit": 100,
                    "gross_loss": 0,
                    "long_count": 1,
                    "long_pnl": 100,
                    "short_count": 0,
                    "short_pnl": 0,
                    "sum_rr": 2,
                    "rr_count": 1,
                    "sum_hold_seconds": 120,
                    "hold_count": 1,
                    "largest_win": 100,
                    "largest_loss": null
                  },
                  "equity": {
                    "points": [{"t":"2026-09-01T15:00:00.000Z","v":100,"i":0}],
                    "max_drawdown": 0,
                    "current_equity": 100
                  },
                  "distributions": {
                    "sessions": [],
                    "weekday_bars": [],
                    "weekday_heatmap": [],
                    "hour_bars": [],
                    "hour_heatmap": [],
                    "hold_histogram": [],
                    "long_short": [],
                    "long_trade_count": 1,
                    "short_trade_count": 0
                  },
                  "insights": []
                }
            },
            "account_preset_metrics": []
          }
        }
        """
        let decoded = try JSONDecoder().decode(AnalyticsDashboardBootstrapV3.self, from: Data(json.utf8))
        let bundle = decoded.data.aggregatePresets["d30"]
        #expect(bundle?.metrics.trade_count == 1)
        let summary = DashboardAnalyticsMapper.summary(from: bundle!, payoutTotal: nil)
        #expect(summary.tradeCount == 1)
        #expect(summary.netPnL == 100)
    }

    @Test("Disk cache schema version isolates blob")
    func cacheKey() {
        #expect(DashboardAnalyticsDiskCache.schemaVersion == 2)
    }

    @Test("Compact bootstrap presets decode without chart blocks")
    func compactAggregatePresetsDecode() throws {
        let json = """
        {
          "meta": {"contract_version":"v1","server_time":"2026-09-21T12:00:00.000Z","viewer_id":"u"},
          "data": {
            "revision": 1,
            "as_of_et": "2026-09-21",
            "payload_kind": "dashboard_analytics_v3_compact",
            "payout_total": 0,
            "accounts": [],
            "presets": {
              "d7": {
                "preset": "d7",
                "start": "2026-09-15",
                "end": "2026-09-21",
                "metrics": {
                  "trade_count": 0,
                  "win_count": 0,
                  "loss_count": 0,
                  "breakeven_count": 0,
                  "net_pnl": 0,
                  "gross_profit": 0,
                  "gross_loss": 0,
                  "long_count": 0,
                  "long_pnl": 0,
                  "short_count": 0,
                  "short_pnl": 0,
                  "sum_rr": 0,
                  "rr_count": 0,
                  "sum_hold_seconds": 0,
                  "hold_count": 0,
                  "largest_win": null,
                  "largest_loss": null
                }
              }
            },
            "account_preset_metrics": []
          }
        }
        """
        let decoded = try JSONDecoder().decode(AnalyticsDashboardBootstrapV3.self, from: Data(json.utf8))
        #expect(decoded.data.isCompactPayload)
        let bundle = decoded.data.aggregatePresets["d7"]
        #expect(bundle?.metrics.trade_count == 0)
        #expect(bundle?.equity.points.isEmpty == true)
        #expect(bundle?.distributions.sessions.isEmpty == true)
        #expect(bundle?.insights.isEmpty == true)
    }

    private static let emptyDistributions = AnalyticsDashboardDistributionsWireV1(
        sessions: [],
        weekday_bars: [],
        weekday_heatmap: [],
        hour_bars: [],
        hour_heatmap: [],
        avg_hold_seconds: nil,
        avg_winner_hold_seconds: nil,
        avg_loser_hold_seconds: nil,
        hold_histogram: [],
        long_short: [],
        long_trade_count: 0,
        short_trade_count: 0
    )

    func makeBootstrap() throws -> AnalyticsDashboardBootstrapV3 {
        let json = """
        {
          "meta": {"contract_version":"v1","server_time":"2026-09-21T12:00:00.000Z","viewer_id":"u"},
          "data": {
            "revision": 3,
            "as_of_et": "2026-09-21",
            "payout_total": 0,
            "accounts": [
              {"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Alpha Eval"},
              {"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"APEX"}
            ],
            "presets": {
              "d30": {
                "preset":"d30","start":"2026-08-23","end":"2026-09-21",
                "metrics": {
                  "trade_count":11,"win_count":4,"loss_count":3,"breakeven_count":0,
                  "net_pnl":3063.5,"gross_profit":4000,"gross_loss":-936.5,
                  "long_count":0,"long_pnl":0,"short_count":0,"short_pnl":0,
                  "sum_rr":0,"rr_count":0,"sum_hold_seconds":0,"hold_count":0,
                  "largest_win":null,"largest_loss":null
                },
                "equity":{"points":[],"max_drawdown":0,"current_equity":0},
                "distributions":{
                  "sessions":[],"weekday_bars":[],"weekday_heatmap":[],
                  "hour_bars":[],"hour_heatmap":[],"hold_histogram":[],
                  "long_short":[],"long_trade_count":0,"short_trade_count":0
                },
                "insights":[]
              },
              "d90": {
                "preset":"d90","start":"2026-06-23","end":"2026-09-21",
                "metrics": {
                  "trade_count":11,"win_count":4,"loss_count":3,"breakeven_count":0,
                  "net_pnl":3063.5,"gross_profit":4000,"gross_loss":-936.5,
                  "long_count":0,"long_pnl":0,"short_count":0,"short_pnl":0,
                  "sum_rr":0,"rr_count":0,"sum_hold_seconds":0,"hold_count":0,
                  "largest_win":null,"largest_loss":null
                },
                "equity":{"points":[],"max_drawdown":0,"current_equity":0},
                "distributions":{
                  "sessions":[],"weekday_bars":[],"weekday_heatmap":[],
                  "hour_bars":[],"hour_heatmap":[],"hold_histogram":[],
                  "long_short":[],"long_trade_count":0,"short_trade_count":0
                },
                "insights":[]
              }
            },
            "account_preset_metrics": [
              {
                "account_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "presets": {
                  "d30": {
                    "preset":"d30","start":"2026-08-23","end":"2026-09-21",
                    "metrics": {
                      "trade_count":1,"win_count":1,"loss_count":0,"breakeven_count":0,
                      "net_pnl":500,"gross_profit":500,"gross_loss":0,
                      "long_count":0,"long_pnl":0,"short_count":0,"short_pnl":0,
                      "sum_rr":0,"rr_count":0,"sum_hold_seconds":0,"hold_count":0,
                      "largest_win":500,"largest_loss":null
                    }
                  }
                }
              },
              {
                "account_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                "presets": {
                  "d30": {
                    "preset":"d30","start":"2026-08-23","end":"2026-09-21",
                    "metrics": {
                      "trade_count":7,"win_count":2,"loss_count":3,"breakeven_count":0,
                      "net_pnl":-36.5,"gross_profit":100,"gross_loss":-136.5,
                      "long_count":0,"long_pnl":0,"short_count":0,"short_pnl":0,
                      "sum_rr":0,"rr_count":0,"sum_hold_seconds":0,"hold_count":0,
                      "largest_win":null,"largest_loss":null
                    }
                  },
                  "d90": {
                    "preset":"d90","start":"2026-06-23","end":"2026-09-21",
                    "metrics": {
                      "trade_count":7,"win_count":2,"loss_count":3,"breakeven_count":0,
                      "net_pnl":-36.5,"gross_profit":100,"gross_loss":-136.5,
                      "long_count":0,"long_pnl":0,"short_count":0,"short_pnl":0,
                      "sum_rr":0,"rr_count":0,"sum_hold_seconds":0,"hold_count":0,
                      "largest_win":null,"largest_loss":null
                    }
                  }
                }
              }
            ]
          }
        }
        """
        return try JSONDecoder().decode(AnalyticsDashboardBootstrapV3.self, from: Data(json.utf8))
    }

    private func makeBootstrapWithAggregateTradeCounts(
        _ counts: [String: Int]
    ) throws -> AnalyticsDashboardBootstrapV3 {
        var bootstrap = try makeBootstrap()
        guard let template = bootstrap.data.aggregatePresets["d30"] else {
            throw NSError(domain: "test", code: 1)
        }
        var presets: [String: AnalyticsDashboardAggregatePresetV1] = [:]
        for key in AnalyticsLocalDashboardPolicy.aggregatePresetKeys {
            var wire = AnalyticsDashboardAggregatePresetV1(full: template)
            wire.preset = key
            wire.metrics.trade_count = counts[key] ?? 0
            presets[key] = wire
        }
        bootstrap.data.presets = presets
        return bootstrap
    }

    private func makeBootstrapWithAccountTradeCounts(
        _ bootstrap: AnalyticsDashboardBootstrapV3,
        accountID: TradingAccountID,
        counts: [String: Int]
    ) throws -> AnalyticsDashboardBootstrapV3 {
        var next = bootstrap
        let accountKey = accountID.rawValue
        var rows = next.data.account_preset_metrics ?? []
        guard let index = rows.firstIndex(where: { $0.account_id == accountKey }) else {
            throw NSError(domain: "test", code: 2)
        }
        var presets = rows[index].presets
        let template = presets["d30"] ?? presets.values.first
        for (key, count) in counts {
            if var preset = presets[key] {
                preset.metrics.trade_count = count
                presets[key] = preset
            } else if var base = template {
                base.preset = key
                base.metrics.trade_count = count
                presets[key] = base
            }
        }
        rows[index] = AnalyticsDashboardBootstrapV3.AccountPresetMetrics(
            account_id: accountKey,
            presets: presets
        )
        next.data.account_preset_metrics = rows
        return next
    }
}
