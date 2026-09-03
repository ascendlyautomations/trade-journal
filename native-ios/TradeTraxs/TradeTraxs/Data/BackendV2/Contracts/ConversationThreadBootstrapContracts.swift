import Foundation

/// Wire contract for `rpc_v1_conversation_thread_bootstrap` (Phase G — personal/group thread).
nonisolated struct ConversationThreadBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var conversation: ConversationThreadConversationV1
        var membership: ConversationThreadMembershipV1
        var participants: [ConversationThreadParticipantV1]
        var notifications_enabled: PostgresFlexibleBool
        var block_status: ConversationThreadBlockStatusV1?
        var messages: [ConversationThreadMessageV1]
        var has_more_messages: PostgresFlexibleBool
        var next_message_cursor: String?
        var unread_count: PostgresFlexibleDouble
        var mark_read: ConversationThreadMarkReadV1
        var notifications_marked_read: PostgresFlexibleDouble
        var page_meta: ConversationThreadPageMetaV1
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }

    /// Required envelope fields — missing `messages` must not decode as silent success.
    func validateRequiredFields() throws {
        let conversationID = data.conversation.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationID.isEmpty else {
            throw ConversationThreadContractError.missingField("conversation.id")
        }
        guard data.membership.is_participant.value ?? false else {
            throw ConversationThreadContractError.accessDenied
        }
    }
}

nonisolated struct ConversationThreadConversationV1: Codable, Sendable, Equatable {
    var id: String
    var is_group: PostgresFlexibleBool
    var name: String?
    var avatar_url: String?
    var is_pinned: PostgresFlexibleBool
}

nonisolated struct ConversationThreadMembershipV1: Codable, Sendable, Equatable {
    var is_participant: PostgresFlexibleBool
}

nonisolated struct ConversationThreadParticipantV1: Codable, Sendable, Equatable {
    var user_id: String
    var profiles: ConversationThreadParticipantProfileV1?
}

nonisolated struct ConversationThreadParticipantProfileV1: Codable, Sendable, Equatable {
    var id: String?
    var username: String?
    var avatar_url: String?
}

nonisolated struct ConversationThreadBlockStatusV1: Codable, Sendable, Equatable {
    var other_user_id: String
    var blocked_by_me: PostgresFlexibleBool
    var blocked_by_other: PostgresFlexibleBool
}

nonisolated struct ConversationThreadMessageV1: Codable, Sendable, Equatable {
    var id: String
    var conversation_id: String?
    var sender_id: String?
    var sender_anonymized: PostgresFlexibleBool
    var content: String?
    var created_at: String?
    var seen_by: [String]
    var type: String?
    var trade_id: String?
    var post_id: String?
    var profile_post_id: String?
    var achievement_post_id: String?
    var reel_id: String?
    var parent_message_id: String?
    var deleted_for_everyone: PostgresFlexibleBool
    var image_url: String?
    var audio_url: String?
    var audio_duration_ms: Int?
    var is_system: PostgresFlexibleBool
    var profiles: ConversationThreadMessageProfileV1?
}

nonisolated struct ConversationThreadMessageProfileV1: Codable, Sendable, Equatable {
    var username: String?
    var avatar_url: String?
}

nonisolated struct ConversationThreadMarkReadV1: Codable, Sendable, Equatable {
    var applied: PostgresFlexibleBool
}

nonisolated struct ConversationThreadPageMetaV1: Codable, Sendable, Equatable {
    var limit: PostgresFlexibleDouble
    var returned: PostgresFlexibleDouble
    var has_more: PostgresFlexibleBool
}

nonisolated enum ConversationThreadContractError: Error, Sendable, Equatable {
    case missingField(String)
    case accessDenied
    case malformedMessage(String)
}
