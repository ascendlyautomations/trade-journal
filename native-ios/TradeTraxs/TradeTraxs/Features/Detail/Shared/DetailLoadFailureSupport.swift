import Foundation

nonisolated struct DetailLoadFailurePresentation: Equatable, Sendable {
    var title: String
    var message: String
    var isRetryable: Bool
}

nonisolated enum DetailLoadContentKind: Sendable {
    case post
    case trade
    case clip
    case achievement
}

/// Maps repository / transport failures into detail-screen copy.
nonisolated enum DetailLoadFailureSupport {
    static func presentation(
        for error: Error,
        content: DetailLoadContentKind,
        confirmedDeleted: Bool = false
    ) -> DetailLoadFailurePresentation {
        if confirmedDeleted {
            return DetailLoadFailurePresentation(
                title: deletedTitle(for: content),
                message: deletedMessage(for: content),
                isRetryable: false
            )
        }

        if let app = error as? AppError {
            return presentation(for: app, content: content)
        }
        if let network = error as? NetworkError {
            return presentation(for: network, content: content)
        }
        return DetailLoadFailurePresentation(
            title: loadFailedTitle(for: content),
            message: "Couldn't load. Try again.",
            isRetryable: true
        )
    }

    static func presentation(
        for error: AppError,
        content: DetailLoadContentKind
    ) -> DetailLoadFailurePresentation {
        switch error {
        case .transport(let network):
            return presentation(for: network, content: content)
        case .cancelled:
            return unavailable(for: content)
        case .unknown(let message):
            if isMissingContentMessage(message) || isPermissionOrUnavailableMessage(message) {
                return unavailable(for: content)
            }
            return DetailLoadFailurePresentation(
                title: loadFailedTitle(for: content),
                message: "Couldn't load. Try again.",
                isRetryable: true
            )
        case .authentication:
            return unavailable(for: content)
        case .notImplemented:
            return unsupported(for: content)
        }
    }

    static func presentation(
        for error: NetworkError,
        content: DetailLoadContentKind
    ) -> DetailLoadFailurePresentation {
        if error.isRetryable {
            return DetailLoadFailurePresentation(
                title: loadFailedTitle(for: content),
                message: "Couldn't load. Try again.",
                isRetryable: true
            )
        }
        switch error {
        case .unauthorized, .forbidden:
            return unavailable(for: content)
        default:
            return unavailable(for: content)
        }
    }

    static func unsupported(for content: DetailLoadContentKind) -> DetailLoadFailurePresentation {
        DetailLoadFailurePresentation(
            title: loadFailedTitle(for: content),
            message: "This content is unavailable.",
            isRetryable: false
        )
    }

    private static func unavailable(for content: DetailLoadContentKind) -> DetailLoadFailurePresentation {
        DetailLoadFailurePresentation(
            title: loadFailedTitle(for: content),
            message: "This content is unavailable.",
            isRetryable: false
        )
    }

    private static func isMissingContentMessage(_ message: String) -> Bool {
        let normalized = message
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "We couldn't find that."
    }

    private static func isPermissionOrUnavailableMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("private")
            || lowered.contains("permission")
            || lowered.contains("isn't available")
            || lowered.contains("isn’t available")
            || lowered.contains("can't interact")
            || lowered.contains("can’t interact")
    }

    private static func loadFailedTitle(for content: DetailLoadContentKind) -> String {
        switch content {
        case .post: return "Couldn't load post"
        case .trade: return "Couldn't load trade"
        case .clip: return "Couldn't load clip"
        case .achievement: return "Couldn't load achievement"
        }
    }

    private static func deletedTitle(for content: DetailLoadContentKind) -> String {
        switch content {
        case .post: return "Post unavailable"
        case .trade: return "Trade unavailable"
        case .clip: return "Clip unavailable"
        case .achievement: return "Achievement unavailable"
        }
    }

    private static func deletedMessage(for content: DetailLoadContentKind) -> String {
        switch content {
        case .post: return "This post was deleted."
        case .trade: return "This trade was deleted."
        case .clip: return "This clip was deleted."
        case .achievement: return "This achievement was deleted."
        }
    }
}
