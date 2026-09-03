import Foundation

/// Native port of web `mergeMessageLists` + `mergeRealtimeMessageIntoList`.
///
/// Every conversation thread mutation (DM + Trade Room) must go through
/// ``mergeMessages(existing:incoming:viewerID:)`` so each `MessageID` exists
/// at most once in memory.
nonisolated enum ConversationMessageMerge {
    private static let optimisticMatchWindow: TimeInterval = 15

    static func isOptimisticMessageID(_ id: MessageID) -> Bool {
        id.rawValue.hasPrefix("temp-")
    }

    /// Upsert `incoming` into `existing` by `MessageID`, replace matching `temp-*`
    /// optimistic rows (web `mergeRealtimeMessageIntoList`), then sort by `createdAt`.
    static func mergeMessages(
        existing: [Message],
        incoming: [Message],
        viewerID: ProfileID? = nil
    ) -> [Message] {
        var result = uniqueByID(existing)
        for message in incoming {
            result = mergeRealtimeMessageIntoList(
                prev: result,
                incoming: message,
                viewerID: viewerID
            )
        }
        result = stripResolvedOptimisticMessages(result, viewerID: viewerID)
        return sortByCreatedAt(uniqueByID(result))
    }

    /// Server first-page refresh — upsert incoming rows and drop in-window rows the server omitted
    /// (soft-deleted / filtered). Older paginated rows below the window are preserved.
    static func reconcileServerFirstPage(existing: [Message], incoming: [Message]) -> [Message] {
        guard !incoming.isEmpty else {
            return sortByCreatedAt(uniqueByID(existing))
        }
        let incomingIDs = Set(incoming.map(\.id))
        let windowStart = incoming.map(\.createdAt).min()!
        let windowEnd = incoming.map(\.createdAt).max()!
        let preserved = existing.filter { message in
            if incomingIDs.contains(message.id) { return true }
            if message.createdAt < windowStart { return true }
            if message.createdAt > windowEnd { return true }
            return false
        }
        return mergeMessageLists(existing: preserved, incoming: incoming)
    }

    /// Web `mergeMessageLists` — Map-by-id upsert without optimistic matching.
    static func mergeMessageLists(existing: [Message], incoming: [Message]) -> [Message] {
        var byID: [MessageID: Message] = [:]
        for message in existing {
            if let prev = byID[message.id] {
                byID[message.id] = upserting(prev, with: message)
            } else {
                byID[message.id] = message
            }
        }
        for message in incoming {
            if let prev = byID[message.id] {
                byID[message.id] = upserting(prev, with: message)
            } else {
                byID[message.id] = message
            }
        }
        return sortByCreatedAt(Array(byID.values))
    }

    /// Web `mergeRealtimeMessageIntoList` for a single server/optimistic row.
    static func mergeRealtimeMessageIntoList(
        prev: [Message],
        incoming: Message,
        viewerID: ProfileID? = nil
    ) -> [Message] {
        if let index = prev.firstIndex(where: { $0.id == incoming.id }) {
            var next = prev
            next[index] = upserting(prev[index], with: incoming)
            return next
        }

        if let tempIndex = prev.firstIndex(where: { candidate in
            matchesOptimistic(candidate, server: incoming, viewerID: viewerID)
        }) {
            var next = prev
            next[tempIndex] = upserting(prev[tempIndex], with: incoming)
            return next
        }

        return prev + [incoming]
    }

    /// Drop `temp-*` rows that already have a confirmed server equivalent in the list.
    static func stripResolvedOptimisticMessages(
        _ messages: [Message],
        viewerID: ProfileID?
    ) -> [Message] {
        let confirmed = messages.filter { !isOptimisticMessageID($0.id) }
        guard !confirmed.isEmpty else { return messages }
        return messages.filter { candidate in
            guard isOptimisticMessageID(candidate.id) else { return true }
            return !confirmed.contains { server in
                matchesOptimistic(candidate, server: server, viewerID: viewerID)
            }
        }
    }

    static func matchesOptimistic(
        _ optimistic: Message,
        server: Message,
        viewerID: ProfileID?
    ) -> Bool {
        guard isOptimisticMessageID(optimistic.id) else { return false }
        if let viewerID, optimistic.senderProfileID != viewerID { return false }
        if optimistic.senderProfileID != server.senderProfileID { return false }
        let incomingContent = contentKey(for: server)
        let sameContent = contentKey(for: optimistic) == incomingContent
        if !sameContent, !incomingContent.isEmpty { return false }
        return abs(server.createdAt.timeIntervalSince(optimistic.createdAt)) < optimisticMatchWindow
    }

    static func sortByCreatedAt(_ messages: [Message]) -> [Message] {
        MessageChronology.sortAscending(messages)
    }

    static func uniqueByID(_ messages: [Message]) -> [Message] {
        var byID: [MessageID: Message] = [:]
        for message in messages {
            if let prev = byID[message.id] {
                byID[message.id] = upserting(prev, with: message)
            } else {
                byID[message.id] = message
            }
        }
        // Preserve relative order of first occurrence, then caller sorts.
        var ordered: [Message] = []
        var seen = Set<MessageID>()
        for message in messages {
            guard !seen.contains(message.id) else { continue }
            seen.insert(message.id)
            if let merged = byID[message.id] {
                ordered.append(merged)
            }
        }
        return ordered
    }

    /// Prefer incoming fields while keeping richer local metadata (web `profiles` preserve).
    static func upserting(_ previous: Message, with incoming: Message) -> Message {
        var merged = incoming
        merged.id = incoming.id
        if (merged.body == nil || merged.body?.isEmpty == true),
           let body = previous.body,
           !body.isEmpty
        {
            merged.body = body
        }
        if merged.attachments.isEmpty, !previous.attachments.isEmpty {
            merged.attachments = previous.attachments
        }
        if merged.replyToMessageID == nil {
            merged.replyToMessageID = previous.replyToMessageID
        }
        // Keep local read if either side already marked read.
        merged.isReadByViewer = previous.isReadByViewer || incoming.isReadByViewer
        if merged.kind == .text, previous.kind != .text, incoming.attachments.isEmpty {
            merged.kind = previous.kind
        }
        return merged
    }

    /// Comparable content fingerprint for optimistic ↔ server matching.
    static func contentKey(for message: Message) -> String {
        if let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }
        if let tradeID = message.attachments.first?.tradeID {
            return "trade:\(tradeID.rawValue)"
        }
        if message.kind == .voice,
           let duration = message.attachments.first?.durationSeconds
        {
            return "voice:\(Int(duration * 1_000))"
        }
        if let mediaID = message.attachments.first?.media.id,
           !mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return mediaID
        }
        return ""
    }
}
