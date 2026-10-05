import Foundation

nonisolated struct DefaultContentDraftRepository: ContentDraftRepository {
    private let database: any SupabaseDatabaseExecuting
    private let session: any SessionProviding
    private let objectStorage: any ObjectStorageProviding

    init(
        database: any SupabaseDatabaseExecuting,
        session: any SessionProviding,
        objectStorage: any ObjectStorageProviding
    ) {
        self.database = database
        self.session = session
        self.objectStorage = objectStorage
    }

    func listDrafts() async throws -> [ContentDraft] {
        let userID = try await requireUserID()
        let rows: [ContentDraftRowDTO] = try await database.select(
            ContentDraftRowDTO.self,
            from: Self.table,
            query: [
                SupabaseQuery.select(Self.columns),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.order("updated_at", ascending: false),
                SupabaseQuery.limit(200),
            ]
        )
        return rows.compactMap(ContentDraftRowMapping.draft(from:))
    }

    func saveDraft(_ draft: ContentDraft) async throws -> ContentDraft {
        let userID = try await requireUserID()
        let body = ContentDraftWriteDTO(
            id: draft.id.uuidString,
            user_id: userID.rawValue,
            draft_type: draft.type.rawValue,
            payload: draft.payload,
            updated_at: ContentDraftDateCodec.string(from: Date())
        )
        let row: ContentDraftRowDTO = try await database.upsert(
            body,
            into: Self.table,
            onConflict: "id",
            returning: ContentDraftRowDTO.self,
            select: Self.columns
        )
        guard let saved = ContentDraftRowMapping.draft(from: row) else {
            throw AppError.unknown(message: "Couldn't read the saved draft.")
        }
        return saved
    }

    func deleteDraft(id: UUID) async throws {
        let userID = try await requireUserID()
        let rows: [ContentDraftRowDTO] = try await database.select(
            ContentDraftRowDTO.self,
            from: Self.table,
            query: [
                SupabaseQuery.select(Self.columns),
                SupabaseQuery.eq("id", id.uuidString),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.limit(1),
            ]
        )
        if let row = rows.first, let draft = ContentDraftRowMapping.draft(from: row) {
            await deleteDraftMedia(paths: draft.payload.mediaPaths)
        }
        try await database.delete(
            from: Self.table,
            query: [
                SupabaseQuery.eq("id", id.uuidString),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
    }

    func uploadDraftImage(draftID: UUID, data: Data) async throws -> String {
        let userID = try await requireUserID()
        let path = "\(userID.rawValue)/\(draftID.uuidString)/image.jpg"
        let stored = try await objectStorage.upload(
            bucket: StorageBucket.draftMedia.rawValue,
            path: path,
            data: data,
            contentType: "image/jpeg",
            cacheControl: "private, max-age=0"
        )
        return stored.isEmpty ? path : stored
    }

    func uploadDraftVideo(draftID: UUID, fileURL: URL, contentType: String) async throws -> String {
        let userID = try await requireUserID()
        let fileName = contentType == "video/quicktime" ? "video.mov" : "video.mp4"
        let allowed = contentType == "video/quicktime" ? contentType : "video/mp4"
        let path = "\(userID.rawValue)/\(draftID.uuidString)/\(fileName)"
        let stored = try await objectStorage.upload(
            bucket: StorageBucket.draftMedia.rawValue,
            path: path,
            fileURL: fileURL,
            contentType: allowed,
            cacheControl: "private, max-age=0"
        )
        return stored.isEmpty ? path : stored
    }

    func deleteDraftMedia(paths: [String]) async {
        guard let userID = await session.currentUserID else { return }
        let prefix = "\(userID.rawValue)/"
        for path in paths where path.hasPrefix(prefix) && !path.contains("..") {
            try? await objectStorage.delete(bucket: StorageBucket.draftMedia.rawValue, path: path)
        }
    }

    private func requireUserID() async throws -> UserID {
        guard let userID = await session.currentUserID else {
            throw AppError.authentication(.sessionMissing)
        }
        return userID
    }

    private static let table = "content_drafts"
    private static let columns = "id,user_id,draft_type,payload,created_at,updated_at"
}

nonisolated struct ContentDraftRowDTO: Decodable, Sendable {
    var id: String
    var user_id: String
    var draft_type: String
    var payload: ContentDraftPayload
    var created_at: String
    var updated_at: String
}

nonisolated struct ContentDraftWriteDTO: Encodable, Sendable {
    var id: String
    var user_id: String
    var draft_type: String
    var payload: ContentDraftPayload
    var updated_at: String
}

nonisolated enum ContentDraftRowMapping {
    static func draft(from row: ContentDraftRowDTO) -> ContentDraft? {
        guard let id = UUID(uuidString: row.id),
              let type = ContentDraftType(rawValue: row.draft_type),
              let createdAt = ContentDraftDateCodec.date(from: row.created_at),
              let updatedAt = ContentDraftDateCodec.date(from: row.updated_at)
        else { return nil }
        return ContentDraft(
            id: id,
            userID: UserID(row.user_id),
            type: type,
            payload: row.payload,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension DataEnvironment {
    func contentDraftRepository() -> any ContentDraftRepository {
        DefaultContentDraftRepository(
            database: supabase.database,
            session: session,
            objectStorage: objectStorage
        )
    }
}
