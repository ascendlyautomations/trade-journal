import Foundation

/// Fill-level dedup across multi-screenshot imports.
nonisolated enum ScreenshotFillDedup {
    static func dedupe(_ fills: [ParsedTradeFill]) -> (unique: [ParsedTradeFill], removedCount: Int) {
        var seenExact = Set<String>()
        var output: [ParsedTradeFill] = []
        var removed = 0

        for fill in fills {
            let exact = ImportFingerprint.forFill(fill)
            if seenExact.contains(exact) {
                removed += 1
                continue
            }
            seenExact.insert(exact)
            output.append(fill)
        }

        return (output, removed)
    }
}
