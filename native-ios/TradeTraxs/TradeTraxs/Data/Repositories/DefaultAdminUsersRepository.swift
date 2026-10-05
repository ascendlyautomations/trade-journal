import Foundation

nonisolated struct DefaultAdminUsersRepository: AdminUsersRepository {
    private let supabase: SupabaseInfrastructure
    private let transport: SupabaseTransport

    init(supabase: SupabaseInfrastructure) {
        guard let transport = supabase.transport else {
            preconditionFailure("DefaultAdminUsersRepository requires Supabase transport")
        }
        self.supabase = supabase
        self.transport = transport
    }

    func fetchDirectory(_ query: AdminUserDirectoryQuery) async throws -> AdminUserDirectoryPage {
        let searchTrim = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let pBanned: Bool? = query.bannedFilter == .all ? nil : (query.bannedFilter == .banned)
        let pPro: Bool? = query.proFilter == .all ? nil : (query.proFilter == .pro)
        let pPrivate: Bool? = query.privacyFilter == .all ? nil : (query.privacyFilter == .private)

        var params: [String: Any] = [
            "p_limit": query.limit,
            "p_offset": query.offset,
        ]
        if searchTrim.isEmpty {
            params["p_search"] = NSNull()
        } else {
            params["p_search"] = searchTrim
        }
        params["p_banned"] = pBanned.map { $0 } ?? NSNull()
        params["p_pro"] = pPro.map { $0 } ?? NSNull()
        params["p_private"] = pPrivate.map { $0 } ?? NSNull()

        let body = try JSONSerialization.data(withJSONObject: params, options: [])
        let data = try await supabase.database.rpcData(
            functionName: "admin_list_users",
            parametersJSON: body
        )

        let rowsRaw = try decodeJSONArray(from: data)
        if rowsRaw.isEmpty {
            return AdminUserDirectoryPage(rows: [], total: 0)
        }

        let rows = rowsRaw.compactMap { AdminUserSummary(json: $0) }
        let total = parseDirectoryCount(rowsRaw.first) ?? rows.count
        return AdminUserDirectoryPage(rows: rows, total: total)
    }

    func fetchActivityCounts(targetUserID: ProfileID) async throws -> AdminUserActivityCounts {
        let body = try JSONSerialization.data(
            withJSONObject: ["p_target": targetUserID.rawValue],
            options: []
        )
        let data = try await supabase.database.rpcData(
            functionName: "admin_user_activity_counts",
            parametersJSON: body
        )
        let object = try decodeJSONObject(from: data)
        func n(_ key: String) -> Int {
            AdminJSONInt.parse(object[key])
        }
        return AdminUserActivityCounts(
            trades: n("trades"),
            posts: n("posts"),
            achievements: n("achievements"),
            feedback: n("feedback"),
            supportTickets: n("supportTickets") != 0 ? n("supportTickets") : n("support")
        )
    }

    func banUser(targetUserID: ProfileID, adminUserID: ProfileID, reason: String) async throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = AdminISO8601.string(from: Date())
        let patch = ProfileBanPatch(
            is_banned: true,
            banned_reason: trimmed.isEmpty ? nil : trimmed,
            banned_at: now,
            banned_by: adminUserID.rawValue
        )
        try await supabase.database.update(
            patch,
            table: "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(targetUserID.rawValue)")]
        )
        try await insertAudit(
            adminUserID: adminUserID,
            targetUserID: targetUserID,
            action: "ban_user",
            details: ["reason": trimmed.isEmpty ? "" : trimmed]
        )
    }

    func unbanUser(targetUserID: ProfileID, adminUserID: ProfileID) async throws {
        let patch = ProfileBanPatch(
            is_banned: false,
            banned_reason: nil,
            banned_at: nil,
            banned_by: nil
        )
        try await supabase.database.update(
            patch,
            table: "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(targetUserID.rawValue)")]
        )
        try await insertAudit(
            adminUserID: adminUserID,
            targetUserID: targetUserID,
            action: "unban_user",
            details: [:]
        )
    }

    func setHiddenFromCommunity(targetUserID: ProfileID, adminUserID: ProfileID, hidden: Bool) async throws {
        let patch = ProfileCommunityVisibilityPatch(is_hidden_from_community: hidden)
        try await supabase.database.update(
            patch,
            table: "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(targetUserID.rawValue)")]
        )
        try await insertAudit(
            adminUserID: adminUserID,
            targetUserID: targetUserID,
            action: hidden ? "hide_user_from_community" : "unhide_user_from_community",
            details: ["is_hidden_from_community": hidden ? "true" : "false"]
        )
    }

    func fetchDeletionPreview(targetUserID: ProfileID) async throws -> AdminUserDeletionPreview {
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/users/\(targetUserID.rawValue)/delete-preview",
            method: .get,
            requiresAuthentication: true
        )
        struct Payload: Decodable {
            var preview: [String: AdminJSONValue]?
            var error: String?
        }
        let decoded = try? JSONDecoder().decode(Payload.self, from: response.data)
        switch response.statusCode {
        case 200 ... 299:
            guard let preview = decoded?.preview else {
                throw AdminUserDeletionFailure.validation("Could not load deletion preview.")
            }
            return AdminUserDeletionPreview(fields: AdminUserDeletionPreview.format(preview))
        case 401:
            throw AdminUserDeletionFailure.notAuthenticated
        case 403:
            throw AdminUserDeletionFailure.forbidden
        default:
            throw AdminUserDeletionFailure.validation(decoded?.error ?? "Could not load deletion preview.")
        }
    }

    func deleteUser(targetUserID: ProfileID) async throws {
        struct Body: Encodable { var confirmation = "DELETE" }
        struct ErrorPayload: Decodable {
            var error: String?
            var message: String?
            var code: String?
            var step: String?
            var table: String?
        }
        let data = try transport.encodeJSON(Body())
        let response = try await transport.send(
            host: .bff,
            path: "/api/admin/users/\(targetUserID.rawValue)/delete",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        let decoded = try? JSONDecoder().decode(ErrorPayload.self, from: response.data)
        switch response.statusCode {
        case 200 ... 299:
            return
        case 401:
            throw AdminUserDeletionFailure.notAuthenticated
        case 403:
            throw AdminUserDeletionFailure.forbidden
        case 404:
            throw AdminUserDeletionFailure.validation(decoded?.error ?? "User not found.")
        default:
            if decoded?.code == "SELF_DELETE" {
                throw AdminUserDeletionFailure.selfDelete
            }
            if decoded?.code == "ADMIN_TARGET" {
                throw AdminUserDeletionFailure.adminTarget
            }
            throw AdminUserDeletionFailure.server(
                step: decoded?.step,
                table: decoded?.table,
                message: decoded?.message ?? decoded?.error ?? "Delete failed."
            )
        }
    }

    private func insertAudit(
        adminUserID: ProfileID,
        targetUserID: ProfileID,
        action: String,
        details: [String: String]
    ) async throws {
        let row = AdminAuditLogInsert(
            admin_user_id: adminUserID.rawValue,
            target_user_id: targetUserID.rawValue,
            action: action,
            target_type: "user",
            target_id: targetUserID.rawValue,
            details: details.isEmpty ? nil : details
        )
        _ = try await supabase.database.insert(
            row,
            into: "admin_audit_log",
            returning: AdminAuditLogInsertResponse.self
        )
    }

    private func decodeJSONArray(from data: Data) throws -> [[String: Any]] {
        let parsed = try JSONSerialization.jsonObject(with: data)
        if let array = parsed as? [[String: Any]] { return array }
        if let string = parsed as? String,
           let nested = string.data(using: .utf8),
           let array = try JSONSerialization.jsonObject(with: nested) as? [[String: Any]]
        {
            return array
        }
        if let object = parsed as? [String: Any], let array = object["data"] as? [[String: Any]] {
            return array
        }
        return []
    }

    private func decodeJSONObject(from data: Data) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: data)
        if let object = parsed as? [String: Any] { return object }
        if let string = parsed as? String,
           let nested = string.data(using: .utf8),
           let object = try JSONSerialization.jsonObject(with: nested) as? [String: Any]
        {
            return object
        }
        return [:]
    }

    private func parseDirectoryCount(_ row: [String: Any]?) -> Int? {
        guard let row else { return nil }
        for key in ["full_count", "total_count", "fullCount", "totalCount"] {
            if let value = row[key] {
                let n = AdminJSONInt.parse(value)
                if n > 0 { return n }
            }
        }
        return nil
    }
}

