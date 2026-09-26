import Foundation

/// How the upload pipeline should treat `localVideoURL` (prepared delivery vs raw source).
enum ReelUploadVideoAssetState: String, Sendable, Equatable {
    case sourceMedia
    case preparedDelivery
}

struct ReelDraftSnapshot: Sendable, Equatable {
    var selectionID: String
    var ownedSourceURL: URL?
    var localVideoURL: URL
    var contentType: String
    var byteCount: Int
    var durationSeconds: Int
    var thumbnailJPEG: Data?
    var caption: String
    var linkedTradeID: TradeID?
    var videoAssetState: ReelUploadVideoAssetState

    init(
        selectionID: String,
        ownedSourceURL: URL?,
        localVideoURL: URL,
        contentType: String,
        byteCount: Int,
        durationSeconds: Int,
        thumbnailJPEG: Data?,
        caption: String,
        linkedTradeID: TradeID?,
        videoAssetState: ReelUploadVideoAssetState = .sourceMedia
    ) {
        self.selectionID = selectionID
        self.ownedSourceURL = ownedSourceURL
        self.localVideoURL = localVideoURL
        self.contentType = contentType
        self.byteCount = byteCount
        self.durationSeconds = durationSeconds
        self.thumbnailJPEG = thumbnailJPEG
        self.caption = caption
        self.linkedTradeID = linkedTradeID
        self.videoAssetState = videoAssetState
    }

    init(draft: ReelDraft, captionOverride: String?) {
        self.init(
            selectionID: draft.selectionID,
            ownedSourceURL: draft.ownedSourceURL,
            localVideoURL: draft.localVideoURL,
            contentType: draft.contentType,
            byteCount: draft.byteCount,
            durationSeconds: draft.durationSeconds,
            thumbnailJPEG: draft.thumbnailJPEG,
            caption: captionOverride ?? draft.caption,
            linkedTradeID: draft.linkedTradeID,
            videoAssetState: draft.videoAssetState
        )
    }

    var asDraft: ReelDraft {
        ReelDraft(
            selectionID: selectionID,
            ownedSourceURL: ownedSourceURL,
            localVideoURL: localVideoURL,
            videoAssetState: videoAssetState,
            contentType: contentType,
            byteCount: byteCount,
            durationSeconds: durationSeconds,
            thumbnailJPEG: thumbnailJPEG,
            thumbnailPreview: nil,
            caption: caption,
            linkedTradeID: linkedTradeID,
            linkedTradeSummary: nil
        )
    }
}

struct ReelUploadSpec: Sendable {
    var publishID: String
    var snapshot: ReelDraftSnapshot
    var authorID: ProfileID
    var tradeIsPublic: Bool?
    /// When set, upload waits for this in-flight background preparation (no second transcode).
    var preparationTaskID: String?
}

struct PostUploadSpec: Sendable {
    var authorID: ProfileID
    var bodyText: String
    var imageData: Data?
}

struct PostUploadCheckpoint: Sendable, Equatable {
    var imageStoragePath: String?
    var uploadedImagePublicURL: String?
}

struct StoryUploadSpec: Sendable {
    var authorID: ProfileID
    var imageData: Data
    var contentType: String
    var originalFileName: String?
    /// Deterministic object key — filled by ``GlobalUploadCoordinator`` at enqueue.
    var storagePath: String = ""
}

struct StoryUploadCheckpoint: Sendable, Equatable {
    var uploadedImagePublicURL: String?
}

struct AchievementUploadCheckpoint: Sendable, Equatable {
    var uploadedImagePublicURL: String?
    var uploadedImageStoragePath: String?
    var savedAchievementID: AchievementID?
}

struct AchievementUploadSpec: Sendable {
    var jobID: String
    var authorID: ProfileID
    var kind: AchievementKind
    var title: String
    var description: String?
    var payout: Decimal?
    var payoutText: String?
    var firm: String?
    var accountID: TradingAccountID?
    var imageData: Data?
    var isPublic: Bool
    var achievedAt: Date
}

enum TradeSaveUploadMode: Sendable, Equatable {
    case create
    case edit(tradeID: TradeID)
}

struct TradeSaveUploadCheckpoint: Sendable, Equatable {
    var uploadedScreenshotPublicURL: String?
    var uploadedScreenshotStoragePath: String?
    var savedTradeID: TradeID?
    var clipAttached: Bool
    /// Existing reel selected at enqueue — PATCH `reels.trade_id` succeeded.
    var reelLinked: Bool
    var publicFeedPostCompleted: Bool
    var reelVideoPublicURL: String?
    var reelVideoStoragePath: String?
    var reelThumbnailPublicURL: String?
    var reelThumbnailStoragePath: String?
    var linkedExistingReelID: ReelID?
}

struct TradeSaveUploadSpec: Sendable {
    var jobID: String
    var authorID: ProfileID
    var mode: TradeSaveUploadMode
    var draft: TradeDraft
    var screenshotData: Data?
    var removeExistingScreenshot: Bool
    var existingImageURL: String?
    var reelSnapshot: ReelDraftSnapshot?
    var linkedReelID: ReelID?
    var tradeIsPublic: Bool
    var lastAccountID: TradingAccountID?
}

/// Services captured at enqueue time (MainActor); not passed across arbitrary actors.
@MainActor
struct GlobalUploadServices {
    var feed: any FeedRepository
    var profiles: (any ProfileRepository)?
    var trades: (any TradeRepository)?
    var achievements: (any AchievementRepository)?
    var uploadService: any UploadService
    var objectStorage: any ObjectStorageProviding
    var detailCache: DetailPresentationCache
}

extension DataEnvironment {
    @MainActor
    func globalUploadServices() -> GlobalUploadServices {
        GlobalUploadServices(
            feed: feed,
            profiles: profiles,
            trades: trades,
            achievements: achievements,
            uploadService: uploadService,
            objectStorage: objectStorage,
            detailCache: detailCache
        )
    }
}
