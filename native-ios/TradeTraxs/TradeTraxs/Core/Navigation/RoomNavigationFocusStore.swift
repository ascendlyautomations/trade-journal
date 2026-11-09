import Foundation

/// Per-room Trade Room navigation intents (push, universal link, in-app) with monotonic revisions.
///
/// Callers seed an intent before ``NavigationCoordinator/openExternal``. The room conversation screen
/// applies the intent once channels are ready, then acknowledges it. Manual channel selection cancels it.
@MainActor
final class RoomNavigationFocusStore {
    static let shared = RoomNavigationFocusStore()

    typealias Focus = NavigationIntent

    struct NavigationIntent: Equatable, Sendable {
        var roomID: RoomID
        var channelID: RoomChannelID?
        var channelName: String?
        var messageID: MessageID?
        var openLiveBroadcast: Bool = false
        /// Monotonic per canonical room; bumps on every ``seed``.
        var revision: UInt64 = 0
    }

    private var intentsByCanonicalRoom: [RoomID: NavigationIntent] = [:]
    private var revisionByCanonicalRoom: [RoomID: UInt64] = [:]
    private var canonicalRoomIDs: [RoomID: RoomID] = [:]

    private init() {}

    // MARK: - Intent seeding

    func seed(_ focus: Focus) {
        let canonical = canonicalRoomID(focus.roomID)
        let nextRevision = (revisionByCanonicalRoom[canonical] ?? 0) + 1
        var stamped = focus
        stamped.revision = nextRevision
        intentsByCanonicalRoom[canonical] = stamped
        revisionByCanonicalRoom[canonical] = nextRevision
        RoomNotificationNavigationTrace.event(
            .init(
                stage: "intent.seed",
                roomID: focus.roomID.rawValue,
                sectionID: focus.channelID?.rawValue,
                sectionName: focus.channelName,
                messageID: focus.messageID?.rawValue,
                detail: "revision=\(nextRevision)"
            )
        )
        NotificationCenter.default.post(
            name: .roomNavigationFocusDidSeed,
            object: focus.roomID
        )
    }

    func seed(
        roomID: RoomID,
        sectionID: String?,
        messageID: String?,
        sectionName: String? = nil,
        openLiveBroadcast: Bool = false
    ) {
        let channel = sectionID.flatMap { raw -> RoomChannelID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : RoomChannelID(trimmed)
        }
        let message = messageID.flatMap { raw -> MessageID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MessageID(trimmed)
        }
        let name = sectionName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        seed(
            NavigationIntent(
                roomID: roomID,
                channelID: channel,
                channelName: name,
                messageID: message,
                openLiveBroadcast: openLiveBroadcast
            )
        )
    }

  func intentRevision(
        for roomID: RoomID,
        resolvedRoomID: RoomID? = nil
    ) -> UInt64 {
        let canonical = canonicalRoomID(forRoute: roomID, resolved: resolvedRoomID)
        return revisionByCanonicalRoom[canonical] ?? 0
    }

    /// Unapplied navigation intent for this room, if any.
    func pendingIntent(
        for roomID: RoomID,
        resolvedRoomID: RoomID? = nil
    ) -> NavigationIntent? {
        let canonical = canonicalRoomID(forRoute: roomID, resolved: resolvedRoomID)
        guard let intent = intentsByCanonicalRoom[canonical] else { return nil }
        guard sameRoom(intent.roomID, roomID)
            || resolvedRoomID.map({ sameRoom(intent.roomID, $0) }) == true
        else { return nil }
        return intent
    }

    /// Active channel intent waiting to be applied (has a channel target).
    func hasActiveChannelIntent(
        for roomID: RoomID,
        resolvedRoomID: RoomID? = nil
    ) -> Bool {
        guard let intent = pendingIntent(for: roomID, resolvedRoomID: resolvedRoomID) else {
            return false
        }
        if intent.channelID != nil { return true }
        let name = intent.channelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty
    }

    /// Removes the intent after the VM successfully applied the requested channel.
    func acknowledgeIntent(
        for roomID: RoomID,
        revision: UInt64,
        resolvedRoomID: RoomID? = nil
    ) {
        let canonical = canonicalRoomID(forRoute: roomID, resolved: resolvedRoomID)
        guard let intent = intentsByCanonicalRoom[canonical], intent.revision == revision else {
            return
        }
        intentsByCanonicalRoom.removeValue(forKey: canonical)
        RoomNotificationNavigationTrace.event(
            .init(
                stage: "intent.ack",
                roomID: roomID.rawValue,
                sectionID: intent.channelID?.rawValue,
                sectionName: intent.channelName,
                messageID: intent.messageID?.rawValue,
                detail: "revision=\(revision)"
            )
        )
    }

