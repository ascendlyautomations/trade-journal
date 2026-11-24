import Foundation

/// User-facing generated prose (AI, templates, dashboard insights), not user-authored content.
///
/// Mirrors `lib/normalizeAIGeneratedText.ts`. Strips legacy em dashes (U+2014) to commas.
/// Preserves missing-data en dashes (U+2013) and `– ·` score labels.
nonisolated enum GeneratedProseNormalizer {
    private static let emDash = "\u{2014}"
    private static let missingValueDash = "\u{2013}"

    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == missingValueDash { return text }
        if trimmed == emDash { return text }
        if trimmed.hasPrefix("\(missingValueDash) ·") || trimmed.hasPrefix("\(missingValueDash)·") { return text }
        if trimmed.hasPrefix("\(emDash) ·") || trimmed.hasPrefix("\(emDash)·") { return text }
        guard text.contains(emDash) else { return text }

        var result = text
        result = result.replacingOccurrences(of: " \(emDash) ", with: ", ")
        result = result.replacingOccurrences(of: "\(emDash) ", with: ", ")
        result = result.replacingOccurrences(of: " \(emDash)", with: ", ")

        if let regex = try? NSRegularExpression(pattern: "(\\S)\(emDash)(\\S)") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1, $2"
            )
        }

        result = result.replacingOccurrences(of: emDash, with: ", ")
        result = result.replacingOccurrences(of: #"\s+,"#, with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: #",{2,}"#, with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: #",\s{2,}"#, with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: ", ,", with: ", ")

        return result
    }
}