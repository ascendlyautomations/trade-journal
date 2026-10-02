import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Web `lib/reelVideo.ts` limits — inspect, delivery-optimize, thumbnail, upload-ready output.
enum MediaVideoPreparation {
    struct Limits: Sendable {
        var maxDurationSeconds: Int
        var maxFinalUploadBytes: Int
        var maxSourceFileBytes: Int
        /// When false, byte ceilings are ignored. Duration and playability still apply.
        var enforcesUploadByteLimits: Bool
        var durationLimitMessage: String
        var sourceTooLargeMessage: String
        var compressionFailedMessage: String
        var preparedTooLargeMessage: String

        nonisolated static let reel = Limits(
            maxDurationSeconds: 90,
            maxFinalUploadBytes: 100 * 1024 * 1024,
            maxSourceFileBytes: 500 * 1024 * 1024,
            enforcesUploadByteLimits: true,
            durationLimitMessage: "Clips must be 90 seconds (1 minute 30 seconds) or less.",
            sourceTooLargeMessage: "This video is too large to process on device. Try a shorter clip.",
            compressionFailedMessage: "Couldn't prepare this video. Try another clip or record again.",
            preparedTooLargeMessage: "Prepared video is still too large. Try a shorter clip."
        )

        /// Stories are eligible by duration. Compression still runs; size is not a rejection rule.
        nonisolated static let story = Limits(
            maxDurationSeconds: StoryMediaDuration.maxVideoDurationSeconds,
            maxFinalUploadBytes: .max,
            maxSourceFileBytes: .max,
            enforcesUploadByteLimits: false,
            durationLimitMessage: StoryMediaDuration.durationExceededMessage,
            sourceTooLargeMessage: "Couldn't prepare this video for your story. Try another clip.",
            compressionFailedMessage: "Couldn't prepare this video for your story. Try another clip.",
            preparedTooLargeMessage: StoryMediaDuration.durationExceededMessage
        )
    }

    nonisolated static let maxDurationSeconds = Limits.reel.maxDurationSeconds
    /// Final optimized upload must remain below this ceiling.
    nonisolated static let maxFileBytes = Limits.reel.maxFinalUploadBytes
    nonisolated static let maxFinalUploadBytes = maxFileBytes
    /// Generous pre-compression source ceiling — large camera originals may compress below final limit.
    nonisolated static let maxSourceFileBytes = Limits.reel.maxSourceFileBytes
    nonisolated static let maxCaptionLength = 2200
    nonisolated static let durationLimitMessage = Limits.reel.durationLimitMessage
    nonisolated static let sourceTooLargeMessage = Limits.reel.sourceTooLargeMessage
    nonisolated static let compressionFailedMessage = Limits.reel.compressionFailedMessage

    private static let acceptedExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let acceptedTypes: Set<UTType> = [.mpeg4Movie, .quickTimeMovie, .movie]

    struct PreparedLocalVideo: Sendable {
        var fileURL: URL
        var contentType: String
        var byteCount: Int
        var durationSeconds: Int
        var thumbnailJPEG: Data?
        var thumbnailImage: UIImage?
    }

    static func isAcceptedVideo(url: URL, contentType: String?) -> Bool {
        let ext = url.pathExtension.lowercased()
        if acceptedExtensions.contains(ext) { return true }
        guard let contentType, let type = UTType(contentType) else { return false }
        return acceptedTypes.contains(where: { type.conforms(to: $0) })
    }

