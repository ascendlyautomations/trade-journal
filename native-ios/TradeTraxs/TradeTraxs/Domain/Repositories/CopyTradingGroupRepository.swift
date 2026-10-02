import Foundation

enum CopyTradingGroupFailure: Error, Equatable, Sendable {
    case duplicateName
    case notFound
    case message(String)
}

nonisolated protocol CopyTradingGroupRepository: Sendable {
    func groups(for userID: ProfileID) async throws -> [CopyTradingGroup]
    func create(userID: ProfileID, name: String, accountIDs: [String]) async throws -> CopyTradingGroup
    func update(
        userID: ProfileID,
        groupID: String,
        name: String,
        accountIDs: [String]
    ) async throws -> CopyTradingGroup
    func delete(userID: ProfileID, groupID: String) async throws
}
