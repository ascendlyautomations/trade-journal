import Foundation

/// Canonical owner for personal and group conversation creation from Messages New Chat.
@MainActor
final class ConversationCreationCoordinator {
    static let shared = ConversationCreationCoordinator()

    struct Result: Sendable {
        var conversation: Conversation
        var wasExisting: Bool
    }

    enum CreationError: Error, Sendable, Equatable {
        case blockedRecipient
        case invalidRecipients
        case participantInsertFailed
        case staleSession
    }

    private var generation: UInt64 = 0
    private var inFlightKeys: Set<String> = []

    private init() {}

    func invalidate() {
        generation &+= 1
        inFlightKeys.removeAll()
        #if DEBUG
        ConversationCreationTelemetry.reset()
        #endif
    }

    /// Opens or creates a 1:1 conversation — never duplicates when inbox or server already has one.
    func openDirectConversation(
        viewerID: ProfileID,
        recipient: Profile,
        messages: any MessageRepository,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore
    ) async throws -> Result {
        let flightKey = ConversationCreationSupport.mutationFlightKey(
            viewerID: viewerID,
            recipientID: recipient.id
        )
        guard !inFlightKeys.contains(flightKey) else {
            if let existing = ConversationCreationSupport.findExistingDirectLocally(
                viewerID: viewerID,
                recipientID: recipient.id,
                inboxStore: inboxStore
            ) {
                return Result(conversation: existing, wasExisting: true)
            }
            if let indexedID = DirectConversationPairIndex.shared.conversationID(
                viewerID: viewerID,
                recipientID: recipient.id
            ) {
                let conversation = ConversationCreationSupport.buildDirectConversation(
                    id: indexedID,
                    viewerID: viewerID,
                    recipient: recipient
                )
                return Result(conversation: conversation, wasExisting: true)
            }
            throw CreationError.staleSession
        }
        inFlightKeys.insert(flightKey)
        defer { inFlightKeys.remove(flightKey) }

        let sessionGeneration = generation
        #if DEBUG
        ConversationCreationTelemetry.started(type: "direct", recipientCount: 1)
        #endif

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || MessagesInboxSupport.isLocalDevelopmentProfile(recipient.id)
        {
            return try openDirectDevConversation(
                viewerID: viewerID,
                recipient: recipient,
                detailCache: detailCache,
                inboxStore: inboxStore
            )
        }

        if let existing = ConversationCreationSupport.findExistingDirectLocally(
            viewerID: viewerID,
            recipientID: recipient.id,
            inboxStore: inboxStore
        ) {
            #if DEBUG
            ConversationCreationTelemetry.duplicateLookupCompleted()
            ConversationCreationTelemetry.blockValidationCompleted()
            #endif
            seedAndFinish(viewerID: viewerID, conversation: existing, profiles: [recipient], detailCache: detailCache, inboxStore: inboxStore, wasExisting: true)
            return Result(conversation: existing, wasExisting: true)
        }

        async let duplicateTask = messages.findExistingDirectConversationID(
            viewerID: viewerID,
            recipientID: recipient.id
        )
        async let blockTask = messages.usersHaveActiveBlock(
            viewerID: viewerID,
            otherID: recipient.id
        )

        if let existingID = try await duplicateTask {
            #if DEBUG
            ConversationCreationTelemetry.duplicateLookupCompleted()
            #endif
            guard sessionGeneration == generation else { throw CreationError.staleSession }
            DirectConversationPairIndex.shared.register(
                conversation: ConversationCreationSupport.buildDirectConversation(
                    id: existingID,
                    viewerID: viewerID,
                    recipient: recipient
                )
            )
            let conversation = ConversationCreationSupport.buildDirectConversation(
                id: existingID,
                viewerID: viewerID,
                recipient: recipient
            )
            seedAndFinish(viewerID: viewerID, conversation: conversation, profiles: [recipient], detailCache: detailCache, inboxStore: inboxStore, wasExisting: true)
            return Result(conversation: conversation, wasExisting: true)
        }

        #if DEBUG
        ConversationCreationTelemetry.duplicateLookupCompleted()
        #endif

        if await blockTask {
            #if DEBUG
            ConversationCreationTelemetry.blockValidationCompleted()
            #endif
            throw CreationError.blockedRecipient
        }
        #if DEBUG
        ConversationCreationTelemetry.blockValidationCompleted()
        #endif

        guard sessionGeneration == generation else { throw CreationError.staleSession }

        let conversation = try await messages.createDirectConversation(
            viewerID: viewerID,
            recipient: recipient
        )
        #if DEBUG
        ConversationCreationTelemetry.persisted(conversationID: conversation.id)
        ConversationCreationTelemetry.participantsCompleted(count: 2)
        #endif

        guard sessionGeneration == generation else { throw CreationError.staleSession }

        seedAndFinish(viewerID: viewerID, conversation: conversation, profiles: [recipient], detailCache: detailCache, inboxStore: inboxStore, wasExisting: false)
        return Result(conversation: conversation, wasExisting: false)
    }

