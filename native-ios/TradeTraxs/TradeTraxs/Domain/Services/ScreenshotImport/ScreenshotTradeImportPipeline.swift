import CoreGraphics
import Foundation

/// End-to-end on-device screenshot import pipeline (Phase 2 + Phase 3 AI integration).
nonisolated enum ScreenshotTradeImportPipeline {
    static func process(blocksByImage: [[OCRTextBlock]]) -> ScreenshotImportProcessResult {
        let tables = ScreenshotTradeTableReconstructor.reconstructStructured(blocksByImage: blocksByImage)
        let tableKind = classifyTables(tables)
        let result: ScreenshotImportProcessResult

        switch tableKind {
        case .executions:
            let exec = ScreenshotExecutionHistoryParser.parse(tables: tables)
            result = processExtractedContent(
                rawFills: exec.fills,
                completedCandidates: [],
                failures: exec.rejectedRows.map {
                    CSVParseRowFailure(rowNumber: $0.rowIndex + 1, reason: $0.reason)
                },
                imagesProcessed: blocksByImage.count,
                isAIAssisted: false,
                aiWarnings: []
            )
            logDiagnostics(
                blocksByImage: blocksByImage,
                tables: tables,
                tableKind: tableKind,
                completedCount: 0,
                executionCount: exec.fills.count,
                ignoredCancelled: exec.ignoredCancelledRows,
                rejectedRows: exec.rejectedRows,
                reviewWarnings: result.summary.trades.flatMap(\.warningMessages)
            )

        case .completedTrades:
            let completed = ScreenshotCompletedTradeParser.parse(tables: tables)
            result = processExtractedContent(
                rawFills: [],
                completedCandidates: completed.candidates,
                failures: completed.rejectedRows.map {
                    CSVParseRowFailure(rowNumber: $0.rowIndex + 1, reason: $0.reason)
                },
                imagesProcessed: blocksByImage.count,
                isAIAssisted: false,
                aiWarnings: []
            )
            logDiagnostics(
                blocksByImage: blocksByImage,
                tables: tables,
                tableKind: tableKind,
                completedCount: completed.candidates.count,
                executionCount: 0,
                ignoredCancelled: 0,
                rejectedRows: completed.rejectedRows,
                reviewWarnings: result.summary.trades.flatMap(\.warningMessages)
            )

        case .unknown:
            let rows = tables.flatMap(\.legacyRows)
            result = processLegacy(rows: rows, imagesProcessed: blocksByImage.count)
            logDiagnostics(
                blocksByImage: blocksByImage,
                tables: tables,
                tableKind: tableKind,
                completedCount: result.summary.trades.filter(\.isImportable).count,
                executionCount: result.fillsProcessed,
                ignoredCancelled: 0,
                rejectedRows: [],
                reviewWarnings: result.summary.trades.flatMap(\.warningMessages)
            )
        }

        let quality = ScreenshotImportConfidenceEvaluator.evaluate(
            result: result,
            blocksByImage: blocksByImage
        )
        return ScreenshotImportProcessResult(
            summary: result.summary,
            metadataByTradeID: result.metadataByTradeID,
            fillsProcessed: result.fillsProcessed,
            fillsDeduped: result.fillsDeduped,
            extractionQuality: quality,
            isAIAssisted: false,
            aiWarnings: result.aiWarnings
        )
    }

    static func process(cgImages: [CGImage]) async throws -> ScreenshotImportProcessResult {
        let blocks = try await ScreenshotTradeOCRService.recognizeText(in: cgImages)
        return process(blocksByImage: blocks)
    }

    /// Phase 3 — normalize AI extraction through the same Phase 2 aggregation path.
    static func processAIExtraction(
        _ extraction: ScreenshotAIExtractionV1,
        imagesProcessed: Int
    ) -> ScreenshotImportProcessResult {
        let normalized = ScreenshotAIExtractionNormalizer.normalize(extraction)
        let result = processExtractedContent(
            rawFills: normalized.fills,
            completedCandidates: normalized.completed,
            failures: [],
            imagesProcessed: imagesProcessed,
            isAIAssisted: true,
            aiWarnings: normalized.warnings
        )
        return ScreenshotImportProcessResult(
            summary: result.summary,
            metadataByTradeID: markAIAssisted(result.metadataByTradeID),
            fillsProcessed: result.fillsProcessed,
            fillsDeduped: result.fillsDeduped,
            extractionQuality: result.summary.successCount > 0 ? .confident : .insufficient,
            isAIAssisted: true,
            aiWarnings: normalized.warnings
        )
    }

    /// Backward-compatible summary-only entry for tests that only need `CSVParseSummary`.
    static func processSummary(blocksByImage: [[OCRTextBlock]]) -> CSVParseSummary {
        process(blocksByImage: blocksByImage).summary
    }

    private static func classifyTables(_ tables: [ScreenshotStructuredTable]) -> ScreenshotTableKind {
        let kinds = tables.map { ScreenshotTableClassifier.classify(table: $0) }
        let completed = kinds.filter { $0 == .completedTrades }.count
        let executions = kinds.filter { $0 == .executions }.count
        if completed > executions { return .completedTrades }
        if executions > completed { return .executions }
        if completed > 0 { return .completedTrades }
        if executions > 0 { return .executions }
        return .unknown
    }

    private static func processLegacy(
        rows: [ScreenshotTableRow],
        imagesProcessed: Int
    ) -> ScreenshotImportProcessResult {
        let rawFills = ScreenshotTradePlatformRegistry.parseFills(from: rows)
        let parseResult = ScreenshotTradeParser.parse(rows: rows)
        let completedCandidates = parseResult.candidates.filter { $0.kind == .completedTrade }
        return processExtractedContent(
            rawFills: rawFills,
            completedCandidates: completedCandidates,
            failures: parseResult.failures,
            imagesProcessed: imagesProcessed,
            isAIAssisted: false,
            aiWarnings: []
        )
    }

    private static func processExtractedContent(
        rawFills: [ParsedTradeFill],
        completedCandidates: [ScreenshotParsedCandidate],
        failures: [CSVParseRowFailure],
        imagesProcessed: Int,
        isAIAssisted: Bool,
        aiWarnings: [String]
    ) -> ScreenshotImportProcessResult {
        let (dedupedFills, removedFillCount) = ScreenshotFillDedup.dedupe(rawFills)
        let roundTrips = TradeFillAggregator.aggregate(fills: dedupedFills)
        let aggregated = ScreenshotFillImportNormalizer.normalize(roundTrips: roundTrips)

        let dedupedCompleted = ScreenshotTradeBatchDedup.dedupe(completedCandidates)
        let completedSummary = ScreenshotTradeImportNormalizer.normalize(
            parseResult: ScreenshotImportParseResult(
                candidates: dedupedCompleted,
                failures: failures,
                imagesProcessed: imagesProcessed
            ),
            dedupedCandidates: dedupedCompleted
        )

        var trades: [CSVParsedTrade] = aggregated.map { $0.trade }
        var metadataByTradeID = Dictionary(uniqueKeysWithValues: aggregated.map { ($0.trade.id, $0.metadata) })

        if isAIAssisted {
            metadataByTradeID = markAIAssisted(metadataByTradeID)
            for index in trades.indices {
                var trade = trades[index]
                if !trade.warningMessages.contains("AI-assisted extraction") {
                    trade.warningMessages.append("AI-assisted extraction")
                }
                trade.status = .needsReview
                trades[index] = trade
            }
        }

        let aggregatedFingerprints = Set(metadataByTradeID.values.compactMap(\.importFingerprint))
        var rowNumber = trades.count + 1
        for completed in completedSummary.trades {
            let fingerprint = ImportFingerprint.forAggregatedTrade(
                symbol: completed.symbol,
                side: completed.side,
                quantity: completed.quantity,
                entryPrice: completed.entryPrice,
                exitPrice: completed.exitPrice,
                entryAt: completed.entryAt,
                exitAt: completed.exitAt,
                accountID: nil
            )
            if aggregatedFingerprints.contains(fingerprint) { continue }
            var trade = completed
            trade.rowNumber = rowNumber
            rowNumber += 1
            if isAIAssisted {
                trade.status = .needsReview
                if !trade.warningMessages.contains("AI-assisted extraction") {
                    trade.warningMessages.append("AI-assisted extraction")
                }
            }
            trades.append(trade)
            metadataByTradeID[trade.id] = ScreenshotImportTradeMetadata(
                fills: [],
                entryFillCount: 0,
                exitFillCount: 0,
                aggregationSource: .completedRow,
                reportedPnL: completed.realizedPnL == 0 ? nil : completed.realizedPnL,
                calculatedPnL: nil,
                pnlSource: .reported,
                aggregatedFees: nil,
                importFingerprint: fingerprint,
                duplicateClassification: .newTrade,
                isSelectedForImport: true,
                warnings: completed.warningMessages,
                extractionSource: isAIAssisted ? .aiAssisted : .deterministic
            )
        }

        let successCount = trades.filter(\.isImportable).count
        let summary = CSVParseSummary(
            format: .screenshot,
            fileName: "screenshot-import",
            totalRows: rawFills.count + completedCandidates.count,
            successCount: successCount,
            failedCount: failures.count + removedFillCount,
            headers: [],
            trades: trades,
            failures: failures
        )

        return ScreenshotImportProcessResult(
            summary: summary,
            metadataByTradeID: metadataByTradeID,
            fillsProcessed: rawFills.count,
            fillsDeduped: removedFillCount,
            extractionQuality: .confident,
            isAIAssisted: isAIAssisted,
            aiWarnings: aiWarnings
        )
    }

    private static func logDiagnostics(
        blocksByImage: [[OCRTextBlock]],
        tables: [ScreenshotStructuredTable],
        tableKind: ScreenshotTableKind,
        completedCount: Int,
        executionCount: Int,
        ignoredCancelled: Int,
        rejectedRows: [ScreenshotImportRejectedRow],
        reviewWarnings: [String]
    ) {
        #if DEBUG
        let diagnostics = ScreenshotImportDiagnosticsBuilder.build(
            blocksByImage: blocksByImage,
            tables: tables,
            tableKind: tableKind,
            completedCount: completedCount,
            executionCount: executionCount,
            ignoredCancelled: ignoredCancelled,
            rejectedRows: rejectedRows,
            reviewWarnings: reviewWarnings
        )
        ScreenshotImportDiagnosticsLogger.log(diagnostics)
        #endif
    }

    private static func markAIAssisted(
        _ metadata: [String: ScreenshotImportTradeMetadata]
    ) -> [String: ScreenshotImportTradeMetadata] {
        metadata.mapValues { item in
            var updated = item
            updated.extractionSource = .aiAssisted
            if !updated.warnings.contains("AI-assisted extraction") {
                updated.warnings.append("AI-assisted extraction")
            }
            return updated
        }
    }
}
