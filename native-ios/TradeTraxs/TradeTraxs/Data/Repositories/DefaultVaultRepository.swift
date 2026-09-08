import Foundation
import OSLog

nonisolated struct DefaultVaultRepository: VaultRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding

    init(supabase: SupabaseInfrastructure, session: any SessionProviding) {
        self.supabase = supabase
        self.session = session
    }

    func state(for refs: [VaultContentRef]) async throws -> [VaultContentRef: VaultItemState] {
        guard let userID = await session.currentUserID?.rawValue else { return [:] }
        guard !refs.isEmpty else { return [:] }

        let payload = refs.map {
            VaultDTO.StateBatchItem(content_type: $0.contentType.rawValue, content_id: $0.contentID)
        }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_vault_state_batch",
            parametersJSON: try JSONEncoder().encode(["p_items": payload])
        )

        let decoder = JSONDecoder()
        let wire = try decoder.decode([VaultDTO.StateBatchWire].self, from: data)
        var result: [VaultContentRef: VaultItemState] = [:]
        for entry in wire {
            guard let type = VaultContentType(rawValue: entry.content_type) else { continue }
            let ref = VaultContentRef(contentType: type, contentID: entry.content_id)
            let folderIDs = (entry.folder_ids ?? []).map { VaultFolderID(rawValue: $0) }
            result[ref] = VaultItemState(
                isVaulted: true,
                vaultItemID: VaultItemID(entry.vault_item_id),
                folderIDs: folderIDs
            )
        }
        for ref in refs where result[ref] == nil {
            result[ref] = .notVaulted
        }
        _ = userID
        return result
    }

    func folders() async throws -> [VaultFolder] {
        guard let userID = await session.currentUserID?.rawValue else { return [] }
        let rows: [VaultDTO.FolderRow] = try await supabase.database.select(
            VaultDTO.FolderRow.self,
            from: "vault_folders",
            query: [
                SupabaseQuery.select("id,user_id,name,created_at,updated_at"),
                SupabaseQuery.eq("user_id", userID),
                URLQueryItem(name: "order", value: "name.asc"),
            ]
        )
        return rows.compactMap(mapFolder)
    }

    func createFolder(name: String) async throws -> VaultFolder {
        guard let userID = await session.currentUserID?.rawValue else {
            throw AppError.authentication(.sessionMissing)
        }
        guard let normalized = VaultSupport.normalizedFolderName(name) else {
            throw AppError.unknown(message: "Folder name cannot be empty.")
        }
        do {
            let row: VaultDTO.FolderRow = try await supabase.database.insert(
                VaultDTO.InsertFolderBody(user_id: userID, name: normalized),
                into: "vault_folders",
                returning: VaultDTO.FolderRow.self
            )
            guard let folder = mapFolder(row) else {
                throw AppError.unknown(message: "Could not create folder.")
            }
            return folder
        } catch {
            throw mapFolderMutationError(error)
        }
    }

    func renameFolder(id: VaultFolderID, name: String) async throws -> VaultFolder {
        guard let normalized = VaultSupport.normalizedFolderName(name) else {
            throw AppError.unknown(message: "Folder name cannot be empty.")
        }
        do {
            let row: VaultDTO.FolderRow = try await supabase.database.update(
                VaultDTO.UpdateFolderBody(
                    name: normalized,
                    updated_at: ISO8601DateFormatter().string(from: Date())
                ),
                table: "vault_folders",
                query: [SupabaseQuery.eq("id", id.rawValue)],
                returning: VaultDTO.FolderRow.self
            )
            guard let folder = mapFolder(row) else {
                throw AppError.unknown(message: "Could not rename folder.")
            }
            return folder
        } catch {
            throw mapFolderMutationError(error)
        }
    }

    func deleteFolder(id: VaultFolderID) async throws {
        try await supabase.database.delete(
            from: "vault_folders",
            query: [SupabaseQuery.eq("id", id.rawValue)]
        )
    }

    func saveToVault(ref: VaultContentRef, folderID: VaultFolderID?) async throws -> VaultItem {
        guard let userID = await session.currentUserID?.rawValue else {
            throw AppError.authentication(.sessionMissing)
        }

        let item = try await upsertVaultItem(ref: ref, userID: userID)
        if let folderID {
            try await insertFolderMembership(folderID: folderID, vaultItemID: item.id)
            var updated = item
            if !updated.folderIDs.contains(folderID) {
                updated.folderIDs.append(folderID)
            }
            return updated
        }
        return item
    }

    func addToFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {
        try await insertFolderMembership(folderID: folderID, vaultItemID: vaultItemID)
    }

    func removeFromFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {
        try await supabase.database.delete(
            from: "vault_folder_items",
            query: [
                SupabaseQuery.eq("folder_id", folderID.rawValue),
                SupabaseQuery.eq("vault_item_id", vaultItemID.rawValue),
            ]
        )
    }

    func removeFromVault(vaultItemID: VaultItemID) async throws {
        try await supabase.database.delete(
            from: "vault_items",
            query: [SupabaseQuery.eq("id", vaultItemID.rawValue)]
        )
    }

    func listItems(
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        cursor: String?,
        limit: Int
    ) async throws -> VaultListPage {
        guard await session.currentUserID != nil else {
            return VaultListPage(items: [], nextCursor: nil)
        }

        var itemRows: [VaultDTO.ItemRow]
        if let folderID {
            itemRows = try await listItemsInFolder(folderID: folderID, cursor: cursor, limit: limit)
        } else {
            itemRows = try await listAllItems(filter: filter, cursor: cursor, limit: limit)
        }

        let folderMap = try await folderMembership(for: itemRows.map(\.id))
        let items = itemRows.compactMap { row -> VaultItem? in
            guard let type = VaultContentType(rawValue: row.content_type) else { return nil }
            return VaultItem(
                id: VaultItemID(row.id),
                ref: VaultContentRef(contentType: type, contentID: row.content_id),
                createdAt: parseDate(row.created_at) ?? Date(timeIntervalSince1970: 0),
                folderIDs: folderMap[row.id] ?? []
            )
        }

        let nextCursor = SupabaseQuery.nextCursor(items: itemRows, limit: limit) { $0.created_at }
        return VaultListPage(items: items, nextCursor: nextCursor)
    }

    // MARK: - Private

    private func upsertVaultItem(ref: VaultContentRef, userID: String) async throws -> VaultItem {
        do {
            let row: VaultDTO.ItemRow = try await supabase.database.upsert(
                VaultDTO.InsertItemBody(
                    user_id: userID,
                    content_type: ref.contentType.rawValue,
                    content_id: ref.contentID
                ),
                into: "vault_items",
                onConflict: "user_id,content_type,content_id",
                returning: VaultDTO.ItemRow.self,
                select: "id,user_id,content_type,content_id,created_at"
            )
            let folderMap = try await folderMembership(for: [row.id])
            return VaultItem(
                id: VaultItemID(row.id),
                ref: ref,
                createdAt: parseDate(row.created_at) ?? Date(),
                folderIDs: folderMap[row.id] ?? []
            )
        } catch {
            AppLog.networking.error("Vault upsert failed: \(String(describing: error), privacy: .public)")
            throw AppError.unknown(message: "Could not save to Vault.")
        }
    }

    private func insertFolderMembership(folderID: VaultFolderID, vaultItemID: VaultItemID) async throws {
        do {
            _ = try await supabase.database.insert(
                VaultDTO.InsertFolderItemBody(
                    folder_id: folderID.rawValue,
                    vault_item_id: vaultItemID.rawValue
                ),
                into: "vault_folder_items",
                returning: VaultDTO.FolderItemRow.self
            )
        } catch {
            let text = String(describing: error)
            if text.contains("23505") { return }
            throw error
        }
    }

    private func listAllItems(
        filter: VaultContentFilter,
        cursor: String?,
        limit: Int
    ) async throws -> [VaultDTO.ItemRow] {
        var query: [URLQueryItem] = [
            SupabaseQuery.select("id,user_id,content_type,content_id,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor, !cursor.isEmpty {
            query.append(URLQueryItem(name: "created_at", value: "lt.\(cursor)"))
        }
        switch filter {
        case .all:
            break
        case .trades:
            query.append(SupabaseQuery.eq("content_type", VaultContentType.trade.rawValue))
        case .clips:
            query.append(SupabaseQuery.eq("content_type", VaultContentType.reel.rawValue))
        case .posts:
            query.append(
                URLQueryItem(
                    name: "content_type",
                    value: "in.(profile_post,feed_post)"
                )
            )
        case .achievements:
            query.append(SupabaseQuery.eq("content_type", VaultContentType.achievement.rawValue))
        }
        return try await supabase.database.select(
            VaultDTO.ItemRow.self,
            from: "vault_items",
            query: query
        )
    }

    private func listItemsInFolder(
        folderID: VaultFolderID,
        cursor: String?,
        limit: Int
    ) async throws -> [VaultDTO.ItemRow] {
        var linkQuery: [URLQueryItem] = [
            SupabaseQuery.select("folder_id,vault_item_id,created_at"),
            SupabaseQuery.eq("folder_id", folderID.rawValue),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor, !cursor.isEmpty {
            linkQuery.append(URLQueryItem(name: "created_at", value: "lt.\(cursor)"))
        }
        let links: [VaultDTO.FolderItemRow] = try await supabase.database.select(
            VaultDTO.FolderItemRow.self,
            from: "vault_folder_items",
            query: linkQuery
        )
        let ids = links.map(\.vault_item_id)
        guard !ids.isEmpty else { return [] }
        let items: [VaultDTO.ItemRow] = try await supabase.database.select(
            VaultDTO.ItemRow.self,
            from: "vault_items",
            query: [
                SupabaseQuery.select("id,user_id,content_type,content_id,created_at"),
                SupabaseQuery.isIn("id", ids),
            ]
        )
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return items.sorted {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    private func folderMembership(for itemIDs: [String]) async throws -> [String: [VaultFolderID]] {
        guard !itemIDs.isEmpty else { return [:] }
        let rows: [VaultDTO.FolderItemRow] = try await supabase.database.select(
            VaultDTO.FolderItemRow.self,
            from: "vault_folder_items",
            query: [
                SupabaseQuery.select("folder_id,vault_item_id,created_at"),
                SupabaseQuery.isIn("vault_item_id", itemIDs),
            ]
        )
        var map: [String: [VaultFolderID]] = [:]
        for row in rows {
            map[row.vault_item_id, default: []].append(VaultFolderID(row.folder_id))
        }
        return map
    }

    private func mapFolder(_ row: VaultDTO.FolderRow) -> VaultFolder? {
        VaultFolder(
            id: VaultFolderID(row.id),
            name: row.name,
            createdAt: parseDate(row.created_at) ?? Date(timeIntervalSince1970: 0),
            updatedAt: parseDate(row.updated_at) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
    }

    private func mapFolderMutationError(_ error: Error) -> Error {
        let text = String(describing: error)
        if text.contains("23505") || text.localizedCaseInsensitiveContains("duplicate") {
            return AppError.unknown(message: "You already have a folder with that name.")
        }
        if let app = error as? AppError { return app }
        return AppError.unknown(message: "Could not update folder.")
    }
}
