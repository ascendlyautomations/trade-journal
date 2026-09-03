import CoreGraphics
import Foundation

/// Broker screenshot OCR fixtures derived from real Vision output (no image assets required).
nonisolated enum BrokerScreenshotFixtures {
    /// Fixture A — order/execution history with FILLED + CANCELLED rows.
    static let executionOrderHistory: [[OCRTextBlock]] = [
        brokerTableBlocks(
            rows: [
                ["03/09/2026 12:58:04.27 AM", "XCME_CO MGC (Z26)", "BUY", "MARKET", "FILLED", "Flatten Trigger", "4481.50", "3.00", "0.00", "3.00"],
                ["03/09/2026 12:57:31.10 AM", "XCME_CO MGC (Z26)", "BUY", "LIMIT", "CANCELLED", "OCO Pull", "-", "0.00", "0.00", "0.00"],
                ["03/09/2026 12:49:31.24 AM", "XCME_CO MGC (Z26)", "SELL", "MARKET", "FILLED", "-", "4481.80", "3.00", "0.00", "3.00"],
                ["03/09/2026 12:57:42.33 AM", "XCME_CO MGC (Z26)", "BUY", "MARKET", "FILLED", "Stop Trigger", "4481.30", "2.00", "0.00", "2.00"],
                ["03/09/2026 12:49:23.82 AM", "XCME_CO MGC (Z26)", "SELL", "LIMIT", "FILLED", "-", "4482.00", "2.00", "0.00", "2.00"],
                ["03/09/2026 12:47:36.33 AM", "XCME_Eq MNQ (U26)", "SELL", "LIMIT", "CANCELLED", "OCO Pull", "-", "0.00", "0.00", "0.00"],
                ["03/09/2026 12:47:26.02 AM", "XCME_Eq MNQ (U26)", "BUY", "MARKET", "FILLED", "-", "29226.75", "3.00", "0.00", "3.00"],
            ],
            imageIndex: 0
        ),
    ]

    /// Fixture B — completed trade history with Trade Day / Open-Close prices / PnL.
    static let completedTradeHistory: [[OCRTextBlock]] = [
        brokerTableBlocks(
            rows: [
                ["Trade Day", "Symbol", "Volume", "Open Time", "Close Time", "Open Price", "Close Price", "Fees", "PnL", "Position"],
                ["23-08-2026", "MNQ", "1", "24-08-2026", "24-08-2026", "$29,196.25", "$29,172.50", "$1.32", "-$47.50", "B"],
                ["23-08-2026", "MNQ", "2", "24-08-2026", "24-08-2026", "$29,196.25", "$29,172.50", "$2.64", "-$95.00", "B"],
                ["23-08-2026", "MNQ", "1", "24-08-2026", "24-08-2026", "$29,170.75", "$29,168.75", "$3.96", "$12.00", "S"],
            ],
            imageIndex: 0
        ),
    ]

    /// Fixture C — completed trade table with SIDE / OPEN SIDE / CLOSE SIDE.
    static let completedTradeTable: [[OCRTextBlock]] = [
        brokerTableBlocks(
            rows: [
                ["SYMBOL", "SIDE", "VOLUME", "TRADE ID", "OPEN SIDE", "CLOSE SIDE", "OPEN PRICE", "CLOSE PRICE", "PNL", "FEES AND COMMISSIONS", "OPEN TIME", "CLOSE TIME"],
                ["XCME_CO MGC (Z26)", "SHORT", "2.00", "9fcf95dadaf535f", "SELL", "BUY", "$4,481.80", "$4,481.50", "+$6.00", "$3.64", "03/09/2026 12:49:31.24 AM", "03/09/2026 12:58:04.27 AM"],
                ["XCME_Eq MNQ (U26)", "LONG", "3.00", "6f48868df80c5c7a", "BUY", "SELL", "$29,233.75", "$29,217.75", "-$46.00", "$3.96", "03/09/2026 12:47:28.02 AM", "03/09/2026 12:48:37.30 AM"],
            ],
            imageIndex: 0
        ),
    ]

    private static func brokerTableBlocks(rows: [[String]], imageIndex: Int) -> [OCRTextBlock] {
        var blocks: [OCRTextBlock] = []
        var blockIndex = 0
        let rowHeight: CGFloat = 0.075
        let topY: CGFloat = 0.92
        let columnCount = rows.map(\.count).max() ?? 1
        let cellWidth: CGFloat = 0.92 / CGFloat(columnCount)

        for (rowIndex, row) in rows.enumerated() {
            let y = topY - CGFloat(rowIndex) * rowHeight
            for (cellIndex, text) in row.enumerated() {
                let x = 0.04 + CGFloat(cellIndex) * cellWidth
                blocks.append(
                    OCRTextBlock(
                        id: "broker-\(imageIndex)-\(blockIndex)",
                        text: text,
                        boundingBox: CGRect(
                            x: x,
                            y: y - rowHeight * 0.45,
                            width: cellWidth * 0.88,
                            height: rowHeight * 0.75
                        ),
                        confidence: 0.97
                    )
                )
                blockIndex += 1
            }
        }
        return blocks
    }
}