    static func validateSourceFile(
        url: URL,
        contentType: String?,
        limits: Limits = .reel
    ) throws {
        guard isAcceptedVideo(url: url, contentType: contentType) else {
            throw AppError.unknown(message: "Clips support MP4 and MOV videos only.")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        guard size > 0 else {
            throw AppError.unknown(message: "Could not read this video file.")
        }
        if limits.enforcesUploadByteLimits, size > limits.maxSourceFileBytes {
            throw AppError.unknown(message: limits.sourceTooLargeMessage)
        }
    }

    /// Copy → inspect → compress/remux → validate → thumbnail from final delivery asset.
    /// Prefer ``ReelEncodingPipeline/prepareForUpload(from:contentType:onProgress:)`` for reel uploads.
    static func prepareLocalVideo(
        from sourceURL: URL,
        contentType: String?,
        limits: Limits = .reel,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> PreparedLocalVideo {
        try Task.checkCancellation()
        try validateSourceFile(url: sourceURL, contentType: contentType, limits: limits)

        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let stagedSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-source-\(UUID().uuidString).\(ext)")
        try removeIfExists(stagedSource)
        try FileManager.default.copyItem(at: sourceURL, to: stagedSource)

        let sourceAsset = AVURLAsset(url: stagedSource)
        let profile: VideoDeliveryExporter.SourceProfile
        do {
            profile = try await VideoDeliveryExporter.inspectSource(
                asset: sourceAsset,
                fileURL: stagedSource
            )
        } catch {
            try? FileManager.default.removeItem(at: stagedSource)
            throw mapPreparationError(error, fallback: limits.compressionFailedMessage, limits: limits)
        }

        VideoCompressionDiagnostics.logSource(
            duration: profile.durationSeconds,
            fileBytes: profile.fileBytes,
            orientedSize: profile.orientedSize,
            fps: profile.frameRate,
            bitrate: profile.estimatedBitrate,
            codec: profile.videoCodec
        )

        guard profile.durationSeconds <= limits.maxDurationSeconds else {
            try? FileManager.default.removeItem(at: stagedSource)
            throw AppError.unknown(message: limits.durationLimitMessage)
        }

        let assessmentTarget = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(
            profile: profile,
            target: assessmentTarget
        )
        let target = VideoDeliveryExporter.deliveryTargetForExport(
            profile: profile,
            mode: mode,
            decisionReason: reason,
            assessmentTarget: assessmentTarget
        )
        VideoCompressionDiagnostics.logDecision(
            mode: mode.rawValue,
            reason: reason,
            targetFPS: target.outputFrameRate,
            targetVideoBitratePolicy: target.videoBitrate,
            targetRenderSize: target.outputSize,
            exportUsesAVAssetExportSessionPreset: mode == .transcode
        )

        onProgress?(0.05)

        var transcodeMetrics: VideoDeliveryExporter.TranscodeMetrics?
        var deliveryURL: URL?
        do {
            deliveryURL = try await VideoDeliveryExporter.produceDeliveryVideo(
                from: sourceAsset,
                sourceURL: stagedSource,
                profile: profile,
                mode: mode,
                target: target,
                transcodeMetrics: &transcodeMetrics,
                onProgress: { value in
                    onProgress?(0.05 + (value * 0.85))
                }
            )
            if let deliveryURL {
                let deliveryFileInfo = VideoTranscodeFailureDiagnostics.outputFileInfo(at: deliveryURL)
                VideoTranscodeDiagnostics.logExportWithSessionReturned(
                    outputURL: deliveryURL,
                    fileBytes: deliveryFileInfo.bytes
                )
            }
        } catch {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "exportFailed \(error)")
        }

        try Task.checkCancellation()

        let resolved = try await resolvePreparedVideoFile(
            sourceAsset: sourceAsset,
            stagedSource: stagedSource,
            sourceProfile: profile,
            deliveryURL: deliveryURL,
            transcodeMetrics: transcodeMetrics,
            target: target,
            assessmentTarget: assessmentTarget,
            decisionReason: reason,
            limits: limits
        )

        if let deliveryURL, deliveryURL != resolved.fileURL {
            try? FileManager.default.removeItem(at: deliveryURL)
        }
        if stagedSource != resolved.fileURL {
            try? FileManager.default.removeItem(at: stagedSource)
        }

        VideoCompressionDiagnostics.logOutput(
            sourceFPS: profile.frameRate,
            targetFPS: target.outputFrameRate,
            outputFPS: resolved.profile.frameRate,
            sourceDuration: profile.durationSeconds,
            outputDuration: resolved.profile.durationSeconds,
            sourceBytes: profile.fileBytes,
            outputBytes: resolved.profile.fileBytes,
            sourceBitrate: VideoDeliveryExporter.effectiveBitrate(for: profile),
            outputBitrate: resolved.profile.estimatedBitrate,
            outputFrameCount: transcodeMetrics?.outputVideoFrameCount
        )

        onProgress?(0.92)

        let finalAsset = AVURLAsset(url: resolved.fileURL)
        let thumb = await generateThumbnail(
            for: finalAsset,
            durationSeconds: resolved.profile.durationSeconds
        )
        if thumb == nil {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "thumbnailGenerationFailed")
        }

        #if DEBUG
        if let info = await VideoPresentationInfo.load(asset: finalAsset) {
            VideoPresentationProbe.log(surface: .profileThumbnail, info: info)
        }
        #endif

        onProgress?(1)

        return PreparedLocalVideo(
            fileURL: resolved.fileURL,
            contentType: resolved.contentType,
            byteCount: resolved.profile.fileBytes,
            durationSeconds: resolved.profile.durationSeconds,
            thumbnailJPEG: thumb?.jpegData(compressionQuality: 0.9),
            thumbnailImage: thumb
        )
    }

