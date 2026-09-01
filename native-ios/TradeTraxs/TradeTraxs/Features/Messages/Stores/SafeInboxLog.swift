import Foundation
import OSLog

nonisolated enum SafeInboxLog {
    static func hash(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        var hasher = Hasher()
        hasher.combine(value.lowercased())
        let digest = hasher.finalize()
        return String(format: "%08x", UInt(bitPattern: digest))
    }

#if DEBUG
    private static let logger = AppLog.realtime

    static func storeCreated(instance: String) {
        logger.debug("inbox.store.created instance=\(instance, privacy: .public)")
    }

    static func storeObserved(instance: String, source: String) {
        logger.debug(
            "inbox.store.observed instance=\(instance, privacy: .public) source=\(source, privacy: .public)"
        )
    }

    static func patchRequested(
        instance: String,
        source: String,
        conversationID: ConversationID,
        messageID: MessageID
    ) {
        logger.debug(
            """
            inbox.patch.requested instance=\(instance, privacy: .public) source=\(source, privacy: .public) \
            convo=\(hash(conversationID.rawValue), privacy: .public) message=\(hash(messageID.rawValue), privacy: .public)
            """
        )
    }

    static func patchApplied(
        instance: String,
        source: String,
        conversationID: ConversationID,
        messageID: MessageID,
        previewChanged: Bool,
        positionBefore: Int?,
        positionAfter: Int?,
        conversationCount: Int
    ) {
        logger.debug(
            """
            inbox.patch.applied instance=\(instance, privacy: .public) source=\(source, privacy: .public) \
            convo=\(hash(conversationID.rawValue), privacy: .public) message=\(hash(messageID.rawValue), privacy: .public) \
            previewChanged=\(previewChanged, privacy: .public) positionBefore=\(positionBefore ?? -1, privacy: .public) \
            positionAfter=\(positionAfter ?? -1, privacy: .public) conversationCount=\(conversationCount, privacy: .public)
            """
        )
    }

    static func activityCompare(
        instance: String,
        incomingAt: Date?,
        existingAt: Date?,
        incomingMessageID: MessageID?,
        existingMessageID: MessageID?,
        accepted: Bool
    ) {
        logger.debug(
            """
            inbox.activity.compare instance=\(instance, privacy: .public) \
            incomingAt=\(incomingAt?.timeIntervalSince1970 ?? -1, privacy: .public) \
            existingAt=\(existingAt?.timeIntervalSince1970 ?? -1, privacy: .public) \
            incomingMsg=\(hash(incomingMessageID?.rawValue), privacy: .public) \
            existingMsg=\(hash(existingMessageID?.rawValue), privacy: .public) \
            accepted=\(accepted, privacy: .public)
            """
        )
    }

    static func bootstrapApplied(
        instance: String,
        owner: String,
        conversationCount: Int,
        forceNetwork: Bool
    ) {
        logger.debug(
            """
            inbox.bootstrap.applied instance=\(instance, privacy: .public) owner=\(owner, privacy: .public) \
            conversationCount=\(conversationCount, privacy: .public) forceNetwork=\(forceNetwork, privacy: .public)
            """
        )
    }

    static func bootstrapStarted(
        owner: String,
        loadGeneration: UInt64,
        flightKey: String,
        forceNetwork: Bool,
        replacementActive: Bool
    ) {
        logger.debug(
            """
            messages.bootstrap.started owner=\(owner, privacy: .public) loadGeneration=\(loadGeneration, privacy: .public) \
            flightKey=\(flightKey, privacy: .public) forceNetwork=\(forceNetwork, privacy: .public) \
            replacementActive=\(replacementActive, privacy: .public)
            """
        )
    }

    static func bootstrapFailed(
        owner: String,
        loadGeneration: UInt64,
        authGeneration: UInt64,
        flightKey: String,
        diagnostic: MessagesBootstrapFailureDiagnostic,
        replacementActive: Bool,
        viewVisible: Bool
    ) {
        logger.debug(
            """
            messages.bootstrap.failed owner=\(owner, privacy: .public) loadGeneration=\(loadGeneration, privacy: .public) \
            authGeneration=\(authGeneration, privacy: .public) errorType=\(diagnostic.errorKind.rawValue, privacy: .public) \
            urlErrorCode=\(diagnostic.urlErrorCode.map(String.init) ?? "-", privacy: .public) \
            httpStatus=\(diagnostic.httpStatus.map(String.init) ?? "-", privacy: .public) \
            taskCancelled=\(diagnostic.taskCancelled, privacy: .public) \
            replacementActive=\(replacementActive, privacy: .public) viewVisible=\(viewVisible, privacy: .public) \
            flightKey=\(flightKey, privacy: .public) summary=\(diagnostic.summary, privacy: .public)
            """
        )
    }

    static func bootstrapCompleted(
        owner: String,
        loadGeneration: UInt64,
        conversationCount: Int,
        rpcRequestCount: Int
    ) {
        logger.debug(
            """
            messages.bootstrap.completed owner=\(owner, privacy: .public) loadGeneration=\(loadGeneration, privacy: .public) \
            conversationCount=\(conversationCount, privacy: .public) rpcRequestCount=\(rpcRequestCount, privacy: .public)
            """
        )
    }

    static func sendCompleted(
        conversationID: ConversationID,
        messageID: MessageID,
        bodyChars: Int,
        hasAttachment: Bool,
        status: Int = 201
    ) {
        logger.debug(
            """
            inbox.send.completed convo=\(hash(conversationID.rawValue), privacy: .public) \
            message=\(hash(messageID.rawValue), privacy: .public) bodyChars=\(bodyChars, privacy: .public) \
            hasAttachment=\(hasAttachment, privacy: .public) status=\(status, privacy: .public)
            """
        )
    }
#else
    static func storeCreated(instance: String) {}
    static func storeObserved(instance: String, source: String) {}
    static func patchRequested(instance: String, source: String, conversationID: ConversationID, messageID: MessageID) {}
    static func patchApplied(
        instance: String,
        source: String,
        conversationID: ConversationID,
        messageID: MessageID,
        previewChanged: Bool,
        positionBefore: Int?,
        positionAfter: Int?,
        conversationCount: Int
    ) {}
    static func activityCompare(
        instance: String,
        incomingAt: Date?,
        existingAt: Date?,
        incomingMessageID: MessageID?,
        existingMessageID: MessageID?,
        accepted: Bool
    ) {}
    static func bootstrapApplied(instance: String, owner: String, conversationCount: Int, forceNetwork: Bool) {}
    static func bootstrapStarted(owner: String, loadGeneration: UInt64, flightKey: String, forceNetwork: Bool, replacementActive: Bool) {}
    static func bootstrapFailed(owner: String, loadGeneration: UInt64, authGeneration: UInt64, flightKey: String, diagnostic: MessagesBootstrapFailureDiagnostic, replacementActive: Bool, viewVisible: Bool) {}
    static func bootstrapCompleted(owner: String, loadGeneration: UInt64, conversationCount: Int, rpcRequestCount: Int) {}
    static func sendCompleted(conversationID: ConversationID, messageID: MessageID, bodyChars: Int, hasAttachment: Bool, status: Int = 201) {}
#endif
}
