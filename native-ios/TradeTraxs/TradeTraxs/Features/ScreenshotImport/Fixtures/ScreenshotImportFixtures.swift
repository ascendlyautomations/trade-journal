import CoreGraphics
import Foundation

/// Synthetic OCR layouts for screenshot import unit tests (no Vision required).
nonisolated enum ScreenshotImportFixtures {
    /// Generic trade-history table — two completed round-trip rows.
    static let tradeHistoryTable: [[OCRTextBlock]] = [
        tableBlocks(
            rows: [
                ["Symbol", "Side", "Qty", "Entry", "Exit", "P&L", "Date", "Entry Time", "Exit Time"],
                ["MNQ", "Long", "2", "24100.25", "24125.50", "$437.50", "2026-09-02", "10:32", "10:41"],
                ["ES", "Short", "1", "5012.00", "5008.25", "$187.50", "2026-09-02", "11:05", "11:12"],
            ],
            imageIndex: 0
        ),
    ]

    /// Second page overlapping one row from the first image.
    static let multiScreenshotOverlap: [[OCRTextBlock]] = [
        tradeHistoryTable[0],
        tableBlocks(
            rows: [
                ["Symbol", "Side", "Qty", "Entry", "Exit", "P&L", "Date", "Entry Time", "Exit Time"],
                ["MNQ", "Long", "2", "24100.25", "24125.50", "$437.50", "2026-09-02", "10:32", "10:41"],
                ["NQ", "Long", "1", "20100", "20125", "$500", "2026-09-02", "14:00", "14:18"],
            ],
            imageIndex: 1
        ),
    ]

    /// Individual execution lines — should require review, not import as completed trades confidently.
    static let executionLines: [[OCRTextBlock]] = [
        lineBlocks(
            lines: [
                "BUY 2 MNQ @ 24,100",
                "BUY 1 MNQ @ 24,105",
                "SELL 3 MNQ @ 24,125",
            ],
            imageIndex: 0
        ),
    ]

    /// Row missing P&L column values.
    static let missingPnL: [[OCRTextBlock]] = [
        tableBlocks(
            rows: [
                ["Symbol", "Side", "Qty", "Entry", "Exit", "Date"],
                ["MNQ", "Long", "3", "24100", "24125", "2026-09-02"],
            ],
            imageIndex: 0
        ),
    ]

    private static func tableBlocks(rows: [[String]], imageIndex: Int) -> [OCRTextBlock] {
        var blocks: [OCRTextBlock] = []
        var blockIndex = 0
        let rowHeight: CGFloat = 0.08
        let topY: CGFloat = 0.92

        for (rowIndex, row) in rows.enumerated() {
            let y = topY - CGFloat(rowIndex) * rowHeight
            let cellWidth: CGFloat = 0.9 / CGFloat(max(row.count, 1))
            for (cellIndex, text) in row.enumerated() {
                let x = 0.05 + CGFloat(cellIndex) * cellWidth
                blocks.append(
                    OCRTextBlock(
                        id: "fixture-\(imageIndex)-\(blockIndex)",
                        text: text,
                        boundingBox: CGRect(x: x, y: y - rowHeight * 0.5, width: cellWidth * 0.9, height: rowHeight * 0.8),
                        confidence: 0.99
                    )
                )
                blockIndex += 1
            }
        }
        return blocks
    }

    private static func lineBlocks(lines: [String], imageIndex: Int) -> [OCRTextBlock] {
        var blocks: [OCRTextBlock] = []
        let rowHeight: CGFloat = 0.1
        let topY: CGFloat = 0.9
        for (index, line) in lines.enumerated() {
            let y = topY - CGFloat(index) * rowHeight
            blocks.append(
                OCRTextBlock(
                    id: "line-\(imageIndex)-\(index)",
                    text: line,
                    boundingBox: CGRect(x: 0.05, y: y - rowHeight * 0.4, width: 0.9, height: rowHeight * 0.7),
                    confidence: 0.98
                )
            )
        }
        return blocks
    }
}
