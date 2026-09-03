import Foundation

/// Maps AI extraction JSON into Phase 2 models — TradeTraxs calculates authoritative values.
nonisolated enum ScreenshotAIExtractionNormalizer {
    static func normalize(
        _ extraction: ScreenshotAIExtractionV1
    ) -> (fills: [ParsedTradeFill], completed: [ScreenshotParsedCandidate], warnings: [String]) {
        var globalWarnings = extraction.warnings
        if extraction.contentType == "mixed" {
            globalWarnings.append("AI detected mixed content")
        }

        let platform = mapPlatform(extraction.detectedPlatform)
        let fills = extraction.fills.compactMap { normalizeFill($0, platform: platform) }
        let completed = extraction.completedTrades.compactMap { normalizeCompletedTrade($0) }
        return (fills, completed, globalWarnings)
    }

    private static func normalizeFill(
        _ fill: ScreenshotAIExtractFill,
        platform: ScreenshotImportPlatform?
    ) -> ParsedTradeFill? {
        guard let symbol = observedOrInferredString(fill.symbol),
              let sideRaw = observedOrInferredString(fill.side),
              let quantity = observedOrInferredDecimal(fill.quantity),
              let price = observedOrInferredDecimal(fill.price)
        else { return nil }

        let action: ParsedTradeFill.Action = sideRaw.lowercased().hasPrefix("s") ? .sell : .buy
        var warnings = fill.warnings ?? []
        warnings.append(contentsOf: provenanceStringWarnings(
            fields: [
                ("symbol", fill.symbol),
                ("side", fill.side),
                ("time", fill.executedAt),
            ]
        ))
        warnings.append(contentsOf: provenanceNumberWarnings(
            fields: [
                ("quantity", fill.quantity),
                ("price", fill.price),
            ]
        ))
        warnings.append("AI-assisted extraction")

        let executedAt = parseDate(observedOrInferredString(fill.executedAt)) ?? Date()
        if fill.executedAt.provenance == .missing || fill.executedAt.value == nil {
            warnings.append("Confirm date")
        }

        return ParsedTradeFill(
            id: fill.id,
            symbol: FuturesInstrumentRegistry.normalizeSymbol(symbol),
            action: action,
            quantity: quantity,
            price: price,
            executedAt: executedAt,
            reportedPnL: optionalDecimal(fill.reportedPnL),
            commission: optionalDecimal(fill.fees),
            executionID: optionalString(fill.executionID),
            orderID: optionalString(fill.orderID),
            sourcePlatform: platform,
            sourceImageIndex: fill.sourceImageIndex,
            sourceRowIndex: fill.sourceImageIndex,
            warnings: Array(Set(warnings))
        )
    }

    private static func normalizeCompletedTrade(
        _ trade: ScreenshotAIExtractCompletedTrade
    ) -> ScreenshotParsedCandidate? {
        guard let symbol = observedOrInferredString(trade.symbol),
              let sideRaw = observedOrInferredString(trade.side),
              let quantity = observedOrInferredDecimal(trade.quantity),
              let entryPrice = observedOrInferredDecimal(trade.entryPrice),
              let exitPrice = observedOrInferredDecimal(trade.exitPrice)
        else { return nil }

        let side: TradeSide = sideRaw.lowercased().contains("short") ? .short : .long
        var warnings = trade.warnings ?? []
        warnings.append(contentsOf: provenanceStringWarnings(
            fields: [
                ("symbol", trade.symbol),
                ("direction", trade.side),
                ("entry time", trade.entryAt),
            ]
        ))
        warnings.append(contentsOf: provenanceNumberWarnings(
            fields: [
                ("quantity", trade.quantity),
                ("entry", trade.entryPrice),
                ("exit", trade.exitPrice),
            ]
        ))
        warnings.append("AI-assisted extraction")

        let entryAt = parseDate(observedOrInferredString(trade.entryAt)) ?? Date()
        let exitAt = parseDate(optionalString(trade.exitAt))
        if trade.entryAt.provenance == .missing || trade.entryAt.value == nil {
            warnings.append("Confirm date")
        }
        if trade.side.provenance == .inferred {
            warnings.append("Review direction")
        }
        if trade.reportedPnL?.provenance == .inferred {
            warnings.append("Review P&L")
        }

        return ScreenshotParsedCandidate(
            id: trade.id,
            kind: .completedTrade,
            symbol: FuturesInstrumentRegistry.normalizeSymbol(symbol),
            side: side,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            entryAt: entryAt,
            exitAt: exitAt,
            realizedPnL: optionalDecimal(trade.reportedPnL),
            points: optionalDecimal(trade.points),
            executionID: optionalString(trade.executionID),
            orderID: optionalString(trade.orderID),
            warnings: Array(Set(warnings)),
            sourceImageIndex: trade.sourceImageIndex,
            sourceRowIndex: trade.sourceImageIndex
        )
    }

    private static func mapPlatform(_ raw: String?) -> ScreenshotImportPlatform? {
        guard let raw else { return nil }
        let lower = raw.lowercased()
        if lower.contains("tradovate") { return .tradovate }
        if lower.contains("alpha") { return .alpha }
        return .generic
    }

    private static func observedOrInferredString<T>(_ field: ScreenshotAIField<T>) -> String? where T: LosslessStringConvertible {
        guard field.provenance != .missing, let value = field.value else { return nil }
        let string = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    private static func observedOrInferredDecimal(_ field: ScreenshotAIField<Double>) -> Decimal? {
        guard field.provenance != .missing, let value = field.value else { return nil }
        return Decimal(value)
    }

    private static func optionalDecimal(_ field: ScreenshotAIField<Double>?) -> Decimal? {
        guard let field, field.provenance != .missing, let value = field.value else { return nil }
        return Decimal(value)
    }

    private static func optionalString(_ field: ScreenshotAIField<String>?) -> String? {
        guard let field, field.provenance != .missing, let value = field.value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func provenanceStringWarnings(
        fields: [(String, ScreenshotAIField<String>)]
    ) -> [String] {
        fields.compactMap { label, field in
            if field.provenance == .inferred {
                return "Review \(label)"
            }
            if field.provenance == .missing {
                return "\(label.capitalized) missing"
            }
            return nil
        }
    }

    private static func provenanceNumberWarnings(
        fields: [(String, ScreenshotAIField<Double>)]
    ) -> [String] {
        fields.compactMap { label, field in
            if field.provenance == .inferred {
                return "Review \(label)"
            }
            if field.provenance == .missing {
                return "\(label.capitalized) missing"
            }
            return nil
        }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy",
            "h:mm a",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
