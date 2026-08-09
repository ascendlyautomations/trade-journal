import Foundation

/// Permanent Profile content sections. Each maps to a lazy container.
enum ProfileSection: String, CaseIterable, Identifiable, Sendable {
    case trades
    case posts
    case clips
    case stats
    case achievements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trades: return "Trades"
        case .posts: return "Posts"
        case .clips: return "Clips"
        case .stats: return "Stats"
        case .achievements: return "Achievements"
        }
    }

    /// Monochrome SF Symbol for the Instagram-style section picker.
    var systemImage: String {
        switch self {
        case .trades: return "chart.line.uptrend.xyaxis"
        case .posts: return "square.grid.2x2"
        case .clips: return "play.square"
        case .stats: return "chart.bar.xaxis"
        case .achievements: return "trophy"
        }
    }

    var emptyTitle: String {
        switch self {
        case .trades: return "No trades yet"
        case .posts: return "No posts yet"
        case .clips: return "No clips yet"
        case .stats: return "No stats yet"
        case .achievements: return "No achievements yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .trades: return "Your journaled trades will show up here."
        case .posts: return "Share a post to see it on your profile."
        case .clips: return "Clips you publish will appear in this tab."
        case .stats: return "Trade enough to unlock your performance summary."
        case .achievements: return "Keep journaling to earn achievements."
        }
    }

    var accessibilityHint: String {
        "Show \(title.lowercased()) on your profile"
    }
}
