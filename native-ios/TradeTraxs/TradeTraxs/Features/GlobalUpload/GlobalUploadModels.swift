import Foundation

enum UploadJobKind: String, Sendable, CaseIterable {
    case reel
    case post
    case story
    case achievement
    case trade
    case avatar
    case room
    case messageMedia

    var defaultTitle: String {
        switch self {
        case .reel: return "Reel"
        case .post: return "Post"
        case .story: return "Story"
        case .achievement: return "Achievement"
        case .trade: return "Trade"
        case .avatar: return "Profile photo"
        case .room: return "Room image"
        case .messageMedia: return "Attachment"
        }
    }
}

enum UploadJobPhase: String, Sendable, Equatable {
    case preparing
    case encoding
    case uploading
    case publishing
    case completed
    case failed
}

struct UploadJob: Identifiable, Sendable, Equatable {
    var id: String
    var kind: UploadJobKind
    var title: String
    var phase: UploadJobPhase
    /// Determinate 0...1 when known; nil during indeterminate prep/encode without AV progress.
    var progress: Double?
    var errorMessage: String?
    var completedAt: Date?
    var showsSuccessFlash: Bool

    var displayLine: String {
        switch phase {
        case .preparing:
            return "Preparing \(title)…"
        case .encoding:
            if let progress {
                return "Encoding \(title)                       \(Self.percentString(progress))"
            }
            return "Encoding \(title)…"
        case .uploading:
            if let progress {
                return "Uploading \(title)                       \(Self.percentString(progress))"
            }
            return "Uploading \(title)…"
        case .publishing:
            return "Publishing \(title)…"
        case .completed:
            return "\(title) uploaded ✓"
        case .failed:
            return "\(title) upload failed"
        }
    }

    var aggregateWeight: Double {
        switch phase {
        case .completed: return 1
        case .failed: return progress ?? 0
        default: return progress ?? 0
        }
    }

    private static func percentString(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }
}

struct GlobalUploadBarPresentation: Equatable {
    var line: String
    var progress: Double?
    var showsRetry: Bool
    var activeCount: Int
}
