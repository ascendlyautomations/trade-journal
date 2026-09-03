import Foundation

#if DEBUG
nonisolated enum ScreenshotImportDiagnosticsLogger {
    static func log(_ diagnostics: ScreenshotImportDiagnostics) {
        print("[ScreenshotImport] OCR observations: \(diagnostics.ocrObservationCount)")
        print("[ScreenshotImport] Table kind: \(diagnostics.tableKind.rawValue)")
        print("[ScreenshotImport] Headers: \(diagnostics.detectedHeaders.joined(separator: ", "))")
        print("[ScreenshotImport] Reconstructed rows: \(diagnostics.reconstructedRowCount)")
        print("[ScreenshotImport] Completed candidates: \(diagnostics.completedTradeCandidates)")
        print("[ScreenshotImport] Execution fills: \(diagnostics.executionCandidates)")
        print("[ScreenshotImport] Ignored cancelled rows: \(diagnostics.ignoredCancelledRows)")
        for rejected in diagnostics.rejectedRows.prefix(20) {
            print("[ScreenshotImport] Rejected row \(rejected.rowIndex): \(rejected.reason)")
        }
        for warning in diagnostics.reviewWarnings.prefix(20) {
            print("[ScreenshotImport] Review: \(warning)")
        }
    }
}
#endif

nonisolated enum ScreenshotImportDiagnosticsBuilder {
    static func build(
        blocksByImage: [[OCRTextBlock]],
        tables: [ScreenshotStructuredTable],
        tableKind: ScreenshotTableKind,
        completedCount: Int,
        executionCount: Int,
        ignoredCancelled: Int,
        rejectedRows: [ScreenshotImportRejectedRow],
        reviewWarnings: [String]
    ) -> ScreenshotImportDiagnostics {
        let headers = tables.flatMap { $0.columns.map(\.headerText) }
        let rowCount = tables.reduce(0) { $0 + $1.dataRows.count }
        return ScreenshotImportDiagnostics(
            ocrObservationCount: blocksByImage.reduce(0) { $0 + $1.count },
            detectedHeaders: headers,
            tableKind: tableKind,
            reconstructedRowCount: rowCount,
            completedTradeCandidates: completedCount,
            executionCandidates: executionCount,
            ignoredCancelledRows: ignoredCancelled,
            rejectedRows: rejectedRows,
            reviewWarnings: reviewWarnings
        )
    }
}
