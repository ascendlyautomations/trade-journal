import Foundation

nonisolated struct AdminUserDirectoryQuery: Sendable, Equatable {
    var search: String
    var bannedFilter: AdminUserBannedFilter
    var proFilter: AdminUserProFilter
    var privacyFilter: AdminUserPrivacyFilter
    var limit: Int
    var offset: Int

    static let defaultPageSize = 20
}

nonisolated enum AdminUserBannedFilter: String, Sendable, CaseIterable {
    case all
    case banned
    case active
}

nonisolated enum AdminUserProFilter: String, Sendable, CaseIterable {
    case all
    case pro
    case nonPro = "non_pro"
}

nonisolated enum AdminUserPrivacyFilter: String, Sendable, CaseIterable {
    case all
    case `private`
    case `public`
}

nonisolated struct AdminUserDirectoryPage: Sendable {
    var rows: [AdminUserSummary]
    var total: Int
}

struct AdminUserSummary: Sendable, Hashable, Identifiable, Codable {
    var id: ProfileID
    var username: String
    var name: String
    var email: String
    var avatarURL: String?
    var createdAt: Date?
    var isPrivate: Bool
    var isPro: Bool
    var subscriptionStatus: String
    var referralCode: String
    var isBanned: Bool
    var bannedReason: String?
    var bannedAt: Date?
    var isBetaTester: Bool
}

nonisolated struct AdminUserActivityCounts: Sendable, Equatable {
    var trades: Int
    var posts: Int
    var achievements: Int
    var feedback: Int
    var supportTickets: Int
}

nonisolated struct AdminUserDeletionPreview: Sendable {
    /// Raw preview payload from the server (table → count labels).
    var fields: [(label: String, value: String)]
}

enum AdminUserDeletionFailure: Error, Sendable, LocalizedError {
    case notAuthenticated
    case forbidden
    case selfDelete
    case adminTarget
    case validation(String)
    case server(step: String?, table: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Session expired."
        case .forbidden: return "You don't have permission to perform this action."
        case .selfDelete: return "You cannot delete your own account."
        case .adminTarget: return "Admin accounts cannot be deleted."
        case .validation(let message): return message
        case .server(_, _, let message): return message
        }
    }
}

nonisolated protocol AdminUsersRepository: Sendable {
    func fetchDirectory(_ query: AdminUserDirectoryQuery) async throws -> AdminUserDirectoryPage
    func fetchActivityCounts(targetUserID: ProfileID) async throws -> AdminUserActivityCounts
    func banUser(targetUserID: ProfileID, adminUserID: ProfileID, reason: String) async throws
    func unbanUser(targetUserID: ProfileID, adminUserID: ProfileID) async throws
    func fetchDeletionPreview(targetUserID: ProfileID) async throws -> AdminUserDeletionPreview
    func deleteUser(targetUserID: ProfileID) async throws
}
