import SwiftUI

/// Profile bio line limit shared by onboarding and Settings.
nonisolated enum ProfileBioPolicy {
    static let maximumLines = 3

    enum EditDecision: Equatable {
        case accept
        case reject
        case apply(String)
    }

    static func lineCount(_ value: String) -> Int {
        normalizeLineEndings(value).split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// Input-level gate — reject a 4th line from Return; paste still applies ``constrained(_:)``.
    static func editDecision(
        current: String,
        range: NSRange,
        replacement: String
    ) -> EditDecision {
        let nsCurrent = current as NSString
        guard range.location <= nsCurrent.length,
              range.location + range.length <= nsCurrent.length
        else {
            return .reject
        }
        let proposed = nsCurrent.replacingCharacters(in: range, with: replacement) as String
        if lineCount(proposed) <= maximumLines {
            return .accept
        }
        let capped = constrained(proposed)
        if capped == current {
            return .reject
        }
        return .apply(capped)
    }

    /// Keeps the first ``maximumLines`` lines. Extra newlines and pasted lines are dropped.
    static func constrained(_ value: String) -> String {
        let normalized = normalizeLineEndings(value)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maximumLines else { return normalized }
        return lines.prefix(maximumLines).joined(separator: "\n")
    }

    /// Line-capped bio ready to save. Empty input stays empty/nil, matching existing trim behavior.
    static func persisted(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = constrained(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func binding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                let next = constrained(newValue)
                guard source.wrappedValue != next else { return }
                source.wrappedValue = next
            }
        )
    }

    private static func normalizeLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}