    /// Manual sub-room selection or explicit cancel — drops pending intent for this room.
    func cancelIntent(for roomID: RoomID, resolvedRoomID: RoomID? = nil) {
        let canonical = canonicalRoomID(forRoute: roomID, resolved: resolvedRoomID)
        guard intentsByCanonicalRoom[canonical] != nil else { return }
        intentsByCanonicalRoom.removeValue(forKey: canonical)
        RoomNotificationNavigationTrace.event(
            .init(
                stage: "intent.cancel",
                roomID: roomID.rawValue,
                detail: "manualOrSuperseded"
            )
        )
    }

    // MARK: - Legacy aliases (tests / gradual migration)

    func pendingFocus(for roomID: RoomID) -> Focus? {
        pendingIntent(for: roomID)
    }

    func discardPending(for roomID: RoomID) {
        cancelIntent(for: roomID)
    }

    /// Tests only — production defers acknowledgement to ``RoomConversationViewModel/applyNavigationIntentIfNeeded()``.
    @available(*, deprecated, message: "Prefer pendingIntent + VM acknowledgeIntent in app code")
    func consume(for roomID: RoomID, resolvedRoomID: RoomID? = nil) -> Focus? {
        guard let intent = pendingIntent(for: roomID, resolvedRoomID: resolvedRoomID) else {
            return nil
        }
        acknowledgeIntent(for: roomID, revision: intent.revision, resolvedRoomID: resolvedRoomID)
        return intent
    }

    // MARK: - Room aliases

    func registerRoomAlias(_ ids: [RoomID]) {
        let cleaned = Array(Set(ids.compactMap(Self.normalized))).sorted { $0.rawValue < $1.rawValue }
        guard cleaned.count > 1 else { return }

        var group = Set(cleaned)
        for id in cleaned {
            var current = id
            var hops = 0
            while let next = canonicalRoomIDs[current], next != current, hops < 8 {
                group.insert(next)
                current = next
                hops += 1
            }
        }

        let canonical = group.first { UUID(uuidString: $0.rawValue) != nil }
            ?? group.sorted { $0.rawValue < $1.rawValue }[0]
        for id in group {
            canonicalRoomIDs[id] = canonical
        }
        for (key, value) in canonicalRoomIDs where group.contains(value) {
            canonicalRoomIDs[key] = canonical
        }
    }

    func canonicalRoomID(_ id: RoomID) -> RoomID {
        var current = id
        var seen = Set<RoomID>()
        while let next = canonicalRoomIDs[current], next != current, seen.insert(current).inserted {
            current = next
        }
        return current
    }

    func sameRoom(_ lhs: RoomID, _ rhs: RoomID) -> Bool {
        lhs == rhs || canonicalRoomID(lhs) == canonicalRoomID(rhs)
    }

    func epochKeys(forRoom id: RoomID) -> [String] {
        let canonical = canonicalRoomID(id)
        var raws: Set<String> = [id.rawValue, canonical.rawValue]
        for (key, value) in canonicalRoomIDs where canonicalRoomID(key) == canonical || value == canonical {
            raws.insert(key.rawValue)
            raws.insert(canonicalRoomID(value).rawValue)
        }
        return raws.map { "room:\($0)" }
    }

    func clear() {
        intentsByCanonicalRoom.removeAll()
        revisionByCanonicalRoom.removeAll()
        canonicalRoomIDs.removeAll()
    }

    private func canonicalRoomID(forRoute route: RoomID, resolved: RoomID?) -> RoomID {
        if let resolved {
            return canonicalRoomID(resolved)
        }
        return canonicalRoomID(route)
    }

    private static func normalized(_ id: RoomID) -> RoomID? {
        let trimmed = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return RoomID(trimmed)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Notification.Name {
    /// Posted when ``RoomNavigationFocusStore`` receives a new navigation intent revision.
    static let roomNavigationFocusDidSeed = Notification.Name("roomNavigationFocusDidSeed")
}