    static func formatDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    static func mimeType(forExtension ext: String, fallback: String?) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default:
            if let fallback, !fallback.isEmpty { return fallback }
            return "video/mp4"
        }
    }

    nonisolated static func cleanupTemporaryFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private struct ResolvedPreparedVideoFile: Sendable {
        var fileURL: URL
        var profile: VideoDeliveryExporter.SourceProfile
        var contentType: String
    }

    /// Compressed delivery when optimization checks pass; otherwise the staged import copy (or remux).
    private static func resolvePreparedVideoFile(
        sourceAsset: AVURLAsset,
        stagedSource: URL,
        sourceProfile: VideoDeliveryExporter.SourceProfile,
        deliveryURL: URL?,
        transcodeMetrics: VideoDeliveryExporter.TranscodeMetrics?,
        target: VideoDeliveryExporter.DeliveryTarget,
        assessmentTarget: VideoDeliveryExporter.DeliveryTarget,
        decisionReason: String,
        limits: Limits
    ) async throws -> ResolvedPreparedVideoFile {
        if let deliveryURL,
           let compressed = try await acceptCompressedDeliveryIfEligible(
            deliveryURL: deliveryURL,
            sourceProfile: sourceProfile,
            transcodeMetrics: transcodeMetrics,
            target: target,
            assessmentTarget: assessmentTarget,
            decisionReason: decisionReason,
            limits: limits
           )
        {
            return compressed
        }
        return try await fallbackToImportedSource(
            sourceAsset: sourceAsset,
            stagedSource: stagedSource,
            sourceProfile: sourceProfile,
            target: target,
            limits: limits
        )
    }

    private static func acceptCompressedDeliveryIfEligible(
        deliveryURL: URL,
        sourceProfile: VideoDeliveryExporter.SourceProfile,
        transcodeMetrics: VideoDeliveryExporter.TranscodeMetrics?,
        target: VideoDeliveryExporter.DeliveryTarget,
        assessmentTarget: VideoDeliveryExporter.DeliveryTarget,
        decisionReason: String,
        limits: Limits
    ) async throws -> ResolvedPreparedVideoFile? {
        VideoPrepareDiagnostics.logValidationStarted(output: deliveryURL.lastPathComponent)
        let deliveryAsset = AVURLAsset(url: deliveryURL)
        let outputProfile: VideoDeliveryExporter.SourceProfile
        do {
            outputProfile = try await VideoDeliveryExporter.validateOutput(
                asset: deliveryAsset,
                fileURL: deliveryURL,
                expectedDurationSeconds: sourceProfile.durationSeconds,
                sourceFrameRate: sourceProfile.frameRate,
                targetFrameRate: target.outputFrameRate,
                transcodeMetrics: transcodeMetrics
            )
            VideoPrepareDiagnostics.logValidationCompleted(
                bytes: outputProfile.fileBytes,
                durationSeconds: outputProfile.durationSeconds,
                fps: outputProfile.frameRate
            )
        } catch {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "compressedValidationFailed")
            return nil
        }

        if limits.enforcesUploadByteLimits, outputProfile.fileBytes > limits.maxFinalUploadBytes {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "compressedExceedsUploadLimit")
            return nil
        }

        if outputProfile.fileBytes >= sourceProfile.fileBytes,
           VideoDeliveryExporter.isDeliveryCompatibleVideo(profile: sourceProfile, target: assessmentTarget)
        {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "compressedNotSmallerThanCompatibleSource")
            return nil
        }

        VideoPrepareDiagnostics.logTranscodeEffectivenessValidationStarted()
        do {
            try VideoDeliveryExporter.validateTranscodeEffectiveness(
                source: sourceProfile,
                output: outputProfile,
                decisionReason: decisionReason
            )
            VideoPrepareDiagnostics.logTranscodeEffectivenessValidationCompleted()
        } catch {
            VideoPrepareDiagnostics.logTranscodeEffectivenessValidationFailed(reason: "\(error)")
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "transcodeEffectivenessFailed")
            return nil
        }

        return ResolvedPreparedVideoFile(
            fileURL: deliveryURL,
            profile: outputProfile,
            contentType: "video/mp4"
        )
    }

    private static func fallbackToImportedSource(
        sourceAsset: AVURLAsset,
        stagedSource: URL,
        sourceProfile: VideoDeliveryExporter.SourceProfile,
        target: VideoDeliveryExporter.DeliveryTarget,
        limits: Limits
    ) async throws -> ResolvedPreparedVideoFile {
        guard isPlayableSourceProfile(sourceProfile, limits: limits) else {
            throw AppError.unknown(message: limits.compressionFailedMessage)
        }
        if limits.enforcesUploadByteLimits, sourceProfile.fileBytes > limits.maxFinalUploadBytes {
            throw AppError.unknown(message: limits.preparedTooLargeMessage)
        }

        if sourceProfile.isMP4Container {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "usingOriginalMP4")
            return ResolvedPreparedVideoFile(
                fileURL: stagedSource,
                profile: sourceProfile,
                contentType: mimeType(
                    forExtension: stagedSource.pathExtension,
                    fallback: "video/mp4"
                )
            )
        }

        var remuxMetrics: VideoDeliveryExporter.TranscodeMetrics?
        do {
            let remuxed = try await VideoDeliveryExporter.produceDeliveryVideo(
                from: sourceAsset,
                sourceURL: stagedSource,
                profile: sourceProfile,
                mode: .remux,
                target: target,
                transcodeMetrics: &remuxMetrics,
                onProgress: nil
            )
            let remuxProfile = try await VideoDeliveryExporter.inspectSource(
                asset: AVURLAsset(url: remuxed),
                fileURL: remuxed
            )
            if limits.enforcesUploadByteLimits, remuxProfile.fileBytes > limits.maxFinalUploadBytes {
                try? FileManager.default.removeItem(at: remuxed)
                throw AppError.unknown(message: limits.preparedTooLargeMessage)
            }
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "usingRemuxedOriginal")
            return ResolvedPreparedVideoFile(
                fileURL: remuxed,
                profile: remuxProfile,
                contentType: "video/mp4"
            )
        } catch let app as AppError {
            throw app
        } catch {
            VideoPrepareDiagnostics.logOptimizationFallback(reason: "remuxFailedUsingOriginalContainer")
            return ResolvedPreparedVideoFile(
                fileURL: stagedSource,
                profile: sourceProfile,
                contentType: mimeType(
                    forExtension: stagedSource.pathExtension,
                    fallback: "video/quicktime"
                )
            )
        }
    }

    private static func isPlayableSourceProfile(
        _ profile: VideoDeliveryExporter.SourceProfile,
        limits: Limits
    ) -> Bool {
        profile.fileBytes > 0
            && profile.durationSeconds > 0
            && profile.durationSeconds <= limits.maxDurationSeconds
            && profile.orientedSize.width > 0
            && profile.orientedSize.height > 0
    }

    private static func generateThumbnail(for asset: AVURLAsset, durationSeconds: Int) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let candidates: [Double] = [0.1, 0.5, 1.0, max(0.1, Double(durationSeconds) * 0.15)]
        for seconds in candidates {
            try? Task.checkCancellation()
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                return UIImage(cgImage: cg)
            }
        }
        return nil
    }

    private static func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func mapPreparationError(
        _ error: Error,
        fallback: String,
        limits: Limits = .reel
    ) -> AppError {
        if Task.isCancelled {
            return AppError.unknown(message: "Video preparation was cancelled.")
        }
        if let failure = error as? VideoPreparationFailure {
            switch failure {
            case .durationExceeded:
                return AppError.unknown(message: limits.durationLimitMessage)
            case .sourceTooLarge:
                return AppError.unknown(message: limits.sourceTooLargeMessage)
            case .cancelled:
                return AppError.unknown(message: "Video preparation was cancelled.")
            case .unsupportedVideo:
                return AppError.unknown(message: "Clips support MP4 and MOV videos only.")
            default:
                return AppError.unknown(message: fallback)
            }
        }
        if let app = error as? AppError {
            return app
        }
        return AppError.unknown(message: fallback)
    }
}
