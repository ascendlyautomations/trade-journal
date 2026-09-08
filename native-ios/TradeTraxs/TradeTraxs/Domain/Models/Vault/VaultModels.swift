import Foundation

/// Stable Vault content key — mirrors ``InteractionTarget`` routing + Supabase `vault_items`.
nonisolated struct VaultContentRef: Hashable, Codable, Sendable {
    var contentType: VaultContentType
    var contentID: String

    var cacheKey: String { "\(contentType.rawValue):\(contentID)" }
}

nonisolated enum VaultContentType: String, Hashable, Codable, Sendable, CaseIterable {
    case trade
    case profilePost = "profile_post"
    case feedPost = "feed_post"
    case reel
    case achievement

    var displayName: String {
        switch self {
        case .trade: return "Trades"
        case .profilePost, .feedPost: return "Posts"
        case .reel: return "Clips"
        case .achievement: return "Achievements"
        }
    }

    var filterLabel: String {
        switch self {
        case .trade: return "Trades"
        case .profilePost, .feedPost: return "Posts"
        case .reel: return "Clips"
        case .achievement: return "Achievements"
        }
    }
}

nonisolated struct VaultFolderID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct VaultItemID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct VaultFolder: Hashable, Codable, Sendable, Identifiable {
    var id: VaultFolderID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct VaultItem: Hashable, Codable, Sendable, Identifiable {
    var id: VaultItemID
    var ref: VaultContentRef
    var createdAt: Date
    var folderIDs: [VaultFolderID]
}

/// Session snapshot for a content ref — used by cards and detail headers.
nonisolated struct VaultItemState: Hashable, Codable, Sendable {
    var isVaulted: Bool
    var vaultItemID: VaultItemID?
    var folderIDs: [VaultFolderID]

    static let notVaulted = VaultItemState(isVaulted: false, vaultItemID: nil, folderIDs: [])
}

nonisolated enum VaultContentFilter: String, Hashable, Codable, Sendable, CaseIterable {
    case all
    case trades
    case clips
    case posts
    case achievements

    func matches(_ type: VaultContentType) -> Bool {
        switch self {
        case .all: return true
        case .trades: return type == .trade
        case .clips: return type == .reel
        case .posts: return type == .profilePost || type == .feedPost
        case .achievements: return type == .achievement
        }
    }
}

nonisolated struct VaultListPage: Sendable {
    var items: [VaultItem]
    var nextCursor: String?
}

extension VaultContentRef {
    static func from(_ target: InteractionTarget) -> VaultContentRef? {
        switch target.kind {
        case .trade:
            return VaultContentRef(contentType: .trade, contentID: target.id)
        case .profilePost:
            return VaultContentRef(contentType: .profilePost, contentID: target.id)
        case .feedPost:
            return VaultContentRef(contentType: .feedPost, contentID: target.id)
        case .reel:
            return VaultContentRef(contentType: .reel, contentID: target.id)
        case .achievement:
            return VaultContentRef(contentType: .achievement, contentID: target.id)
        }
    }
}

enum VaultSupport {
    static let folderNameMaxLength = 64

    static func normalizedFolderName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > folderNameMaxLength {
            return String(trimmed.prefix(folderNameMaxLength))
        }
        return trimmed
    }
}
