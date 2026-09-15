import Foundation

/// User-facing generated prose (AI, templates, analytics copy) — not user-authored content.
///
/// Mirrors `lib/normalizeAIGeneratedText.ts` em-dash rules.
nonisolated enum GeneratedProseNormalizer {
    private static let emDash = "\u{2014}"

    static func normalize(_ text: String) -> String {
        guard text.contains(emDash) else { return text }

        var result = text
        result = result.replacingOccurrences(of: " — ", with: ", ")
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
