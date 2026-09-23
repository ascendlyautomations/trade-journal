import Foundation

#if DEBUG
nonisolated enum SocialEntityRealtimeDebugLog {
    static func entityInsert(table: String, id: String) {
        print("[SocialEntityRealtime] entityInsert table=\(table) id=\(short(id))")
    }

    static func entityUpdate(table: String, id: String) {
        print("[SocialEntityRealtime] entityUpdate table=\(table) id=\(short(id))")
    }

    static func entityDelete(table: String, id: String) {
        print("[SocialEntityRealtime] entityDelete table=\(table) id=\(short(id))")
    }

    static func ignoredOutOfScope(table: String, id: String, reason: String) {
        print("[SocialEntityRealtime] ignoredOutOfScope table=\(table) id=\(short(id)) reason=\(reason)")
    }

    static func ignoredBlocked(authorID: String) {
        print("[SocialEntityRealtime] ignoredBlocked author=\(short(authorID))")
    }

    static func visibilityRemove(table: String, id: String) {
        print("[SocialEntityRealtime] visibilityRemove table=\(table) id=\(short(id))")
    }

    static func summaryHydration(table: String, id: String) {
        print("[SocialEntityRealtime] summaryHydration table=\(table) id=\(short(id))")
    }

    static func summaryHydrationCoalesced(table: String, id: String) {
        print("[SocialEntityRealtime] summaryHydrationCoalesced table=\(table) id=\(short(id))")
    }

    static func feedPatch(id: String) {
        print("[SocialEntityRealtime] feedPatch id=\(short(id))")
    }

    static func profilePatch(profileID: String, id: String) {
        print("[SocialEntityRealtime] profilePatch profile=\(short(profileID)) id=\(short(id))")
    }

    static func persist(table: String, id: String) {
        print("[SocialEntityRealtime] persist table=\(table) id=\(short(id))")
    }

    static func duplicateIgnored(table: String, id: String) {
        print("[SocialEntityRealtime] duplicateIgnored table=\(table) id=\(short(id))")
    }

    static func routeJoin(table: String, routeKey: String) {
        print("[SocialEntityRealtime] routeJoin table=\(table) route=\(routeKey)")
    }

    static func routeLeave(routeKey: String) {
        print("[SocialEntityRealtime] routeLeave route=\(routeKey)")
    }

    static func sessionClear(reason: String) {
        print("[SocialEntityRealtime] sessionClear reason=\(reason)")
    }

    private static func short(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed }
        return String(trimmed.prefix(8)) + "…"
    }
}
#endif
