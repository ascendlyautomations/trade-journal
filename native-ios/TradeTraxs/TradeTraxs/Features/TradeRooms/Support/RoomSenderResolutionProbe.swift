import Foundation

#if DEBUG
enum RoomSenderResolutionProbe {
    private static var loggedKeys: Set<String> = []

    static func logResolved(
        senderID: ProfileID,
        source: String,
        username: String,
        hasAvatar: Bool
    ) {
        let key = "ok:\(senderID.rawValue)"
        guard loggedKeys.insert(key).inserted else { return }
        print(
            "[RoomSender] senderID=\(senderID.rawValue) source=\(source) resolved=true username=\(username) avatar=\(hasAvatar)"
        )
    }

    static func logUnresolved(senderID: ProfileID, reason: String) {
        let key = "fail:\(senderID.rawValue)"
        guard loggedKeys.insert(key).inserted else { return }
        print(
            "[RoomSender] senderID=\(senderID.rawValue) resolved=false reason=\(reason)"
        )
    }

    static func resetForTesting() {
        loggedKeys = []
    }
}
#else
enum RoomSenderResolutionProbe {
    static func logResolved(senderID: ProfileID, source: String, username: String, hasAvatar: Bool) {}
    static func logUnresolved(senderID: ProfileID, reason: String) {}
    static func resetForTesting() {}
}
#endif
