import Foundation

/// Shared OCR text normalization and token detection for broker screenshots.
nonisolated enum ScreenshotBrokerText {
    static func normalizeSymbol(_ raw: String) -> String {
        FuturesInstrumentRegistry.normalizeSymbol(raw)
    }

    static func extractSymbol(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let upper = trimmed.uppercased()
        let brokerPattern = #"(?:XCME[_\s.\-]*\w+\s+)?([A-Z]{2,4})\s*\([A-Z]?\d{1,2}\)"#
        if let regex = try? NSRegularExpression(pattern: brokerPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let root = Range(match.range(at: 1), in: upper)
        {
            let code = String(upper[root])
            if FuturesInstrumentRegistry.resolve(symbol: code) != nil {
                return code
            }
        }

        let normalized = normalizeSymbol(trimmed)
        if FuturesInstrumentRegistry.resolve(symbol: normalized) != nil {
            return normalized
        }

        if trimmed.range(of: #"^[A-Z][A-Z0-9]{0,5}$"#, options: .regularExpression) != nil,
           !["LONG", "SHORT", "BUY", "SELL", "MARKET", "LIMIT", "FILLED"].contains(upper)
        {
            return normalized
        }
        return nil
    }

    static func isBuySell(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return s == "BUY" || s == "SELL" || s == "BOT" || s == "SLD"
    }

    static func isLongShort(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s == "LONG" || s == "LONO" || s.hasPrefix("LONG") { return true }
        if s == "SHORT" || s.hasPrefix("SHORT") { return true }
        return false
    }

    static func isOrderType(_ text: String) -> Bool {
        let s = text.uppercased()
        return s == "MARKET" || s == "LIMIT" || s == "STOP" || s == "MIT"
    }

    static func isExecutionStatus(_ text: String) -> Bool {
        let s = text.uppercased()
        if s == "FILLED" || s == "ALLED" || s.hasSuffix("FILLED") { return true }
        if s == "CANCELLED" || s == "CANCELED" || s.contains("CANCEL") { return true }
        if s == "REJECTED" || s == "WORKING" || s == "PENDING" { return true }
        return false
    }

    static func isNonFillStatus(_ text: String) -> Bool {
        let s = text.uppercased()
        if s.contains("CANCEL") { return true }
        if s == "REJECTED" || s == "WORKING" || s == "PENDING" { return true }
        return false
    }

    static func isFilledStatus(_ text: String) -> Bool {
        let s = text.uppercased()
        return s == "FILLED" || s == "ALLED" || s.contains("FILLED")
    }

    static func isTriggerAction(_ text: String) -> Bool {
        let s = text.lowercased()
        return s.contains("trigger") || s.contains("oco pull") || s.contains("0co pull") || s.contains("flatten")
    }

    static func isTimestamp(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#, options: .regularExpression) != nil {
            return true
        }
        if s.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil &&
            s.range(of: #"\d{4}"#, options: .regularExpression) != nil
        {
            return true
        }
        return false
    }

    static func parseDirection(_ raw: String?) -> TradeSide? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.isEmpty { return nil }

        for token in s.split(separator: " ").map(String.init) {
            if token == "SHORT" || token.hasPrefix("SHORT") { return .short }
            if token == "LONG" || token == "LONO" || token.hasPrefix("LONG") { return .long }
        }

        if s.contains("SHORT") { return .short }
        if s.contains("LONG") || s == "LONO" { return .long }
        if s == "BUY" || s == "B" || s.contains("BUY") { return .long }
        if s == "SELL" || s == "S" || s.contains("SELL") { return .short }
        return nil
    }

    static func parseSideFromOpenSide(_ raw: String?) -> TradeSide? {
        guard let raw else { return nil }
        let s = raw.uppercased()
        if s.contains("BUY") { return .long }
        if s.contains("SELL") { return .short }
        return nil
    }

    static func parsePosition(_ raw: String?) -> TradeSide? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s == "B" || s == "BUY" || s == "LONG" || s.hasPrefix("LONG") { return .long }
        if s == "S" || s == "SELL" || s == "SHORT" || s.hasPrefix("SHORT") { return .short }
        return nil
    }
}
