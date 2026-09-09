import Foundation

/// Locale-aware numeric presentation for user-facing TradeTraxs UI.
///
/// Display-only — never mutates domain values. Prefer these helpers over
/// ad-hoc `String(format:)` / string interpolation for counts, currency, and percentages.
nonisolated enum NumberDisplay {
    // MARK: - Integers

    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func integer(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    // MARK: - Decimals

    static func decimal(
        _ value: Decimal,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 2
    ) -> String {
        formatDouble(
            NSDecimalNumber(decimal: value).doubleValue,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    static func decimal(
        _ value: Double,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 2
    ) -> String {
        formatDouble(
            value,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    /// General-purpose ratio/metric (`1,234.56`).
    static func ratio(_ value: Decimal, fractionDigits: Int = 2) -> String {
        decimal(value, minimumFractionDigits: 0, maximumFractionDigits: fractionDigits)
    }

    static func ratio(_ value: Double, fractionDigits: Int = 2) -> String {
        decimal(value, minimumFractionDigits: 0, maximumFractionDigits: fractionDigits)
    }

    // MARK: - Currency / P&L

    /// `$1,250.00`, `-$1,250.50`, optional `+$6,254.00`.
    static func currency(
        _ value: Decimal,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 2,
        explicitPlus: Bool = false
    ) -> String {
        signedCurrencyPrefix(
            value: value,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits,
            explicitPlus: explicitPlus
        )
    }

    static func currency(
        _ value: Double,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 2,
        explicitPlus: Bool = false
    ) -> String {
        signedCurrencyPrefix(
            value: Decimal(value),
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits,
            explicitPlus: explicitPlus
        )
    }

    /// Whole-dollar P&L — `+$1,250`, `-$450` (Trade cards / leaderboard).
    static func pnlWholeDollars(_ money: Money?) -> String {
        guard let amount = money?.amount else { return "—" }
        return signedCurrencyPrefix(
            value: amount,
            minimumFractionDigits: 0,
            maximumFractionDigits: 0,
            explicitPlus: amount > 0
        )
    }

    /// Profile / dashboard currency — `$1,250.00`, `-$1,250.50`.
    static func money(_ amount: Decimal?) -> String {
        guard let amount else { return "—" }
        return signedCurrencyPrefix(
            value: amount,
            minimumFractionDigits: 0,
            maximumFractionDigits: 2,
            explicitPlus: false
        )
    }

    /// Signed currency with explicit `+` on positive values.
    static func signedMoney(_ value: Decimal) -> String {
        signedCurrencyPrefix(
            value: value,
            minimumFractionDigits: 0,
            maximumFractionDigits: 2,
            explicitPlus: value > 0
        )
    }

    static func signedMoney(_ value: Double) -> String {
        signedMoney(Decimal(value))
    }

    /// Report-style P&L — preserves two decimal places.
    static func reportPnL(_ value: Double) -> String {
        currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    static func reportPnL(_ value: Decimal) -> String {
        currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    /// Chart axis / tooltip — whole dollars, optional explicit `+` on meaningful gains.
    static func chartSignedCurrency(_ value: Double) -> String {
        if value > 0.01 {
            return currency(value, minimumFractionDigits: 0, maximumFractionDigits: 0, explicitPlus: true)
        }
        if value < -0.01 {
            return currency(value, minimumFractionDigits: 0, maximumFractionDigits: 0)
        }
        return currency(abs(value), minimumFractionDigits: 0, maximumFractionDigits: 0)
    }

    /// Unsigned whole-dollar currency for chart accessibility labels.
    static func chartCurrency(_ value: Double) -> String {
        currency(value, minimumFractionDigits: 0, maximumFractionDigits: 0)
    }

    /// Journal-style reward multiple — `1:2.9`.
    static func journalRewardMultiple(_ value: Decimal) -> String {
        "1:\(decimal(value, minimumFractionDigits: 1, maximumFractionDigits: 1))"
    }

    // MARK: - Percentages

    /// Percent on a 0–100 scale — `1,250%`, `1,250.5%`, `-1,250.5%`.
    static func percent(
        _ value: Double,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 1,
        explicitPlus: Bool = false
    ) -> String {
        signedPercentPrefix(
            value: value,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits,
            explicitPlus: explicitPlus
        )
    }

    static func percent(
        _ value: Decimal,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 1,
        explicitPlus: Bool = false
    ) -> String {
        percent(
            NSDecimalNumber(decimal: value).doubleValue,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits,
            explicitPlus: explicitPlus
        )
    }

    /// Win rate stored as 0–1 fraction.
    static func winRate(_ rate: Decimal?) -> String {
        guard let rate else { return "—" }
        let percentValue = NSDecimalNumber(decimal: rate * 100).doubleValue
        if percentValue.rounded() == percentValue {
            return percent(percentValue, minimumFractionDigits: 0, maximumFractionDigits: 0)
        }
        return percent(percentValue, minimumFractionDigits: 1, maximumFractionDigits: 1)
    }

    /// Profit factor / generic factor — `1,234.56`.
    static func factor(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return ratio(value, fractionDigits: 2)
    }

    // MARK: - Compact social counts (K / M)

    /// Compact follower/member counts — `1.2K`, `15K`, `1.4M`. Values under 1,000 use grouping.
    static func compactCount(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            let scaled = Double(absolute) / 1_000_000
            return trimmedCompact(scaled) + "M"
        }
        if absolute >= 1_000 {
            let scaled = Double(absolute) / 1_000
            return trimmedCompact(scaled) + "K"
        }
        return integer(value)
    }

    /// Like/engagement compact counts — preserves existing K/M thresholds.
    static func compactEngagementCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return decimal(Double(value) / 1_000_000, minimumFractionDigits: 1, maximumFractionDigits: 1) + "M"
        }
        if value >= 1_000 {
            return decimal(Double(value) / 1_000, minimumFractionDigits: 1, maximumFractionDigits: 1) + "K"
        }
        return integer(value)
    }

    /// Chart axis compact currency — preserves `$1.2K` behavior for large magnitudes.
    static func compactCurrencyAxis(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let sign = number < 0 ? "-" : "+"
        let absValue = abs(number)
        if absValue >= 10_000 {
            let scaled = absValue / 1_000
            return "\(sign)$\(decimal(scaled, minimumFractionDigits: 1, maximumFractionDigits: 1))K"
        }
        if absValue >= 1_000 {
            let k = absValue / 1_000
            if k.rounded() == k {
                return "\(sign)$\(integer(Int(k)))K"
            }
            return "\(sign)$\(decimal(k, minimumFractionDigits: 1, maximumFractionDigits: 1))K"
        }
        return "\(sign)$\(integer(Int(absValue.rounded())))"
    }

    /// Equity curve Y-axis — compact K for large values, grouped full value otherwise.
    static func compactEquityAxis(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted: String
        if absValue >= 1_000 {
            formatted = decimal(absValue / 1_000, minimumFractionDigits: 1, maximumFractionDigits: 1) + "K"
        } else {
            formatted = decimal(absValue, minimumFractionDigits: 0, maximumFractionDigits: 0)
        }
        return value < 0 ? "-$\(formatted)" : "$\(formatted)"
    }

    // MARK: - Labels

    static func tradeCount(_ count: Int) -> String {
        count == 1 ? "1 trade" : "\(integer(count)) trades"
    }

    static func memberCount(_ count: Int) -> String {
        "\(compactCount(count)) members"
    }

    /// Rating on a 1–5 scale — `4.2/5`.
    static func ratingOutOfFive(_ value: Double, fractionDigits: Int = 1) -> String {
        "\(decimal(value, minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits))/5"
    }

    /// Duration in hours — `7.5h`.
    static func hours(_ value: Double, fractionDigits: Int = 1) -> String {
        "\(decimal(value, minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits))h"
    }

    /// Multiplier — `2.5×`.
    static func multiple(_ value: Double, fractionDigits: Int = 1) -> String {
        "\(decimal(value, minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits))×"
    }

    /// R multiple label — `1.5R`.
    static func rMultiple(_ value: Double, fractionDigits: Int = 1) -> String {
        "\(decimal(abs(value), minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits))R"
    }

    // MARK: - Private

    private static func formatDouble(
        _ value: Double,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(minimumFractionDigits...maximumFractionDigits))
                .grouping(.automatic)
        )
    }

    private static func signedCurrencyPrefix(
        value: Decimal,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int,
        explicitPlus: Bool
    ) -> String {
        let absAmount = abs(value)
        let body = decimal(
            absAmount,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        if value < 0 { return "-$\(body)" }
        if explicitPlus && value > 0 { return "+$\(body)" }
        return "$\(body)"
    }

    private static func signedPercentPrefix(
        value: Double,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int,
        explicitPlus: Bool
    ) -> String {
        let absValue = abs(value)
        let body = formatDouble(
            absValue,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        if value < 0 { return "-\(body)%" }
        if explicitPlus && value > 0 { return "+\(body)%" }
        return "\(body)%"
    }

    private static func trimmedCompact(_ value: Double) -> String {
        if value.rounded() == value {
            return integer(Int(value))
        }
        let tenths = Int((value * 10).rounded())
        let whole = tenths / 10
        let fraction = abs(tenths % 10)
        return fraction == 0 ? "\(whole)" : "\(whole).\(fraction)"
    }
}
