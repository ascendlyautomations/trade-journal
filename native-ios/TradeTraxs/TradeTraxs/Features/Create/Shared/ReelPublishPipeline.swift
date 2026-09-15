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
    /// Trade-linked: visibility from trade public flag; reel caption is independent of trade description.
    /// Linked-trade uniqueness must be validated by the caller before invoking this method.
    static func publish(
        publishID: String,
        draft: ReelDraft,
        authorID: ProfileID,
        tradeID: TradeID?,
        tradeIsPublic: Bool?,
        feed: any FeedRepository,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Reel {
        ReelPublishDiagnostics.logPreparationCompleted(
            publishID: publishID,
            byteCount: draft.byteCount,
            durationSeconds: draft.durationSeconds
        )

        onProgress?(0.1)
        let uploaded: UploadedMedia
        do {
            uploaded = try await uploadMedia(
                publishID: publishID,
                draft: draft,
                authorID: authorID,
                uploadService: uploadService,
                objectStorage: objectStorage,
                onProgress: onProgress
            )
        } catch {
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "upload",
                error: error
            )
            throw error
        }
        onProgress?(0.9)

        let visibility: ContentVisibility = {
            if tradeID != nil {
                return (tradeIsPublic == true) ? .public : .private
            }
            return .public
        }()

        let caption: String? = Self.normalizedCaption(draft.caption)

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

        ReelPublishDiagnostics.logDatabaseInsertStarted(publishID: publishID)
        do {
            let inserted = try await feed.createReel(provisional)
            ReelPublishDiagnostics.logDatabaseInsertCompleted(
                publishID: publishID,
                reelID: inserted.id.rawValue
            )

            let verified = try await feed.reel(id: inserted.id)
            guard verified.reel.authorProfileID == authorID else {
                throw AppError.unknown(message: "Published clip could not be verified.")
            }

            onProgress?(1)
            ReelPublishDiagnostics.logCompleted(publishID: publishID)
            return verified.reel
        } catch {
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "databaseInsert",
                error: error
            )
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

    private static let reelVideoCacheControl = "31536000"

    nonisolated static func normalizedCaption(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(MediaVideoPreparation.maxCaptionLength))
    }

    private static func uploadMedia(
        publishID: String,
        draft: ReelDraft,
        authorID: ProfileID,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onProgress: ((Double) -> Void)?
    ) async throws -> UploadedMedia {
        let resolved: ReelEncodingPipeline.ResolvedUploadVideo
        do {
            resolved = try await ReelEncodingPipeline.resolveUploadVideo(draft: draft) { value in
                onProgress?(0.05 + value * 0.15)
            }
        } catch {
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "encode",
                error: error
            )
            throw error
        }

        defer {
            ReelEncodingPipeline.cleanupEphemeralFiles(
                resolved.ephemeralURLs,
                preserving: Set([draft.localVideoURL, draft.ownedSourceURL].compactMap { $0 })
            )
        }

        let videoData = try Data(contentsOf: resolved.fileURL, options: [.mappedIfSafe])
        guard videoData.count <= MediaVideoPreparation.maxFinalUploadBytes else {
            throw AppError.unknown(message: "Videos must be 100 MB or smaller.")
        }

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let videoPath = "\(authorID.rawValue)/videos/\(stamp)-clip.mp4"

        onProgress?(0.25)
        ReelPublishDiagnostics.logVideoUploadStarted(
            publishID: publishID,
            objectIdentity: videoPath,
            byteCount: videoData.count
        )
        let videoRef: MediaReference
        do {
            videoRef = try await uploadService.upload(
                UploadRequest(
                    bucket: StorageBucket.reels.rawValue,
                    path: videoPath,
                    data: videoData,
                    contentType: "video/mp4",
                    purpose: nil,
                    cacheControl: reelVideoCacheControl
                )
            )
            ReelPublishDiagnostics.logVideoUploadCompleted(
                publishID: publishID,
                statusCode: 200
            )
        } catch {
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "uploadVideo",
                error: error
            )
            throw error
        }
        let videoURL = objectStorage.publicURL(
            bucket: StorageBucket.reels.rawValue,
            path: videoRef.id
        )?.absoluteString ?? videoRef.id

        onProgress?(0.7)
        var thumbPath: String?
        var thumbURL: String?
        if let jpeg = draft.thumbnailJPEG {
            let path = "\(authorID.rawValue)/thumbnails/\(stamp)-thumb.jpg"
            ReelPublishDiagnostics.logThumbnailUploadStarted(
                publishID: publishID,
                objectIdentity: path
            )
            let ref = try await uploadService.upload(
                UploadRequest(
                    bucket: StorageBucket.reels.rawValue,
                    path: path,
                    data: jpeg,
                    contentType: "image/jpeg",
                    purpose: .reelThumbnail
                )
            )
            ReelPublishDiagnostics.logThumbnailUploadCompleted(
                publishID: publishID,
                statusCode: 200
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
