import CoreGraphics
import Foundation

/// Groups OCR blocks into rows and assigns cells to header-defined columns using geometry.
nonisolated enum ScreenshotTradeTableReconstructor {
    private static let rowYTolerance: CGFloat = 0.022
    private static let cellXGap: CGFloat = 0.028

    static func reconstruct(
        blocksByImage: [[OCRTextBlock]]
    ) -> [ScreenshotTableRow] {
        blocksByImage.enumerated().flatMap { index, blocks in
            reconstructLegacyRows(blocks: blocks, sourceImageIndex: index)
        }
    }

    static func reconstructStructured(
        blocksByImage: [[OCRTextBlock]]
    ) -> [ScreenshotStructuredTable] {
        blocksByImage.enumerated().map { index, blocks in
            reconstructStructuredImage(blocks: blocks, sourceImageIndex: index)
        }
    }

    // MARK: - Structured reconstruction

    private static func reconstructStructuredImage(
        blocks: [OCRTextBlock],
        sourceImageIndex: Int
    ) -> ScreenshotStructuredTable {
        let legacyRows = reconstructLegacyRows(blocks: blocks, sourceImageIndex: sourceImageIndex)
        guard !blocks.isEmpty else {
            return ScreenshotStructuredTable(
                columns: [],
                headerRowIndex: nil,
                dataRows: [],
                legacyRows: [],
                sourceImageIndex: sourceImageIndex
            )
        }

        let rowClusters = clusterRows(blocks: blocks)
        let headerMatch = detectHeaderRow(in: rowClusters)
        let columns = buildColumns(from: headerMatch, rowClusters: rowClusters)
        let dataRowClusters = headerMatch.map { Array(rowClusters.dropFirst($0.index + 1)) } ?? rowClusters

        var dataRows: [ScreenshotStructuredRow] = []
        for (offset, cluster) in dataRowClusters.enumerated() {
            let texts = cluster.map(\.text)
            if isHeaderLike(texts) { continue }
            let values = assignValues(blocks: cluster, columns: columns)
            let yCenter = cluster.map(\.midY).reduce(0, +) / CGFloat(max(cluster.count, 1))
            dataRows.append(
                ScreenshotStructuredRow(
                    id: offset,
                    values: values,
                    allCellTexts: orderedCellTexts(from: cluster),
                    yCenter: yCenter,
                    sourceImageIndex: sourceImageIndex
                )
            )
        }

        return ScreenshotStructuredTable(
            columns: columns,
            headerRowIndex: headerMatch?.index,
            dataRows: dataRows,
            legacyRows: legacyRows,
            sourceImageIndex: sourceImageIndex
        )
    }

    private struct HeaderMatch {
        var index: Int
        var columns: [(key: ScreenshotColumnKey, block: OCRTextBlock, cellIndex: Int)]
    }

    private static func detectHeaderRow(in rowClusters: [[OCRTextBlock]]) -> HeaderMatch? {
        var best: HeaderMatch?
        var bestScore = 0

        for (index, cluster) in rowClusters.prefix(10).enumerated() {
            let ordered = cluster.sorted { $0.midX < $1.midX }
            var columns: [(ScreenshotColumnKey, OCRTextBlock, Int)] = []
            for (cellIndex, block) in ordered.enumerated() {
                if let key = ScreenshotColumnHeaderCatalog.classifyHeader(block.text) {
                    columns.append((key, block, cellIndex))
                }
            }
            let uniqueKeys = Set(columns.map(\.0))
            let score = uniqueKeys.count
            if score >= 2 && score > bestScore {
                bestScore = score
                best = HeaderMatch(index: index, columns: columns)
            }
        }
        return best
    }

    private static func buildColumns(
        from headerMatch: HeaderMatch?,
        rowClusters: [[OCRTextBlock]]
    ) -> [ScreenshotTableColumn] {
        guard let headerMatch else { return [] }

        let ordered = rowClusters[headerMatch.index].sorted { $0.midX < $1.midX }
        var headerEntries: [(key: ScreenshotColumnKey, xMin: CGFloat, xMax: CGFloat, text: String, index: Int)] = []
        for (cellIndex, block) in ordered.enumerated() {
            if let key = ScreenshotColumnHeaderCatalog.classifyHeader(block.text) {
                let inset = block.boundingBox.width * 0.15
                headerEntries.append((
                    key,
                    block.boundingBox.minX + inset,
                    block.boundingBox.maxX - inset,
                    block.text,
                    cellIndex
                ))
            }
        }
        guard !headerEntries.isEmpty else { return [] }

        var columns: [ScreenshotTableColumn] = []
        for entry in headerEntries {
            columns.append(
                ScreenshotTableColumn(
                    key: entry.key,
                    headerText: entry.text,
                    xMin: entry.xMin,
                    xMax: entry.xMax,
                    columnIndex: entry.index
                )
            )
        }
        return columns
    }

    private static func assignValues(
        blocks: [OCRTextBlock],
        columns: [ScreenshotTableColumn]
    ) -> [ScreenshotColumnKey: String] {
        guard !columns.isEmpty else {
            return assignValuesHeuristic(blocks: blocks)
        }

        var values: [ScreenshotColumnKey: String] = [:]
        for block in blocks {
            guard let column = nearestColumn(for: block.midX, columns: columns) else { continue }
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let existing = values[column.key] {
                values[column.key] = existing + " " + text
            } else {
                values[column.key] = text
            }
        }
        return values
    }

    private static func nearestColumn(
        for x: CGFloat,
        columns: [ScreenshotTableColumn]
    ) -> ScreenshotTableColumn? {
        let containing = columns.filter { x >= $0.xMin && x <= $0.xMax }
        if containing.count == 1 { return containing[0] }
        if containing.count > 1 {
            return containing.min(by: { abs($0.xCenter - x) < abs($1.xCenter - x) })
        }
        return columns.min(by: { abs($0.xCenter - x) < abs($1.xCenter - x) })
    }

    private static func assignValuesHeuristic(
        blocks: [OCRTextBlock]
    ) -> [ScreenshotColumnKey: String] {
        let ordered = blocks.sorted { $0.midX < $1.midX }
        var values: [ScreenshotColumnKey: String] = [:]
        for block in ordered {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let key = inferColumnKey(for: text) {
                if values[key] == nil {
                    values[key] = text
                }
            }
        }
        return values
    }

    private static func inferColumnKey(for text: String) -> ScreenshotColumnKey? {
        if ScreenshotBrokerText.isTimestamp(text) { return .timestamp }
        if ScreenshotBrokerText.extractSymbol(from: text) != nil { return .symbol }
        if ScreenshotBrokerText.isBuySell(text) { return .side }
        if ScreenshotBrokerText.isOrderType(text) { return .orderType }
        if ScreenshotBrokerText.isExecutionStatus(text) { return .status }
        if ScreenshotBrokerText.isTriggerAction(text) { return .action }
        if CSVNumericParser.parse(text) != nil {
            let upper = text.uppercased()
            if upper.contains("$") || upper.contains(",") || (upper.contains(".") && upper.count >= 4) {
                return .price
            }
            return .filledQuantity
        }
        return nil
    }

    private static func orderedCellTexts(from blocks: [OCRTextBlock]) -> [String] {
        clusterCells(from: blocks.sorted { $0.midX < $1.midX })
    }

    // MARK: - Legacy row reconstruction

    private static func reconstructLegacyRows(
        blocks: [OCRTextBlock],
        sourceImageIndex: Int
    ) -> [ScreenshotTableRow] {
        guard !blocks.isEmpty else { return [] }
        let rowClusters = clusterRows(blocks: blocks)
        return rowClusters.enumerated().compactMap { rowID, cluster in
            let ordered = cluster.sorted { $0.midX < $1.midX }
            let cells = clusterCells(from: ordered)
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !trimmed.isEmpty else { return nil }
            let yCenter = cluster.map(\.midY).reduce(0, +) / CGFloat(cluster.count)
            return ScreenshotTableRow(
                id: rowID,
                cells: trimmed,
                yCenter: yCenter,
                sourceImageIndex: sourceImageIndex
            )
        }
    }

    private static func clusterRows(blocks: [OCRTextBlock]) -> [[OCRTextBlock]] {
        let sorted = blocks.sorted {
            if abs($0.midY - $1.midY) > rowYTolerance { return $0.midY > $1.midY }
            return $0.midX < $1.midX
        }

        var rowClusters: [[OCRTextBlock]] = []
        for block in sorted {
            if let index = rowClusters.firstIndex(where: { cluster in
                guard let first = cluster.first else { return false }
                return abs(first.midY - block.midY) <= rowYTolerance
            }) {
                rowClusters[index].append(block)
            } else {
                rowClusters.append([block])
            }
        }
        return rowClusters
    }

    private static func clusterCells(from blocks: [OCRTextBlock]) -> [String] {
        guard !blocks.isEmpty else { return [] }
        var cells: [String] = []
        var current = blocks[0].text
        var previousX = blocks[0].midX

        for block in blocks.dropFirst() {
            if block.midX - previousX > cellXGap {
                cells.append(current)
                current = block.text
            } else {
                current += " " + block.text
            }
            previousX = block.midX
        }
        cells.append(current)
        return cells
    }

    private static func isHeaderLike(_ cells: [String]) -> Bool {
        let joined = cells.joined(separator: " ").lowercased()
        let hits = [
            "symbol", "ticker", "direction", "entry", "exit", "p&l", "pnl", "qty", "contracts",
            "volume", "open price", "close price", "account id", "username", "trade day",
        ].filter { joined.contains($0) }.count
        return hits >= 2
    }
}
