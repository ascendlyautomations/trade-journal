import Foundation

/// Matches auth-trigger placeholder names that may be replaced after OAuth first login.
nonisolated enum ProfileDisplayNamePolicy {
    private static let placeholderNames: Set<String> = [
        "new user",
    ]

    static func isPlaceholder(_ name: String?) -> Bool {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return true
        }
        return placeholderNames.contains(trimmed.lowercased())
    }

    static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
