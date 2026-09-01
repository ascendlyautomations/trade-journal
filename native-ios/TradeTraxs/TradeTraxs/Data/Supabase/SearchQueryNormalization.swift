import Foundation

/// Shared normalization for profile/trader search queries (Messages New Chat, Explore, etc.).
nonisolated enum SearchQueryNormalization {
    static func normalizePeopleQuery(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            trimmed = String(trimmed.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// PostgREST `ilike` patterns — strip characters that break `or=(...)` filters.
    static func escapeILikePattern(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