// MARK: - Encodable payloads

private nonisolated struct ProfileCommunityVisibilityPatch: Encodable, Sendable {
    var is_hidden_from_community: Bool
}

private nonisolated struct ProfileBanPatch: Encodable, Sendable {
    var is_banned: Bool
    var banned_reason: String?
    var banned_at: String?
    var banned_by: String?
}

private nonisolated struct AdminAuditLogInsert: Encodable, Sendable {
    var admin_user_id: String
    var target_user_id: String
    var action: String
    var target_type: String
    var target_id: String
    var details: [String: String]?
}

private nonisolated struct AdminAuditLogInsertResponse: Decodable, Sendable {
    var id: String?
}

// MARK: - JSON helpers

private nonisolated enum AdminJSONInt {
    static func parse(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? Double, n.isFinite { return Int(n) }
        if let s = value as? String, let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return n
        }
        return 0
    }
}

private nonisolated enum AdminJSONValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .null
        }
    }

    var display: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "—"
        }
    }
}

private nonisolated extension AdminUserSummary {
    init?(json: [String: Any]) {
        guard let idRaw = json["id"] as? String ?? (json["id"] as? UUID)?.uuidString else {
            return nil
        }
        let createdAt = (json["created_at"] as? String).flatMap { AdminISO8601.date(from: $0) }
        self.init(
            id: ProfileID(idRaw),
            username: String(describing: json["username"] ?? ""),
            name: String(describing: json["name"] ?? ""),
            email: String(describing: json["email"] ?? ""),
            avatarURL: json["avatar_url"] as? String,
            createdAt: createdAt,
            isPrivate: json["is_private"] as? Bool ?? false,
            isPro: json["is_pro"] as? Bool ?? false,
            subscriptionStatus: String(describing: json["subscription_status"] ?? ""),
            referralCode: String(describing: json["referral_code"] ?? ""),
            isBanned: json["is_banned"] as? Bool ?? false,
            bannedReason: json["banned_reason"] as? String,
            bannedAt: (json["banned_at"] as? String).flatMap { AdminISO8601.date(from: $0) },
            isBetaTester: json["is_beta_tester"] as? Bool ?? false,
            isHiddenFromCommunity: json["is_hidden_from_community"] as? Bool ?? false
        )
    }
}

private nonisolated extension AdminUserDeletionPreview {
    static func format(_ preview: [String: AdminJSONValue]) -> [(label: String, value: String)] {
        preview.keys.sorted().map { key in
            (key, preview[key]?.display ?? "—")
        }
    }
}

private nonisolated enum AdminISO8601 {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
