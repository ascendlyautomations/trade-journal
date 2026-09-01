import Foundation

/// Strips UUID-shaped placeholders from public profile identity fields.
nonisolated enum ProfileIdentitySanitizer {
    static let neutralFallbackName = "Trader"

    static func isUUIDLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 32 else { return false }
        let pattern = #"^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    static func sanitizedPublicField(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isUUIDLike(trimmed) else { return nil }
        return trimmed
    }

    /// Web `getTraderDisplay` parity — never surface a UUID as a visible handle.
    static func leaderboardDisplayName(name: String?, username: String?) -> String {
        if let name = sanitizedPublicField(name) { return name }
        if let username = sanitizedPublicField(username) { return username }
        return neutralFallbackName
    }

    static func leaderboardUsername(_ raw: String?) -> String? {
        sanitizedPublicField(raw)
    }
}
