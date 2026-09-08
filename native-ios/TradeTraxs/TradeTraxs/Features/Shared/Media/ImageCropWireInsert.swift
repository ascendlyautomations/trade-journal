import Foundation

/// Shared insert fallback when `image_crop` jsonb columns are not deployed yet.
enum ImageCropWireInsert {
    static let migrationHint = "Apply supabase/migrations/20260907160000_content_image_crop.sql"

    /// Feed post row created when a trade is shared publicly (`posts` insert).
    struct TradePublicPostInsertBody: Encodable, Sendable {
        var user_id: String
        var trade_id: String
        var image_url: String?
        var image_crop: JSONValue?
        var pnl: Double?
        var rr: Double?
        var caption: String
        var includeImageCropKey: Bool

        enum CodingKeys: String, CodingKey {
            case user_id, trade_id, image_url, image_crop, pnl, rr, caption
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(trade_id, forKey: .trade_id)
            try container.encodeIfPresent(image_url, forKey: .image_url)
            if includeImageCropKey {
                try container.encodeIfPresent(image_crop, forKey: .image_crop)
            }
            try container.encodeIfPresent(pnl, forKey: .pnl)
            try container.encodeIfPresent(rr, forKey: .rr)
            try container.encode(caption, forKey: .caption)
        }
    }

    @discardableResult
    static func insertWallPost(
        supabase: SupabaseInfrastructure,
        body: ProfileWallPostInsertBody
    ) async throws -> FeedDTO.ProfileWallPost {
        do {
            PostPublishProbe.logDatabaseInsertStarted(
                table: "profile_posts",
                payloadKeys: wallPostPayloadKeys(body)
            )
            let dto: FeedDTO.ProfileWallPost = try await supabase.database.insert(
                body,
                into: "profile_posts",
                returning: FeedDTO.ProfileWallPost.self
            )
            PostPublishProbe.logDatabaseInsertSucceeded(table: "profile_posts")
            PostPublishProbe.logResponseDecodeSucceeded(table: "profile_posts")
            return dto
        } catch {
            if isResponseDecodeFailure(error) {
                PostPublishProbe.logFailed(stage: .responseDecode, error: error)
                PostPublishProbe.logNote(
                    "profile_posts insert may have succeeded server-side — avoid blind republish retries"
                )
                throw error
            }
            guard body.includeImageCropKey,
                  body.image_crop != nil,
                  ContentImagePresentationCodec.isMissingImageCropColumnError(error)
            else {
                PostPublishProbe.logFailed(stage: .databaseInsert, error: error)
                throw error
            }
            PostPublishProbe.logNote(
                "profile_posts.image_crop column missing — retrying without image_crop. \(migrationHint)"
            )
            var fallback = body
            fallback.includeImageCropKey = false
            PostPublishProbe.logDatabaseInsertStarted(
                table: "profile_posts",
                payloadKeys: wallPostPayloadKeys(fallback)
            )
            let dto: FeedDTO.ProfileWallPost = try await supabase.database.insert(
                fallback,
                into: "profile_posts",
                returning: FeedDTO.ProfileWallPost.self
            )
            PostPublishProbe.logDatabaseInsertSucceeded(table: "profile_posts")
            PostPublishProbe.logResponseDecodeSucceeded(table: "profile_posts")
            return dto
        }
    }

    private static func isResponseDecodeFailure(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        if let app = error as? AppError,
           case .unknown(let message) = app,
           message.localizedCaseInsensitiveContains("decode") {
            return true
        }
        return false
    }

    private static func wallPostPayloadKeys(_ body: ProfileWallPostInsertBody) -> [String] {
        var keys = ["user_id", "content"]
        if body.image_url != nil { keys.append("image_url") }
        if body.includeImageCropKey { keys.append("image_crop") }
        return keys
    }

    @discardableResult
    static func insertAchievement(
        supabase: SupabaseInfrastructure,
        body: AchievementInsertBody
    ) async throws -> AchievementDTO.Achievement {
        do {
            PostPublishProbe.logDatabaseInsertStarted(table: "achievements", payloadKeys: ["achievements"])
            let dto: AchievementDTO.Achievement = try await supabase.database.insert(
                body,
                into: "achievements",
                returning: AchievementDTO.Achievement.self
            )
            PostPublishProbe.logDatabaseInsertSucceeded(table: "achievements")
            return dto
        } catch {
            guard body.includeImageCropKey,
                  body.image_crop != nil,
                  ContentImagePresentationCodec.isMissingImageCropColumnError(error)
            else {
                PostPublishProbe.logFailed(stage: .databaseInsert, error: error)
                throw error
            }
            PostPublishProbe.logNote(
                "achievements.image_crop column missing — retrying without image_crop. \(migrationHint)"
            )
            var fallback = body
            fallback.includeImageCropKey = false
            let dto: AchievementDTO.Achievement = try await supabase.database.insert(
                fallback,
                into: "achievements",
                returning: AchievementDTO.Achievement.self
            )
            PostPublishProbe.logDatabaseInsertSucceeded(table: "achievements")
            return dto
        }
    }

    static func insertPublicTradePost(
        supabase: SupabaseInfrastructure,
        body: TradePublicPostInsertBody
    ) async throws {
        do {
            PostPublishProbe.logDatabaseInsertStarted(table: "posts", payloadKeys: ["posts"])
            try await supabase.database.insert(body, into: "posts")
            PostPublishProbe.logDatabaseInsertSucceeded(table: "posts")
        } catch {
            guard body.includeImageCropKey,
                  body.image_crop != nil,
                  ContentImagePresentationCodec.isMissingImageCropColumnError(error)
            else {
                PostPublishProbe.logFailed(stage: .databaseInsert, error: error)
                throw error
            }
            PostPublishProbe.logNote(
                "posts.image_crop column missing — retrying without image_crop. \(migrationHint)"
            )
            var fallback = body
            fallback.includeImageCropKey = false
            try await supabase.database.insert(fallback, into: "posts")
            PostPublishProbe.logDatabaseInsertSucceeded(table: "posts")
        }
    }

    static func insertTradeRow(
        supabase: SupabaseInfrastructure,
        body: TradeDTO.InsertBody
    ) async throws -> TradeDTO.Trade {
        do {
            PostPublishProbe.logDatabaseInsertStarted(table: "trades", payloadKeys: ["trades"])
            let dto: TradeDTO.Trade = try await supabase.database.insert(
                body,
                into: "trades",
                returning: TradeDTO.Trade.self
            )
            PostPublishProbe.logDatabaseInsertSucceeded(table: "trades")
            return dto
        } catch {
            guard body.image_crop != nil,
                  ContentImagePresentationCodec.isMissingImageCropColumnError(error)
            else {
                PostPublishProbe.logFailed(stage: .databaseInsert, error: error)
                throw error
            }
            PostPublishProbe.logNote(
                "trades.image_crop column missing — retrying without image_crop. \(migrationHint)"
            )
            var fallback = body
            fallback.image_crop = nil
            let dto: TradeDTO.Trade = try await supabase.database.insert(
                fallback,
                into: "trades",
                returning: TradeDTO.Trade.self
            )
            PostPublishProbe.logDatabaseInsertSucceeded(table: "trades")
            return dto
        }
    }
}
