import SwiftUI

/// Generic async / network-adjacent UI states. Feature-agnostic.
enum FeedbackState: Equatable, Sendable {
    case idle
    case loading
    case syncing
    case empty(message: String)
    case offline(message: String)
    case failure(message: String, retryable: Bool)
    case success(message: String)

    var isBlocking: Bool {
        switch self {
        case .loading:
            return true
        default:
            return false
        }
    }
}

enum BannerTone: Sendable {
    case info
    case success
    case warning
    case error
    case offline

    var color: Color {
        color(in: ExperienceColor.palette)
    }

    func color(in palette: SemanticColorPalette) -> Color {
        switch self {
        case .info: return palette.info
        case .success: return palette.success
        case .warning: return palette.warning
        case .error: return palette.error
        case .offline: return palette.secondaryText
        }
    }

    var icon: AppIcon {
        switch self {
        case .info: return .info
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        case .offline: return .offline
        }
    }
}
