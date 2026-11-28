import Foundation

nonisolated struct PsychologyCoachStructuredSections: Hashable, Sendable {
    var biggestInsight: String?
    var performancePatterns: [String]
    var areasForImprovement: [String]
    var recommendedGuardrails: [String]
    var nextSessionFocus: String?

    var isStructured: Bool {
        biggestInsight != nil
            || !performancePatterns.isEmpty
            || !areasForImprovement.isEmpty
            || !recommendedGuardrails.isEmpty
            || nextSessionFocus != nil
    }
}

nonisolated enum PsychologyCoachResponseParser {
    static func parse(_ content: String) -> PsychologyCoachStructuredSections? {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var biggestInsight: String?
        var performance: [String] = []
        var improvements: [String] = []
        var guardrails: [String] = []
        var nextFocus: String?
        var current: SectionKey?

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let key = SectionKey.match(line) {
                current = key
                continue
            }
            guard let current, !line.isEmpty else { continue }
            switch current {
            case .biggestInsight:
                biggestInsight = append(biggestInsight, line)
            case .performancePatterns:
                performance.append(contentsOf: bulletLines(from: line))
            case .areasForImprovement:
                improvements.append(contentsOf: bulletLines(from: line))
            case .recommendedGuardrails:
                guardrails.append(contentsOf: bulletLines(from: line))
            case .nextSessionFocus:
                nextFocus = append(nextFocus, line)
            }
        }

        let sections = PsychologyCoachStructuredSections(
            biggestInsight: trim(biggestInsight),
            performancePatterns: Array(performance.prefix(6)),
            areasForImprovement: Array(improvements.prefix(6)),
            recommendedGuardrails: Array(guardrails.prefix(5)),
            nextSessionFocus: trim(nextFocus)
        )
        return sections.isStructured ? sections : nil
    }

    private enum SectionKey {
        case biggestInsight
        case performancePatterns
        case areasForImprovement
        case recommendedGuardrails
        case nextSessionFocus

        static func match(_ line: String) -> SectionKey? {
            let stripped = line
                .replacingOccurrences(of: #"^#{1,3}\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\*\*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\*\*:?$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch stripped {
            case "biggest psychological insight":
                return .biggestInsight
            case "performance patterns":
                return .performancePatterns
            case "areas for improvement":
                return .areasForImprovement
            case "recommended guardrails":
                return .recommendedGuardrails
            case "next session focus":
                return .nextSessionFocus
            default:
                return nil
            }
        }
    }

    private static func bulletLines(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
            let body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return body.isEmpty ? [] : [body]
        }
        if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            let body = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            return body.isEmpty ? [] : [body]
        }
        return [trimmed]
    }

    private static func append(_ existing: String?, _ line: String) -> String {
        guard let existing, !existing.isEmpty else { return line }
        return "\(existing) \(line)"
    }

    private static func trim(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}