    /// Creates a group conversation with viewer + selected recipients (minimum two others).
    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?,
        messages: any MessageRepository,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore
    ) async throws -> Result {
        let uniqueRecipients = recipients.uniqued(by: \.id).filter { $0.id != viewerID }
        guard uniqueRecipients.count >= 2 else {
            throw CreationError.invalidRecipients
        }

        let flightKey = ConversationCreationSupport.groupMutationFlightKey(
            viewerID: viewerID,
            participantIDs: uniqueRecipients.map(\.id)
        )
        guard !inFlightKeys.contains(flightKey) else {
            throw CreationError.staleSession
        }
        inFlightKeys.insert(flightKey)
        defer { inFlightKeys.remove(flightKey) }

        let sessionGeneration = generation
        #if DEBUG
        ConversationCreationTelemetry.started(type: "group", recipientCount: uniqueRecipients.count)
        ConversationCreationTelemetry.duplicateLookupCompleted()
        #endif

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            let conversation = ConversationCreationSupport.buildGroupConversation(
                id: ConversationID("dev-group-\(UUID().uuidString.lowercased())"),
                viewerID: viewerID,
                recipients: uniqueRecipients,
                name: name
            )
            seedAndFinish(viewerID: viewerID, conversation: conversation, profiles: uniqueRecipients, detailCache: detailCache, inboxStore: inboxStore, wasExisting: false)
            return Result(conversation: conversation, wasExisting: false)
        }

        for recipient in uniqueRecipients {
            if await messages.usersHaveActiveBlock(viewerID: viewerID, otherID: recipient.id) {
                #if DEBUG
                ConversationCreationTelemetry.blockValidationCompleted()
                #endif
                throw CreationError.blockedRecipient
            }
        }
        #if DEBUG
        ConversationCreationTelemetry.blockValidationCompleted()
        #endif

        guard sessionGeneration == generation else { throw CreationError.staleSession }

        let conversation = try await messages.createGroupConversation(
            viewerID: viewerID,
            recipients: uniqueRecipients,
            name: name
        )
        #if DEBUG
        ConversationCreationTelemetry.persisted(conversationID: conversation.id)
        ConversationCreationTelemetry.participantsCompleted(count: uniqueRecipients.count + 1)
        #endif

        guard sessionGeneration == generation else { throw CreationError.staleSession }

        seedAndFinish(
            viewerID: viewerID,
            conversation: conversation,
            profiles: uniqueRecipients,
            detailCache: detailCache,
            inboxStore: inboxStore,
            wasExisting: false
        )
        return Result(conversation: conversation, wasExisting: false)
    }

    // MARK: - Private

    private func openDirectDevConversation(
        viewerID: ProfileID,
        recipient: Profile,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore
    ) throws -> Result {
        if let existing = ConversationCreationSupport.findExistingDirectLocally(
            viewerID: viewerID,
            recipientID: recipient.id,
            inboxStore: inboxStore
        ) {
            seedAndFinish(viewerID: viewerID, conversation: existing, profiles: [recipient], detailCache: detailCache, inboxStore: inboxStore, wasExisting: true)
            return Result(conversation: existing, wasExisting: true)
        }
        let created = ConversationCreationSupport.buildDirectConversation(
            id: devConversationID(for: recipient),
            viewerID: viewerID,
            recipient: recipient
        )
        seedAndFinish(viewerID: viewerID, conversation: created, profiles: [recipient], detailCache: detailCache, inboxStore: inboxStore, wasExisting: false)
        return Result(conversation: created, wasExisting: false)
    }

    private func devConversationID(for recipient: Profile) -> ConversationID {
        let suffix = recipient.id.rawValue.replacingOccurrences(of: "dev.follower.", with: "")
        return ConversationID("dev-dm-\(suffix)")
    }

    private func seedAndFinish(
        viewerID: ProfileID,
        conversation: Conversation,
        profiles: [Profile],
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore,
        wasExisting: Bool
    ) {
        ConversationCreationSupport.seedCanonicalState(
            viewerID: viewerID,
            conversation: conversation,
            profiles: profiles,
            detailCache: detailCache,
            inboxStore: inboxStore
        )
        #if DEBUG
        ConversationCreationTelemetry.cacheSeedCompleted()
        _ = wasExisting
        #endif
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
