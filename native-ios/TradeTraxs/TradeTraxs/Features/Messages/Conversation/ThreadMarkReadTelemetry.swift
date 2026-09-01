import Foundation
import os

#if DEBUG
nonisolated enum ThreadMarkReadTelemetry {
    static func log(
        owner: String,
        intent: String,
        applied: Bool,
        conversationID: ConversationID
    ) {
        let prefix = String(conversationID.rawValue.prefix(8))
        AppLog.realtime.debug(
            "thread.markRead owner=\(owner, privacy: .public) intent=\(intent, privacy: .public) applied=\(applied, privacy: .public) convo=\(prefix, privacy: .public)…"
        )
    }
}
#else
nonisolated enum ThreadMarkReadTelemetry {
    static func log(owner: String, intent: String, applied: Bool, conversationID: ConversationID) {}
}
#endif
