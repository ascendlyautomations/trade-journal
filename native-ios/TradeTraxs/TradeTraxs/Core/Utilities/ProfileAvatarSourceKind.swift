import Foundation
import OSLog

/// Classifies how a profile avatar identifier should be resolved — never log the raw value.
nonisolated enum ProfileAvatarSourceKind: String, Sendable, CaseIterable {
    case fullURL
    case storagePath
    case mediaID
    case missing

    static func classify(_ raw: String?) -> ProfileAvatarSourceKind {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return .missing
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return .fullURL
        }
        if trimmed.contains("/") {
            return .storagePath
        }
        return .mediaID
    }

    static func classify(reference: MediaReference?) -> ProfileAvatarSourceKind {
        classify(reference?.id)
    }

    #if DEBUG
    static func summary(for profiles: some Sequence<Profile>) -> String {
        var counts = Dictionary(uniqueKeysWithValues: allCases.map { ($0, 0) })
        for profile in profiles {
            let kind = classify(reference: profile.avatar)
            counts[kind, default: 0] += 1
        }
        return allCases.map { "\($0.rawValue)=\(counts[$0, default: 0])" }.joined(separator: " ")
    }

    static func logLeaderboardStage(_ stage: String, profiles: some Sequence<Profile>) {
        AppLog.networking.debug("leaderboard.avatar \(stage): \(summary(for: profiles))")
    }
    #endif
}
