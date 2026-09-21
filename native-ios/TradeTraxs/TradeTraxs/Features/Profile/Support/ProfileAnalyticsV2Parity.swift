import Foundation

nonisolated enum ProfileAnalyticsV2ParityClassification: String, Sendable {
    case pass = "PASS"
    case v2Bug = "V2_BUG"
    case v1Legacy = "V1_LEGACY"
    case expectedSemantic = "EXPECTED_SEMANTIC"
    case inconclusive = "INCONCLUSIVE"
}

nonisolated enum ProfileAnalyticsV2Parity {
    struct FieldMismatch: Sendable, Equatable {
        var profileID: String
        var mode: ProfileStatisticsMetrics.Mode
        var field: String
        var v1Value: String
        var v2Value: String
        var classification: ProfileAnalyticsV2ParityClassification
    }

    struct GateComparison: Sendable, Equatable {
        var v1GateOpen: Bool
        var v2Found: Bool
        var matches: Bool
    }

    static func compareGate(
        v1CanViewStatistics: Bool,
        v2Found: Bool
    ) -> GateComparison {
        GateComparison(
            v1GateOpen: v1CanViewStatistics,
            v2Found: v2Found,
            matches: v1CanViewStatistics == v2Found
        )
    }

    static func compareModes(
        profileID: ProfileID,
        v1: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result],
        v2: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result],
        decimalTolerance: Decimal = 0.01
    ) -> [FieldMismatch] {
        var mismatches: [FieldMismatch] = []
        let modes = Set(v1.keys).union(v2.keys)

        for mode in modes.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let left = v1[mode], let right = v2[mode] else {
                mismatches.append(
                    FieldMismatch(
                        profileID: profileID.rawValue,
                        mode: mode,
                        field: "mode_presence",
                        v1Value: v1[mode] == nil ? "missing" : "present",
                        v2Value: v2[mode] == nil ? "missing" : "present",
                        classification: .v2Bug
                    )
                )
                continue
            }
            mismatches.append(
                contentsOf: compareResult(
                    profileID: profileID,
                    mode: mode,
                    v1: left,
                    v2: right,
                    decimalTolerance: decimalTolerance
                )
            )
        }
        return mismatches
    }

    private static func compareResult(
        profileID: ProfileID,
        mode: ProfileStatisticsMetrics.Mode,
        v1: ProfileStatisticsMetrics.Result,
        v2: ProfileStatisticsMetrics.Result,
        decimalTolerance: Decimal
    ) -> [FieldMismatch] {
        var out: [FieldMismatch] = []

        func checkInt(_ field: String, _ a: Int, _ b: Int) {
            guard a == b else {
                out.append(
                    FieldMismatch(
                        profileID: profileID.rawValue,
                        mode: mode,
                        field: field,
                        v1Value: "\(a)",
                        v2Value: "\(b)",
                        classification: .v2Bug
                    )
                )
                return
            }
        }

        func checkOptionalDecimal(_ field: String, _ a: Decimal?, _ b: Decimal?) {
            switch (a, b) {
            case (nil, nil):
                return
            case let (av?, bv?):
                if abs(av - bv) > decimalTolerance {
                    out.append(
                        FieldMismatch(
                            profileID: profileID.rawValue,
                            mode: mode,
                            field: field,
                            v1Value: "\(av)",
                            v2Value: "\(bv)",
                            classification: .v2Bug
                        )
                    )
                }
            default:
                out.append(
                    FieldMismatch(
                        profileID: profileID.rawValue,
                        mode: mode,
                        field: field,
                        v1Value: a.map { "\($0)" } ?? "nil",
                        v2Value: b.map { "\($0)" } ?? "nil",
                        classification: .v2Bug
                    )
                )
            }
        }

        checkInt("filtered_trade_count", v1.filteredTradeCount, v2.filteredTradeCount)
        checkOptionalDecimal("win_rate", v1.winRate, v2.winRate)
        checkOptionalDecimal("profit_factor", v1.profitFactor, v2.profitFactor)
        checkOptionalDecimal("average_winner", v1.averageWinner, v2.averageWinner)
        checkOptionalDecimal("average_loser", v1.averageLoser, v2.averageLoser)
        checkOptionalDecimal("profit_per_trade", v1.profitPerTrade, v2.profitPerTrade)
        checkOptionalDecimal("biggest_win", v1.biggestWin, v2.biggestWin)
        checkOptionalDecimal("biggest_loss", v1.biggestLoss, v2.biggestLoss)
        checkInt("long_trades", v1.longTrades, v2.longTrades)
        checkInt("max_win_streak", v1.maxWinStreak, v2.maxWinStreak)
        checkInt("max_loss_streak", v1.maxLossStreak, v2.maxLossStreak)
        checkInt("session_total", v1.sessionTotal, v2.sessionTotal)
        checkOptionalDecimal("current_equity", v1.currentEquity, v2.currentEquity)

        if v1.sessionBreakdown != v2.sessionBreakdown {
            out.append(
                FieldMismatch(
                    profileID: profileID.rawValue,
                    mode: mode,
                    field: "session_breakdown",
                    v1Value: "\(v1.sessionBreakdown.count) rows",
                    v2Value: "\(v2.sessionBreakdown.count) rows",
                    classification: .v2Bug
                )
            )
        }

        if v1.equityData.count != v2.equityData.count {
            out.append(
                FieldMismatch(
                    profileID: profileID.rawValue,
                    mode: mode,
                    field: "equity_data.count",
                    v1Value: "\(v1.equityData.count)",
                    v2Value: "\(v2.equityData.count)",
                    classification: .v2Bug
                )
            )
        } else {
            for (index, pair) in zip(v1.equityData, v2.equityData).enumerated() {
                if pair.0.index != pair.1.index {
                    out.append(
                        FieldMismatch(
                            profileID: profileID.rawValue,
                            mode: mode,
                            field: "equity_data[\(index)].index",
                            v1Value: "\(pair.0.index)",
                            v2Value: "\(pair.1.index)",
                            classification: .v2Bug
                        )
                    )
                }
                if abs(pair.0.equity - pair.1.equity) > decimalTolerance {
                    out.append(
                        FieldMismatch(
                            profileID: profileID.rawValue,
                            mode: mode,
                            field: "equity_data[\(index)].equity",
                            v1Value: "\(pair.0.equity)",
                            v2Value: "\(pair.1.equity)",
                            classification: .v2Bug
                        )
                    )
                }
            }
        }

        return out
    }
}
