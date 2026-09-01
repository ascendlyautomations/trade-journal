import Foundation
import OSLog

#if DEBUG
nonisolated enum ExploreHydrationDiagnostics {
    static func logProfiles(requested: Int, resolved: Int, withAvatar: Int) {
        AppLog.networking.debug(
            """
            explore.hydration profiles requested=\(requested, privacy: .public) \
            resolved=\(resolved, privacy: .public) \
            withAvatar=\(withAvatar, privacy: .public)
            """
        )
    }

    static func logRooms(decoded: Int, withImage: Int, sourceCounts: [String: Int]) {
        let sources = sourceCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        AppLog.networking.debug(
            """
            explore.hydration rooms decoded=\(decoded, privacy: .public) \
            withImage=\(withImage, privacy: .public) \
            imageSourceKind \(sources, privacy: .public)
            """
        )
    }
}
#endif
