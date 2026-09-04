import Foundation
import OSLog

#if DEBUG
nonisolated enum ExploreHydrationDiagnostics {
    struct TraderAvatarTrace: Sendable {
        var profileID: ProfileID
        var bootstrapHasAvatar: Bool
        var batchRequired: Bool
        var batchHasAvatar: Bool?
        var cachePreservedAvatar: Bool
        var finalHasAvatar: Bool
    }

    static func logProfiles(requested: Int, resolved: Int, withAvatar: Int) {
        AppLog.networking.debug(
            """
            explore.hydration profiles requested=\(requested, privacy: .public) \
            resolved=\(resolved, privacy: .public) \
            withAvatar=\(withAvatar, privacy: .public)
            """
        )
    }

    static func logTraderAvatars(_ traces: [TraderAvatarTrace]) {
        guard !traces.isEmpty else { return }
        let batchRequired = traces.filter(\.batchRequired).count
        let batchResolved = traces.filter { $0.batchHasAvatar == true }.count
        let cachePreserved = traces.filter(\.cachePreservedAvatar).count
        let finalAvatars = traces.filter(\.finalHasAvatar).count
        AppLog.networking.debug(
            """
            explore.hydration.traders count=\(traces.count, privacy: .public) \
            bootstrapAvatar=\(traces.filter(\.bootstrapHasAvatar).count, privacy: .public) \
            batchRequired=\(batchRequired, privacy: .public) \
            batchResolved=\(batchResolved, privacy: .public) \
            cachePreserved=\(cachePreserved, privacy: .public) \
            finalAvatar=\(finalAvatars, privacy: .public)
            """
        )
        for trace in traces.prefix(8) {
            let suffix = String(trace.profileID.rawValue.suffix(6))
            AppLog.networking.debug(
                """
                explore.hydration.trader id=…\(suffix, privacy: .public) \
                bootstrap=\(trace.bootstrapHasAvatar, privacy: .public) \
                batchRequired=\(trace.batchRequired, privacy: .public) \
                batch=\(trace.batchHasAvatar.map { $0 ? "yes" : "no" } ?? "skip", privacy: .public) \
                cachePreserved=\(trace.cachePreservedAvatar, privacy: .public) \
                final=\(trace.finalHasAvatar, privacy: .public)
                """
            )
        }
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
#else
nonisolated enum ExploreHydrationDiagnostics {
    struct TraderAvatarTrace: Sendable {
        var profileID: ProfileID
        var bootstrapHasAvatar: Bool
        var batchRequired: Bool
        var batchHasAvatar: Bool?
        var cachePreservedAvatar: Bool
        var finalHasAvatar: Bool
    }

    static func logProfiles(requested: Int, resolved: Int, withAvatar: Int) {}
    static func logTraderAvatars(_ traces: [TraderAvatarTrace]) {}
    static func logRooms(decoded: Int, withImage: Int, sourceCounts: [String: Int]) {}
}
#endif
