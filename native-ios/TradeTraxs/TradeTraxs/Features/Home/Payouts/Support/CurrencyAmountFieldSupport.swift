import Foundation

/// USD currency editing + display helpers for Record Payout money fields.
enum CurrencyAmountFieldSupport {
    private static let editingStyle = NumericInputStyle.unsignedCurrency

    /// Strips grouping/currency symbols and clamps to a valid currency fraction (max 2 decimal places).
    static func sanitizeInput(_ raw: String) -> String {
        NumericInputFieldSupport.formatWhileEditing(raw, style: editingStyle)
    }

    static func parse(_ raw: String) -> Decimal? {
        guard let value = NumericInputFieldSupport.parse(raw, style: editingStyle), value >= 0 else { return nil }
        return value
    }

    /// Standard USD display — always 2 decimal places, e.g. `$53,242.50`.
    static func formatDisplay(_ amount: Decimal) -> String {
        usdDisplayFormatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
    }

    /// Programmatic seed for editable text — grouped whole dollars with cents when present.
    static func seedEditingText(from amount: Decimal) -> String {
        NumericInputFieldSupport.seedEditingText(from: amount, style: editingStyle)
    }

    private static let usdDisplayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
