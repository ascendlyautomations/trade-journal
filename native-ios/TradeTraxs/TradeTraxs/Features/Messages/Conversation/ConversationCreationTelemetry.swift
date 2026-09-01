import Foundation
import OSLog

#if DEBUG
/// DEBUG-only creation-path telemetry — no PII, queries, or message bodies.
nonisolated enum ConversationCreationTelemetry {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "ConversationCreate")

    nonisolated(unsafe) private static var startedAt: Date?
    nonisolated(unsafe) private static var requestCount: Int = 0

    static func reset() {
        startedAt = nil
        requestCount = 0
    }

    static func recordRequest() {
        requestCount += 1
    }

    static func started(type: String, recipientCount: Int) {
        startedAt = Date()
        requestCount = 0
        logger.debug("conversation.create.started type=\(type, privacy: .public) recipients=\(recipientCount, privacy: .public)")
    }

    static func duplicateLookupCompleted() {
        logger.debug("conversation.create.duplicateLookup.completed")
    }

    static func blockValidationCompleted() {
        logger.debug("conversation.create.blockValidation.completed")
    }

    static func persisted(conversationID: ConversationID) {
        let hash = conversationID.rawValue.prefix(8)
        logger.debug("conversation.create.persisted id=\(hash, privacy: .public)")
    }

    static func participantsCompleted(count: Int) {
        logger.debug("conversation.create.participants.completed count=\(count, privacy: .public)")
    }

    static func cacheSeedCompleted() {
        logger.debug("conversation.create.cacheSeed.completed")
    }

    static func navigationCompleted() {
        guard let startedAt else {
            logger.debug("conversation.create.navigation.completed")
            return
        }
        let ms = Int(Date().timeIntervalSince(startedAt) * 1_000)
        logger.debug(
            """
            conversation.create.navigation.completed \
            firstUsefulRender ms=\(ms, privacy: .public) \
            requests=\(requestCount, privacy: .public)
            """
        )
        Self.startedAt = nil
    }
}
#else
nonisolated enum ConversationCreationTelemetry {
    static func reset() {}
    static func recordRequest() {}
    static func started(type: String, recipientCount: Int) {}
    static func duplicateLookupCompleted() {}
    static func blockValidationCompleted() {}
    static func persisted(conversationID: ConversationID) {}
    static func participantsCompleted(count: Int) {}
    static func cacheSeedCompleted() {}
    static func navigationCompleted() {}
}
#endif
