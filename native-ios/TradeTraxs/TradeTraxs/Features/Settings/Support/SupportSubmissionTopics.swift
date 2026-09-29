import Foundation

/// Support contact topics shown in Settings → Support (maps to ``support_tickets.category``).
enum SupportContactTopic: String, CaseIterable, Identifiable, Sendable {
    case account
    case brokerIntegration = "broker_integration"
    case bugTechnical = "bug"
    case billing
    case other = "general"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .account: return "Account"
        case .brokerIntegration: return "Broker Integration"
        case .bugTechnical: return "Bug / Technical Issue"
        case .billing: return "Billing"
        case .other: return "Other"
        }
    }

    var ticketCategory: SupportTicketCategory {
        switch self {
        case .account: return .account
        case .brokerIntegration: return .broker_integration
        case .bugTechnical: return .bug
        case .billing: return .billing
        case .other: return .general
        }
    }

    /// Stored in ``support_tickets.subject`` (web requires a subject line).
    var ticketSubject: String { "\(label) support request" }
}

/// Product feedback types for Settings → Product Feedback (encoded in ``feedback_submissions.subject``).
nonisolated enum ProductFeedbackType: String, CaseIterable, Identifiable, Sendable, Codable {
    case featureRequest = "feature_request"
    case improvement
    case bug
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .featureRequest: return "Feature Request"
        case .improvement: return "Improvement"
        case .bug: return "Bug"
        case .other: return "Other"
        }
    }

    func composedSubject(optionalTitle: String) -> String {
        ProductFeedbackSubjectCodec.encode(type: self, optionalTitle: optionalTitle)
    }
}

/// Deterministic `feedback_submissions.subject` encoding shared by user submit + Admin display.
nonisolated enum ProductFeedbackSubjectCodec {
    private static let typeLabelsBySpecificity: [ProductFeedbackType] = [
        .featureRequest,
        .improvement,
        .bug,
        .other,
    ]

    static func encode(type: ProductFeedbackType, optionalTitle: String) -> String {
        let title = optionalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return type.label
        }
        return "\(type.label): \(title)"
    }

    /// Parses native Product Feedback subjects; returns `(nil, subject)` for legacy/freeform web rows.
    static func parse(_ subject: String?) -> (type: ProductFeedbackType?, title: String?) {
        let raw = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return (nil, nil) }

        for type in typeLabelsBySpecificity {
            let label = type.label
            if raw == label {
                return (type, nil)
            }
            let prefix = "\(label): "
            if raw.hasPrefix(prefix) {
                let title = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return (type, title.isEmpty ? nil : title)
            }
        }
        return (nil, raw)
    }
}
