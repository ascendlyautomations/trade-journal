import Foundation

/// Frozen rank session for `rpc_v2_feed_bootstrap` pagination (rank + chrono scan cursors).
@MainActor
enum FeedRotatingSessionStore {
    struct Session: Sendable {
        var sessionID: String
        var rankFrozenAt: Date
        var scanCursor: String?
        var usesV2: Bool
    }

    private static var sessions: [String: Session] = [:]

    static func cacheKey(viewerID: ProfileID, scope: FeedScope, filter: FeedContentFilter) -> String {
        "\(viewerID.rawValue)|\(scope.rawValue)|\(filter.rpcValue)"
    }

    static func isRankCursor(_ cursor: String) -> Bool {
        let parts = cursor.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        let head = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        return head.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
    }

  /// Starts or resumes a rank session. Pass `forceNew: true` on pull-to-refresh so impressions + order reset.
    static func begin(
        viewerID: ProfileID,
        scope: FeedScope,
        filter: FeedContentFilter,
        forceNew: Bool = false
    ) -> Session {
        let key = cacheKey(viewerID: viewerID, scope: scope, filter: filter)
        if !forceNew, let existing = sessions[key], existing.usesV2 {
            return existing
        }
        let session = Session(
            sessionID: UUID().uuidString,
            rankFrozenAt: Date(),
            scanCursor: nil,
            usesV2: true
        )
        sessions[key] = session
        FeedRotatingRankProbe.rankSessionBegan(
            scope: scope.rawValue,
            filter: filter.rpcValue,
            sessionID: session.sessionID
        )
        return session
    }

    static func session(
        viewerID: ProfileID,
        scope: FeedScope,
        filter: FeedContentFilter
    ) -> Session? {
        sessions[cacheKey(viewerID: viewerID, scope: scope, filter: filter)]
    }

    static func setScanCursor(
        viewerID: ProfileID,
        scope: FeedScope,
        filter: FeedContentFilter,
        scanCursor: String?
    ) {
        let key = cacheKey(viewerID: viewerID, scope: scope, filter: filter)
        guard var existing = sessions[key] else { return }
        let trimmed = scanCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.scanCursor = (trimmed?.isEmpty == false) ? trimmed : nil
        sessions[key] = existing
    }

    static func markV1Fallback(
        viewerID: ProfileID,
        scope: FeedScope,
        filter: FeedContentFilter
    ) {
        sessions.removeValue(forKey: cacheKey(viewerID: viewerID, scope: scope, filter: filter))
    }

    static func reset(viewerID: ProfileID) {
        let prefix = viewerID.rawValue + "|"
        sessions = sessions.filter { !$0.key.hasPrefix(prefix) }
    }

    static func resetAll() {
        sessions = [:]
    }

    #if DEBUG
    static func resetAllForTesting() {
        resetAll()
    }
    #endif
}