import Foundation
import UIKit

/// Shared upload + insert path matching web `publishReel` / `publishTradeReel`.
enum ReelPublishPipeline {
    struct UploadedMedia {
        var videoStoragePath: String
        var videoPublicURL: String
        var thumbnailStoragePath: String?
        var thumbnailPublicURL: String?
    }

    /// Uploads video (+ optional thumb) then inserts `reels`.
    /// Trade-linked: `caption` forced nil; visibility from trade public flag.
    static func publish(
        draft: ReelDraft,
        authorID: ProfileID,
        tradeID: TradeID?,
        tradeIsPublic: Bool?,
        feed: any FeedRepository,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Reel {
        if let tradeID {
            if try await feed.tradeHasAttachedReel(tradeID) {
                throw AppError.domain(.conflict(message: "This trade already has a clip attached."))
            }
        }

        onProgress?(0.1)
        let uploaded = try await uploadMedia(
            draft: draft,
            authorID: authorID,
            uploadService: uploadService,
            objectStorage: objectStorage,
            onProgress: onProgress
        )
        onProgress?(0.9)

        let visibility: ContentVisibility = {
            if tradeID != nil {
                return (tradeIsPublic == true) ? .public : .private
            }
            return .public
        }()

        // DB: trade_id IS NULL OR caption IS NULL
        let caption: String? = {
            guard tradeID == nil else { return nil }
            let trimmed = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(MediaVideoPreparation.maxCaptionLength))
        }()

        let thumbURL = uploaded.thumbnailPublicURL ?? uploaded.videoPublicURL
        let provisional = Reel(
            id: ReelID(UUID().uuidString),
            authorProfileID: authorID,
            video: MediaReference(id: uploaded.videoPublicURL, kind: .video, altText: nil),
            thumbnail: MediaReference(id: thumbURL, kind: .image, altText: nil),
            caption: caption,
            visibility: visibility,
            linkedTradeID: tradeID,
            durationSeconds: draft.durationSeconds,
            createdAt: .now
        )

        do {
            let created = try await feed.createReel(provisional)
            onProgress?(1)
            return created
        } catch {
            // Best-effort orphan cleanup (web does not; we try).
            try? await objectStorage.delete(
                bucket: StorageBucket.reels.rawValue,
                path: uploaded.videoStoragePath
            )
            if let thumbPath = uploaded.thumbnailStoragePath {
                try? await objectStorage.delete(
                    bucket: StorageBucket.reels.rawValue,
                    path: thumbPath
                )
            }
            throw error
        }
    }

    private static func uploadMedia(
        draft: ReelDraft,
        authorID: ProfileID,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onProgress: ((Double) -> Void)?
    ) async throws -> UploadedMedia {
        let videoData = try Data(contentsOf: draft.localVideoURL)
        guard videoData.count <= MediaVideoPreparation.maxFileBytes else {
            throw AppError.unknown(message: "Videos must be 100 MB or smaller.")
        }

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = draft.localVideoURL.pathExtension.isEmpty ? "mov" : draft.localVideoURL.pathExtension
        let videoPath = "\(authorID.rawValue)/videos/\(stamp)-clip.\(ext)"

        onProgress?(0.25)
        let videoRef = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.reels.rawValue,
                path: videoPath,
                data: videoData,
                contentType: draft.contentType,
                purpose: nil
            )
        )
        let videoURL = objectStorage.publicURL(
            bucket: StorageBucket.reels.rawValue,
            path: videoRef.id
        )?.absoluteString ?? videoRef.id

        onProgress?(0.7)
        var thumbPath: String?
        var thumbURL: String?
        if let jpeg = draft.thumbnailJPEG {
            let path = "\(authorID.rawValue)/thumbnails/\(stamp)-thumb.jpg"
            let ref = try await uploadService.upload(
                UploadRequest(
                    bucket: StorageBucket.reels.rawValue,
                    path: path,
                    data: jpeg,
                    contentType: "image/jpeg",
                    purpose: .reelThumbnail
                )
            )
            thumbPath = ref.id
            thumbURL = objectStorage.publicURL(
                bucket: StorageBucket.reels.rawValue,
                path: ref.id
            )?.absoluteString ?? ref.id
        }

        return UploadedMedia(
            videoStoragePath: videoRef.id,
            videoPublicURL: videoURL,
            thumbnailStoragePath: thumbPath,
            thumbnailPublicURL: thumbURL
        )
    }
}
