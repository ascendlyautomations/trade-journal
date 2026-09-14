import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Web `lib/reelVideo.ts` limits — inspect, delivery-optimize, thumbnail, upload-ready output.
enum MediaVideoPreparation {
    static let maxDurationSeconds = 90
    /// Final optimized upload must remain below this ceiling.
    static let maxFileBytes = 100 * 1024 * 1024
    static let maxFinalUploadBytes = maxFileBytes
    /// Generous pre-compression source ceiling — large camera originals may compress below final limit.
    static let maxSourceFileBytes = 500 * 1024 * 1024
    static let maxCaptionLength = 2200
    static let durationLimitMessage = "Clips must be 90 seconds (1 minute 30 seconds) or less."
    static let sourceTooLargeMessage = "This video is too large to process on device. Try a shorter clip."
    static let compressionFailedMessage = "Couldn't prepare this video. Try another clip or record again."

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

    static func validateSourceFile(url: URL, contentType: String?) throws {
        guard isAcceptedVideo(url: url, contentType: contentType) else {
            throw AppError.unknown(message: "Clips support MP4 and MOV videos only.")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        guard size > 0 else {
            throw AppError.unknown(message: "Could not read this video file.")
        }
        guard size <= maxSourceFileBytes else {
            throw AppError.unknown(message: sourceTooLargeMessage)
        }
    }

    /// Copy → inspect → compress/remux → validate → thumbnail from final delivery asset.
    /// Prefer ``ReelEncodingPipeline/prepareForUpload(from:contentType:onProgress:)`` for reel uploads.
    static func prepareLocalVideo(
        from sourceURL: URL,
        contentType: String?,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> PreparedLocalVideo {
        try Task.checkCancellation()
        try validateSourceFile(url: sourceURL, contentType: contentType)

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
            throw mapPreparationError(error, fallback: compressionFailedMessage)
        }

        VideoCompressionDiagnostics.logSource(
            duration: profile.durationSeconds,
            fileBytes: profile.fileBytes,
            orientedSize: profile.orientedSize,
            fps: profile.frameRate,
            bitrate: profile.estimatedBitrate,
            codec: profile.videoCodec
        )

        guard profile.durationSeconds <= maxDurationSeconds else {
            try? FileManager.default.removeItem(at: stagedSource)
            throw AppError.unknown(message: durationLimitMessage)
        }

        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        VideoCompressionDiagnostics.logDecision(
            mode: mode.rawValue,
            reason: reason,
            targetFPS: target.outputFrameRate,
            targetVideoBitrate: target.videoBitrate
        )

        onProgress?(0.05)

        var transcodeMetrics: VideoDeliveryExporter.TranscodeMetrics?
        let deliveryURL: URL
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
        } catch {
            try? FileManager.default.removeItem(at: stagedSource)
            throw mapPreparationError(error, fallback: compressionFailedMessage)
        }

        try Task.checkCancellation()

        let deliveryAsset = AVURLAsset(url: deliveryURL)
        let outputProfile: VideoDeliveryExporter.SourceProfile
        do {
            outputProfile = try await VideoDeliveryExporter.validateOutput(
                asset: deliveryAsset,
                fileURL: deliveryURL,
                expectedDurationSeconds: profile.durationSeconds,
                sourceFrameRate: profile.frameRate,
                targetFrameRate: target.outputFrameRate,
                transcodeMetrics: transcodeMetrics
            )
        } catch {
            try? FileManager.default.removeItem(at: stagedSource)
            try? FileManager.default.removeItem(at: deliveryURL)
            throw AppError.unknown(message: compressionFailedMessage)
        }

        guard outputProfile.fileBytes <= maxFinalUploadBytes else {
            try? FileManager.default.removeItem(at: stagedSource)
            try? FileManager.default.removeItem(at: deliveryURL)
            throw AppError.unknown(message: "Prepared video is still too large. Try a shorter clip.")
        }

        do {
            try VideoDeliveryExporter.validateTranscodeEffectiveness(
                source: profile,
                output: outputProfile,
                decisionReason: reason
            )
        } catch {
            try? FileManager.default.removeItem(at: stagedSource)
            try? FileManager.default.removeItem(at: deliveryURL)
            throw mapPreparationError(error, fallback: compressionFailedMessage)
        }

        var finalURL = deliveryURL
        var finalProfile = outputProfile
        if outputProfile.fileBytes >= profile.fileBytes,
           VideoDeliveryExporter.isDeliveryCompatibleVideo(profile: profile, target: target)
        {
            try? FileManager.default.removeItem(at: deliveryURL)
            if profile.isMP4Container {
                finalURL = stagedSource
                finalProfile = profile
            } else {
                var remuxMetrics: VideoDeliveryExporter.TranscodeMetrics?
                let remuxed = try await VideoDeliveryExporter.produceDeliveryVideo(
                    from: sourceAsset,
                    sourceURL: stagedSource,
                    profile: profile,
                    mode: .remux,
                    target: target,
                    transcodeMetrics: &remuxMetrics,
                    onProgress: nil
                )
                try? FileManager.default.removeItem(at: stagedSource)
                finalURL = remuxed
                finalProfile = try await VideoDeliveryExporter.inspectSource(
                    asset: AVURLAsset(url: remuxed),
                    fileURL: remuxed
                )
            }
        } else {
            try? FileManager.default.removeItem(at: stagedSource)
        }

        guard finalProfile.fileBytes <= maxFinalUploadBytes else {
            try? FileManager.default.removeItem(at: finalURL)
            throw AppError.unknown(message: "Prepared video is still too large. Try a shorter clip.")
        }

        VideoCompressionDiagnostics.logOutput(
            sourceFPS: profile.frameRate,
            targetFPS: target.outputFrameRate,
            outputFPS: outputProfile.frameRate,
            sourceDuration: profile.durationSeconds,
            outputDuration: outputProfile.durationSeconds,
            sourceBytes: profile.fileBytes,
            outputBytes: finalProfile.fileBytes,
            outputBitrate: finalProfile.estimatedBitrate,
            outputFrameCount: transcodeMetrics?.outputVideoFrameCount
        )

        onProgress?(0.92)

        let finalAsset = AVURLAsset(url: finalURL)
        let thumb = await generateThumbnail(
            for: finalAsset,
            durationSeconds: finalProfile.durationSeconds
        )
        guard thumb != nil else {
            try? FileManager.default.removeItem(at: finalURL)
            throw AppError.unknown(message: compressionFailedMessage)
        }

        #if DEBUG
        if let info = await VideoPresentationInfo.load(asset: finalAsset) {
            VideoPresentationProbe.log(surface: .profileThumbnail, info: info)
        }
        #endif

        onProgress?(1)

        return PreparedLocalVideo(
            fileURL: finalURL,
            contentType: "video/mp4",
            byteCount: finalProfile.fileBytes,
            durationSeconds: finalProfile.durationSeconds,
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

    static func cleanupTemporaryFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

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

    private static func mapPreparationError(_ error: Error, fallback: String) -> AppError {
        if Task.isCancelled {
            return AppError.unknown(message: "Video preparation was cancelled.")
        }
        if let failure = error as? VideoPreparationFailure {
            switch failure {
            case .durationExceeded:
                return AppError.unknown(message: durationLimitMessage)
            case .sourceTooLarge:
                return AppError.unknown(message: sourceTooLargeMessage)
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
