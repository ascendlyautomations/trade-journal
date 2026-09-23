import Foundation

#if DEBUG
enum EngagementRealtimeDebugLog {
    static func retainTargets(count: Int, kinds: String) {
        print("[EngagementRealtime] retainTargets count=\(count) kinds=\(kinds)")
    }

    static func releaseTargets(count: Int) {
        print("[EngagementRealtime] releaseTargets count=\(count)")
    }

    static func routeJoin(table: String, routeKey: String, idCount: Int) {
        print("[EngagementRealtime] routeJoin table=\(table) route=\(routeKey) ids=\(idCount)")
    }

    static func routeLeave(routeKey: String) {
        print("[EngagementRealtime] routeLeave route=\(routeKey)")
    }

    static func eventInsert(table: String, contentID: String, userID: String) {
        print(
            """
            [EngagementRealtime] eventInsert table=\(table) \
            contentID=\(short(contentID)) userID=\(short(userID))
            """
        )
    }

    static func eventDelete(table: String, contentID: String, userID: String) {
        print(
            """
            [EngagementRealtime] eventDelete table=\(table) \
            contentID=\(short(contentID)) userID=\(short(userID))
            """
        )
    }

    static func viewerEcho(table: String, contentID: String, kind: String) {
        print(
            """
            [EngagementRealtime] viewerEcho table=\(table) \
            contentID=\(short(contentID)) kind=\(kind)
            """
        )
    }

    static func remotePatch(
        targetKind: String,
        targetID: String,
        likeCount: Int,
        isLiked: Bool
    ) {
        print(
            """
            [EngagementRealtime] remotePatch kind=\(targetKind) \
            id=\(short(targetID)) likeCount=\(likeCount) isLiked=\(isLiked)
            """
        )
    }

    static func duplicateIgnored(table: String, rowID: String) {
        print("[EngagementRealtime] duplicateIgnored table=\(table) rowID=\(short(rowID))")
    }

    static func staleIgnored(reason: String) {
        print("[EngagementRealtime] staleIgnored reason=\(reason)")
    }

    static func writeThrough(targetKind: String, targetID: String) {
        print(
            """
            [EngagementRealtime] writeThrough kind=\(targetKind) id=\(short(targetID))
            """
        )
    }

    static func sessionClear(reason: String) {
        print("[EngagementRealtime] sessionClear reason=\(reason)")
    }

    private static func short(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed }
        return String(trimmed.prefix(8)) + "…"
    }
}
#endif
