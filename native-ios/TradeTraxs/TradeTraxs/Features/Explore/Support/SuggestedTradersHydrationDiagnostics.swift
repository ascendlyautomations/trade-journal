import Foundation
import OSLog

nonisolated enum SuggestedTradersHydrationDiagnostics {
    enum Source: String {
        case initial
        case refresh
        case pagination
    }

    #if DEBUG
    static func log(
        source: Source,
        rows: Int,
        profilesResolved: Int,
        avatarsAvailable: Int,
        avatarsUnknown: Int,
        requests: Int
    ) {
        AppLog.networking.debug(
            """
            suggestedTraders source=\(source.rawValue, privacy: .public) \
            rows=\(rows, privacy: .public) \
            profilesResolved=\(profilesResolved, privacy: .public) \
            avatarsAvailable=\(avatarsAvailable, privacy: .public) \
            avatarsUnknown=\(avatarsUnknown, privacy: .public) \
            requests=\(requests, privacy: .public)
            """
        )
    }
    #else
    static func log(
        source: Source,
        rows: Int,
        profilesResolved: Int,
        avatarsAvailable: Int,
        avatarsUnknown: Int,
        requests: Int
    ) {}
    #endif
}
