import Foundation

/// Web `lib/copyTradingGroups.ts` against the same tables. Owner RLS only.
nonisolated struct DefaultCopyTradingGroupRepository: CopyTradingGroupRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding

    init(supabase: SupabaseInfrastructure, session: any SessionProviding) {
        self.supabase = supabase
        self.session = session
    }

    func groups(for userID: ProfileID) async throws -> [CopyTradingGroup] {
        try await requireSession(userID)
        let groupRows: [GroupRow] = try await supabase.database.select(
            GroupRow.self,
            from: "copy_trading_groups",
            query: [
                SupabaseQuery.select("id,name,created_at,updated_at"),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.order("name", ascending: true),
            ]
        )
        guard !groupRows.isEmpty else { return [] }
        let memberRows: [MemberRow] = try await supabase.database.select(
            MemberRow.self,
            from: "copy_trading_group_accounts",
            query: [
                SupabaseQuery.select("group_id,account_id,sort_order"),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        return groupRows.map { group in
            let members = memberRows
                .filter { $0.group_id == group.id }
                .sorted {
                    if $0.sort_order != $1.sort_order { return $0.sort_order < $1.sort_order }
                    return $0.account_id < $1.account_id
                }
            return CopyTradingGroup(
                id: group.id,
                name: group.name,
                accountIDs: members.map(\.account_id),
                createdAt: group.created_at,
                updatedAt: group.updated_at
            )
        }
    }

    func create(userID: ProfileID, name: String, accountIDs: [String]) async throws -> CopyTradingGroup {
        try await requireSession(userID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group: GroupRow
        do {
            group = try await supabase.database.insert(
                GroupInsert(user_id: userID.rawValue, name: trimmed),
                into: "copy_trading_groups",
                returning: GroupRow.self
            )
        } catch {
            throw mapWriteError(error)
        }
        do {
            try await insertMembers(userID: userID, groupID: group.id, accountIDs: accountIDs)
        } catch {
            try? await supabase.database.delete(
                from: "copy_trading_groups",
                query: [
                    SupabaseQuery.eq("id", group.id),
                    SupabaseQuery.eq("user_id", userID.rawValue),
                ]
            )
            throw mapWriteError(error)
        }
        return CopyTradingGroup(
            id: group.id,
            name: group.name,
            accountIDs: accountIDs,
            createdAt: group.created_at,
            updatedAt: group.updated_at
        )
    }

    func update(
        userID: ProfileID,
        groupID: String,
        name: String,
        accountIDs: [String]
    ) async throws -> CopyTradingGroup {
        try await requireSession(userID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group: GroupRow
        do {
            group = try await supabase.database.update(
                GroupNameUpdate(name: trimmed),
                table: "copy_trading_groups",
                query: [
                    SupabaseQuery.eq("id", groupID),
                    SupabaseQuery.eq("user_id", userID.rawValue),
                ],
                returning: GroupRow.self
            )
        } catch {
            throw mapWriteError(error)
        }
        try await supabase.database.delete(
            from: "copy_trading_group_accounts",
            query: [
                SupabaseQuery.eq("group_id", groupID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        do {
            try await insertMembers(userID: userID, groupID: groupID, accountIDs: accountIDs)
        } catch {
            throw mapWriteError(error)
        }
        return CopyTradingGroup(
            id: group.id,
            name: group.name,
            accountIDs: accountIDs,
            createdAt: group.created_at,
            updatedAt: group.updated_at
        )
    }

    func delete(userID: ProfileID, groupID: String) async throws {
        try await requireSession(userID)
        let owned: [GroupIDRow] = try await supabase.database.select(
            GroupIDRow.self,
            from: "copy_trading_groups",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("id", groupID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        guard owned.contains(where: { $0.id == groupID }) else {
            throw CopyTradingGroupFailure.notFound
        }
        // Historical trades stay. `copy_trading_group_id` is cleared; accounts and broker rows are untouched.
        try await supabase.database.update(
            UnlinkTradesFromGroup(),
            table: "trades",
            query: [
                SupabaseQuery.eq("copy_trading_group_id", groupID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        try await supabase.database.delete(
            from: "copy_trading_groups",
            query: [
                SupabaseQuery.eq("id", groupID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
    }

    private func requireSession(_ userID: ProfileID) async throws {
        guard let sessionUser = await session.currentUserID,
              sessionUser.rawValue == userID.rawValue
        else {
            throw CopyTradingGroupFailure.message("Sign in to manage copy trading accounts.")
        }
    }

    private func insertMembers(userID: ProfileID, groupID: String, accountIDs: [String]) async throws {
        let rows = accountIDs.enumerated().map { index, accountID in
            MemberInsert(
                group_id: groupID,
                account_id: accountID,
                user_id: userID.rawValue,
                sort_order: index
            )
        }
        guard !rows.isEmpty else { return }
        try await supabase.database.insert(rows, into: "copy_trading_group_accounts")
    }

    private func mapWriteError(_ error: Error) -> CopyTradingGroupFailure {
        if error is CopyTradingGroupFailure, let typed = error as? CopyTradingGroupFailure {
            return typed
        }
        let text = String(describing: error)
        if text.contains("23505") || text.localizedCaseInsensitiveContains("duplicate") {
            return .duplicateName
        }
        if text.localizedCaseInsensitiveContains("must belong to the group owner") {
            return .message("You can only add accounts you own.")
        }
        return .message("Couldn't save this copy trading group.")
    }
}

private nonisolated struct GroupRow: Decodable, Sendable {
    var id: String
    var name: String
    var created_at: String
    var updated_at: String
}

private nonisolated struct GroupIDRow: Decodable, Sendable {
    var id: String
}

private nonisolated struct MemberRow: Decodable, Sendable {
    var group_id: String
    var account_id: String
    var sort_order: Int
}

private nonisolated struct GroupInsert: Encodable, Sendable {
    var user_id: String
    var name: String
}

private nonisolated struct GroupNameUpdate: Encodable, Sendable {
    var name: String
}

private nonisolated struct MemberInsert: Encodable, Sendable {
    var group_id: String
    var account_id: String
    var user_id: String
    var sort_order: Int
}

/// Encodes JSON null so PostgREST clears `trades.copy_trading_group_id`.
private nonisolated struct UnlinkTradesFromGroup: Encodable, Sendable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .copy_trading_group_id)
    }

    private enum CodingKeys: String, CodingKey {
        case copy_trading_group_id
    }
}
