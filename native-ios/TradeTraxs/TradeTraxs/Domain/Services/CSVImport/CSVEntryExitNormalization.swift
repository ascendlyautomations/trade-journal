import Foundation

/// Web `normalizeCsvEntryExitTimestamps` — earliest entry, latest exit; optional price swap (Tradovate).
nonisolated enum CSVEntryExitNormalization {
    struct Result: Sendable {
        var entry: Date
        var exit: Date
        var entryPrice: Decimal?
        var exitPrice: Decimal?
        var durationSeconds: Int?
        var reordered: Bool
    }

    static func normalize(
        entry: Date,
        exit: Date,
        entryPrice: Decimal?,
        exitPrice: Decimal?,
        swapPricesWhenReordering: Bool
    ) -> Result {
        var nextEntry = entry
        var nextExit = exit
        var nextEntryPrice = entryPrice
        var nextExitPrice = exitPrice
        var reordered = false

        if exit < entry {
            nextEntry = exit
            nextExit = entry
            reordered = true
            if swapPricesWhenReordering {
                nextEntryPrice = exitPrice
                nextExitPrice = entryPrice
            }
        }

        var durationSeconds: Int?
        let span = nextExit.timeIntervalSince(nextEntry)
        if span > 0 {
            durationSeconds = Int(span.rounded())
        }

        return Result(
            entry: nextEntry,
            exit: nextExit,
            entryPrice: nextEntryPrice,
            exitPrice: nextExitPrice,
            durationSeconds: durationSeconds,
            reordered: reordered
        )
    }
}
