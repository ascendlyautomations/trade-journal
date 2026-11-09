import Foundation

nonisolated enum ScorecardReliabilitySupport {
    static func resolve(sampleSize: Int) -> ScorecardReliability {
        if sampleSize < 3 { return .insufficient }
        if sampleSize <= 7 { return .earlySignal }
        if sampleSize <= 19 { return .developing }
        return .strong
    }

    static func clampScore(_ value: Double) -> Int {
        Int(max(0, min(100, value.rounded())))
    }

    static func formatPercent(_ value: Double, digits: Int = 0) -> String {
        let pct = value * 100
        if digits == 0 {
            return String(format: "%.0f%%", pct)
        }
        return String(format: "%.\(digits)f%%", pct)
    }

    static func minReliability(_ a: ScorecardReliability, _ b: ScorecardReliability) -> ScorecardReliability {
        let order: [ScorecardReliability] = [.insufficient, .earlySignal, .developing, .strong]
        let ai = order.firstIndex(of: a) ?? 0
        let bi = order.firstIndex(of: b) ?? 0
        return ai < bi ? a : b
    }
}
