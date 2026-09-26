import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum VideoPreparationFailure: Error, Equatable {
    case sourceInspectionFailed
    case unsupportedVideo
    case durationExceeded
    case sourceTooLarge
    case compressionFailed
    case outputValidationFailed
    case thumbnailFailed
    case cancelled
}

/// Delivery optimization for Clip uploads — inspect, decide, transcode/remux/passthrough.
nonisolated enum VideoDeliveryExporter {
    enum DeliveryMode: String, Sendable {
        case passthrough
        case remux
        case transcode
    }

    struct SourceProfile: Sendable {
        var durationSeconds: Int
        var orientedSize: CGSize
        var frameRate: Double
        var estimatedBitrate: Double
        var videoCodec: String?
        var audioCodec: String?
        var hasAudio: Bool
        var fileBytes: Int
        var containerExtension: String
        var isMP4Container: Bool
    }

    struct DeliveryTarget: Sendable {
        var outputSize: CGSize
        var outputFrameRate: Double
        var videoBitrate: Int
        var audioBitrate: Int
    }

    /// Output metrics after delivery transcode (frame estimate + high-FPS reduction flag).
    struct TranscodeMetrics: Sendable {
        var outputVideoFrameCount: Int = 0
        var intentionalHighFPSReduction: Bool = false
    }

    /// Minimum acceptable output FPS as a fraction of the delivery target (guards silent frame drops).
    static let minOutputFrameRateRatio = 0.92

    // MARK: - Limits

    static let maxDeliveryLongEdge: CGFloat = 1920
    static let maxDeliveryShortEdge: CGFloat = 1080
    /// Max dimensions when transcode is required for bitrate/size (720p delivery export).
    static let maxTranscodeCompressionLongEdge: CGFloat = 1280
    static let maxTranscodeCompressionShortEdge: CGFloat = 720
    /// Delivery ceiling — sources above this are reduced to 60 FPS (e.g. 120/240 → 60).
    static let maxDeliveryFrameRate: Double = 60
    static let highFrameRateBitrateThreshold: Double = 30.5

    enum DeliveryResolutionClass: Sendable {
        case small
        case hd720
        case hd1080
    }

    // MARK: - Inspection

    static func inspectSource(asset: AVURLAsset, fileURL: URL) async throws -> SourceProfile {
        let duration = try await asset.load(.duration)
        let seconds = Int(ceil(CMTimeGetSeconds(duration)))
        guard seconds > 0 else { throw VideoPreparationFailure.sourceInspectionFailed }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw VideoPreparationFailure.unsupportedVideo }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let oriented = orientedSize(naturalSize: naturalSize, transform: transform)

        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        let fps = nominalFPS > 0 ? Double(nominalFPS) : 30

        let estimatedRate = try await videoTrack.load(.estimatedDataRate)
        var bitrate = Double(estimatedRate)
        if bitrate <= 0 {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let bytes = values.fileSize ?? 0
            bitrate = seconds > 0 ? (Double(bytes) * 8.0) / Double(seconds) : 0
        }

        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let videoCodec = codecFourCC(from: formatDescriptions.first)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let hasAudio = !audioTracks.isEmpty
        var audioCodec: String?
        if let audioTrack = audioTracks.first {
            let audioFormats = try await audioTrack.load(.formatDescriptions)
            audioCodec = codecFourCC(from: audioFormats.first)
        }

        let ext = fileURL.pathExtension.lowercased()
        let fileBytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return SourceProfile(
            durationSeconds: seconds,
            orientedSize: oriented,
            frameRate: fps,
            estimatedBitrate: bitrate,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            hasAudio: hasAudio,
            fileBytes: fileBytes,
            containerExtension: ext.isEmpty ? "mov" : ext,
            isMP4Container: ext == "mp4" || ext == "m4v"
        )
    }

    static func orientedSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    // MARK: - Decision

    static func deliveryTarget(
        for profile: SourceProfile,
        maxLongEdge: CGFloat = maxDeliveryLongEdge,
        maxShortEdge: CGFloat = maxDeliveryShortEdge
    ) -> DeliveryTarget {
        let outputSize = targetOutputSize(
            for: profile.orientedSize,
            maxLongEdge: maxLongEdge,
            maxShortEdge: maxShortEdge
        )
        let outputFPS = targetFrameRate(sourceFPS: profile.frameRate)
        let longEdge = max(outputSize.width, outputSize.height)
        let videoBitrate = targetVideoBitrate(longEdge: longEdge, targetFPS: outputFPS)
        return DeliveryTarget(
            outputSize: outputSize,
            outputFrameRate: outputFPS,
            videoBitrate: videoBitrate,
            audioBitrate: 128_000
        )
    }

    /// Passthrough/remux decisions use the 1080p assessment target; bitrate/size transcodes export at 720p.
    static func deliveryTargetForExport(
        profile: SourceProfile,
        mode: DeliveryMode,
        decisionReason: String,
        assessmentTarget: DeliveryTarget
    ) -> DeliveryTarget {
        guard mode == .transcode else { return assessmentTarget }
        guard decisionReason.contains("bitrate") || decisionReason.contains("size") else {
            return assessmentTarget
        }
        return deliveryTarget(
            for: profile,
            maxLongEdge: maxTranscodeCompressionLongEdge,
            maxShortEdge: maxTranscodeCompressionShortEdge
        )
    }

    /// Transcode encoder rate — ceiling cap; stay near source when already efficient.
    static func transcodeVideoBitrate(profile: SourceProfile, ceiling: Int) -> Int {
        let audioAllowance = profile.hasAudio ? 128_000 : 0
        let sourceVideoEstimate = max(
            500_000,
            Int(effectiveBitrate(for: profile) - Double(audioAllowance))
        )
        return min(ceiling, sourceVideoEstimate)
    }

    static func resolutionClass(for longEdge: CGFloat) -> DeliveryResolutionClass {
        if longEdge <= 720 { return .small }
        if longEdge <= 1280 { return .hd720 }
        return .hd1080
    }

    static func targetOutputSize(
        for orientedSize: CGSize,
        maxLongEdge: CGFloat = maxDeliveryLongEdge,
        maxShortEdge: CGFloat = maxDeliveryShortEdge
    ) -> CGSize {
        let width = max(orientedSize.width, 1)
        let height = max(orientedSize.height, 1)
        let scale = min(
            1.0,
            maxLongEdge / max(width, height),
            maxShortEdge / min(width, height)
        )
        return CGSize(
            width: floor(width * scale),
            height: floor(height * scale)
        )
    }

    static func targetFrameRate(sourceFPS: Double) -> Double {
        if sourceFPS <= 0 { return maxDeliveryFrameRate }
        return min(sourceFPS, maxDeliveryFrameRate)
    }

    /// CMTime frame duration for video composition / encoder cadence.
    static func frameDuration(for fps: Double) -> CMTime {
        if fps <= 0 { return CMTime(value: 1001, timescale: 30000) }
        if abs(fps - 23.976) < 0.05 || abs(fps - 23.98) < 0.05 {
            return CMTime(value: 1001, timescale: 24000)
        }
        if abs(fps - 29.97) < 0.05 {
            return CMTime(value: 1001, timescale: 30000)
        }
        if abs(fps - 59.94) < 0.05 {
            return CMTime(value: 1001, timescale: 60000)
        }
        let timescale: Int32 = 60_000
        let ticksPerFrame = max(1, Int64((Double(timescale) / fps).rounded()))
        return CMTime(value: ticksPerFrame, timescale: timescale)
    }

    /// Composition output cadence — only reduces sources above 60 FPS to a stable 60 FPS cadence.
    static func compositionOutputFrameRate(sourceFPS: Double, targetFPS: Double) -> Double {
        if sourceFPS > maxDeliveryFrameRate + 0.5 {
            return maxDeliveryFrameRate
        }
        return targetFPS
    }

    static func encoderHintFrameRate(for cadenceFPS: Double) -> Int {
        if abs(cadenceFPS - 59.94) < 0.05 { return 60 }
        if abs(cadenceFPS - 29.97) < 0.05 { return 30 }
        if abs(cadenceFPS - 23.976) < 0.05 { return 24 }
        return max(1, Int(round(cadenceFPS)))
    }

    /// Social playback targets — tuned for feed delivery (1080p ~4–6 Mbps, 720p ~2.5–4 Mbps).
    static func targetVideoBitrate(longEdge: CGFloat, targetFPS: Double) -> Int {
        let highFPS = targetFPS > highFrameRateBitrateThreshold
        switch resolutionClass(for: longEdge) {
        case .small:
            return highFPS ? 2_000_000 : 1_400_000
        case .hd720:
            return highFPS ? 3_500_000 : 2_800_000
        case .hd1080:
            return highFPS ? 5_500_000 : 4_500_000
        }
    }

    /// Track metadata can under-report; file size ÷ duration is the ground truth for passthrough decisions.
    static func averageFileBitrate(for profile: SourceProfile) -> Double {
        guard profile.durationSeconds > 0 else { return 0 }
        return (Double(profile.fileBytes) * 8.0) / Double(profile.durationSeconds)
    }

    static func effectiveBitrate(for profile: SourceProfile) -> Double {
        max(profile.estimatedBitrate, averageFileBitrate(for: profile))
    }

    /// Upper bound for an efficiently encoded delivery file (video + AAC + mux overhead).
    static func maxDeliveryFileBytes(profile: SourceProfile, target: DeliveryTarget) -> Int {
        let audioRate = profile.hasAudio ? Double(target.audioBitrate) : 0
        let totalBps = Double(target.videoBitrate) + audioRate
        let seconds = Double(max(profile.durationSeconds, 1))
        return Int((totalBps / 8.0 * seconds * 1.18).rounded(.up))
    }

    static func decideDeliveryMode(profile: SourceProfile, target: DeliveryTarget) -> (DeliveryMode, String) {
        let needsScale = target.outputSize.width < profile.orientedSize.width - 1
            || target.outputSize.height < profile.orientedSize.height - 1
        let needsFPSReduction = profile.frameRate > maxDeliveryFrameRate + 0.5

        let passthroughBitrateCeiling = Double(target.videoBitrate) * 1.02
        let effectiveRate = effectiveBitrate(for: profile)
        let bitrateTooHigh = effectiveRate > passthroughBitrateCeiling
        let fileTooLarge = profile.fileBytes > maxDeliveryFileBytes(profile: profile, target: target)

        let isH264 = profile.videoCodec?.lowercased().contains("avc") == true
            || profile.videoCodec?.lowercased() == "h264"

        if needsScale || needsFPSReduction || !isH264 || bitrateTooHigh || fileTooLarge {
            var reasons: [String] = []
            if needsScale { reasons.append("resolution") }
            if needsFPSReduction { reasons.append("fps") }
            if !isH264 { reasons.append("codec") }
            if bitrateTooHigh { reasons.append("bitrate") }
            if fileTooLarge { reasons.append("size") }
            return (.transcode, reasons.joined(separator: "+"))
        }

        if profile.isMP4Container {
            return (.passthrough, "delivery-ready-mp4")
        }
        return (.remux, "compatible-codecs-non-mp4")
    }

    /// Video stream is within delivery limits — used for post-encode size guard (ignore audio codec differences).
    static func isDeliveryCompatibleVideo(profile: SourceProfile, target: DeliveryTarget) -> Bool {
        let needsScale = target.outputSize.width < profile.orientedSize.width - 1
            || target.outputSize.height < profile.orientedSize.height - 1
        let needsFPSReduction = profile.frameRate > maxDeliveryFrameRate + 0.5
        let passthroughBitrateCeiling = Double(targetVideoBitrate(
            longEdge: max(target.outputSize.width, target.outputSize.height),
            targetFPS: target.outputFrameRate
        )) * 1.02
        let effectiveRate = effectiveBitrate(for: profile)
        let bitrateTooHigh = effectiveRate > passthroughBitrateCeiling
        let fileTooLarge = profile.fileBytes > maxDeliveryFileBytes(profile: profile, target: target)
        let isH264 = profile.videoCodec?.lowercased().contains("avc") == true
            || profile.videoCodec?.lowercased() == "h264"
        return !needsScale && !needsFPSReduction && isH264 && !bitrateTooHigh && !fileTooLarge
    }

    // MARK: - Export

    static func produceDeliveryVideo(
        from sourceAsset: AVURLAsset,
        sourceURL: URL,
        profile: SourceProfile,
        mode: DeliveryMode,
        target: DeliveryTarget,
        transcodeMetrics: inout TranscodeMetrics?,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-delivery-\(UUID().uuidString).mp4")

        switch mode {
        case .passthrough, .remux:
            // Always remux through AVAssetExportSession so `shouldOptimizeForNetworkUse`
            // moves the `moov` atom to the file start — raw copy skips fast-start.
            try await exportWithSession(
                asset: sourceAsset,
                outputURL: outputURL,
                presetName: AVAssetExportPresetPassthrough,
                compatiblePresets: await compatibleExportPresets(for: sourceAsset),
                videoComposition: nil,
                onProgress: onProgress
            )
            return outputURL
        case .transcode:
            var metrics = TranscodeMetrics(
                intentionalHighFPSReduction: profile.frameRate > maxDeliveryFrameRate + 0.5
            )
            try await transcode(
                asset: sourceAsset,
                outputURL: outputURL,
                profile: profile,
                target: target,
                metrics: &metrics,
                onProgress: onProgress
            )
            transcodeMetrics = metrics
            return outputURL
        }
    }

    /// Preferred system export preset for delivery transcode (resolved against asset compatibility at export time).
    static func deliveryExportPresetName(for target: DeliveryTarget) -> String {
        deliveryExportPresetCandidates(for: target).first
            ?? AVAssetExportPresetMediumQuality
    }

    /// Ordered export presets for max-1080 delivery (first compatible with the asset wins at export time).
    static func deliveryExportPresetCandidates(for target: DeliveryTarget) -> [String] {
        let longEdge = max(target.outputSize.width, target.outputSize.height)
        switch resolutionClass(for: longEdge) {
        case .small, .hd720:
            return [
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset960x540,
                AVAssetExportPresetHighestQuality,
            ]
        case .hd1080:
            return [
                AVAssetExportPreset1920x1080,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetHighestQuality,
            ]
        }
    }

    struct ExportPresetResolution: Sendable {
        var preferred: String
        var resolved: String
        var compatiblePresets: [String]
    }

    /// Presets that can export `asset`. Replaces deprecated `exportPresets(compatibleWith:)`.
    static func compatibleExportPresets(for asset: AVAsset) async -> [String] {
        var compatible: [String] = []
        for preset in AVAssetExportSession.allExportPresets() {
            let matches = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: nil
            )
            if matches {
                compatible.append(preset)
            }
        }
        return compatible
    }

    /// Picks the first preset that is both compatible with the asset and instantiates a session.
    static func resolveExportPreset(for asset: AVAsset, target: DeliveryTarget) async -> ExportPresetResolution {
        let preferred = deliveryExportPresetName(for: target)
        let compatible = await compatibleExportPresets(for: asset)
        let compatibleSet = Set(compatible)
        var seen = Set<String>()
        var candidates: [String] = []
        for preset in [preferred] + deliveryExportPresetCandidates(for: target) + compatible {
            guard seen.insert(preset).inserted else { continue }
            candidates.append(preset)
        }
        for preset in candidates {
            guard compatibleSet.contains(preset) else { continue }
            if AVAssetExportSession(asset: asset, presetName: preset) != nil {
                return ExportPresetResolution(
                    preferred: preferred,
                    resolved: preset,
                    compatiblePresets: compatible
                )
            }
        }
        for preset in compatible where AVAssetExportSession(asset: asset, presetName: preset) != nil {
            return ExportPresetResolution(
                preferred: preferred,
                resolved: preset,
                compatiblePresets: compatible
            )
        }
        return ExportPresetResolution(
            preferred: preferred,
            resolved: preferred,
            compatiblePresets: compatible
        )
    }

    private static func exportCompositionRenderSizeDescription(_ composition: AVVideoComposition?) -> String {
        guard let composition else { return "none" }
        let size = composition.renderSize
        return "\(Int(size.width))x\(Int(size.height))"
    }

    private static func isMP4Supported(in supportedFileTypes: [AVFileType]) -> Bool {
        supportedFileTypes.contains { type in
            type == .mp4 || type.rawValue == AVFileType.mp4.rawValue || type.rawValue.contains("mpeg-4")
        }
    }

    private static func resolveExportOutputFileType(from supportedFileTypes: [AVFileType]) -> AVFileType? {
        if isMP4Supported(in: supportedFileTypes) {
            return .mp4
        }
        return supportedFileTypes.first
    }

    /// Requires a non-empty exported file after `export(to:as:)` finishes.
    private static func acceptCompletedExportOutput(at outputURL: URL) throws {
        let info = VideoTranscodeFailureDiagnostics.outputFileInfo(at: outputURL)
        VideoTranscodeDiagnostics.logCompletedOutputCheck(
            outputURL: outputURL,
            exists: info.exists,
            fileBytes: info.bytes
        )
        guard info.exists else {
            VideoTranscodeDiagnostics.logCompletedOutputRejected(reason: "missingFile")
            throw VideoPreparationFailure.compressionFailed
        }
        guard info.bytes > 0 else {
            VideoTranscodeDiagnostics.logCompletedOutputRejected(reason: "zeroBytes")
            throw VideoPreparationFailure.compressionFailed
        }
        VideoTranscodeDiagnostics.logCompletedOutputAccepted(fileBytes: info.bytes)
    }

    private static func logExportWithSessionReturnedIfPresent(at outputURL: URL) {
        let info = VideoTranscodeFailureDiagnostics.outputFileInfo(at: outputURL)
        VideoTranscodeDiagnostics.logExportWithSessionReturned(
            outputURL: outputURL,
            fileBytes: info.bytes
        )
    }

    private static func logAndThrowExportFailure(
        stage: String,
        exportError: Error?,
        statusLabel: String,
        presetName: String,
        outputURL: URL,
        compositionSize: String
    ) async throws -> Never {
        let errorSummary = VideoTranscodeFailureDiagnostics.errorDetails(from: exportError)?
            .description ?? "none"
        VideoTranscodeDiagnostics.logExportSessionFinished(
            status: statusLabel,
            errorSummary: errorSummary
        )
        let failedOutput = await VideoTranscodeFailureDiagnostics.inspectFailedOutput(at: outputURL)
        VideoTranscodeFailureDiagnostics.logFailedOutputInspection(failedOutput)
        VideoTranscodeFailureDiagnostics.logExportFailure(
            stage: stage,
            presetName: presetName,
            outputURL: outputURL,
            sessionError: exportError,
            extra: "status=\(statusLabel) compositionRenderSize=\(compositionSize)"
        )
        try? FileManager.default.removeItem(at: outputURL)
        throw VideoPreparationFailure.compressionFailed
    }

    static func validateOutput(
        asset: AVURLAsset,
        fileURL: URL,
        expectedDurationSeconds: Int,
        sourceFrameRate: Double,
        targetFrameRate: Double,
        transcodeMetrics: TranscodeMetrics? = nil
    ) async throws -> SourceProfile {
        let profile = try await inspectSource(asset: asset, fileURL: fileURL)
        guard profile.fileBytes > 0 else {
            VideoPrepareDiagnostics.logValidationFailed(reason: "emptyFile")
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard profile.isMP4Container || fileURL.pathExtension.lowercased() == "mp4" else {
            VideoPrepareDiagnostics.logValidationFailed(reason: "notMP4Container ext=\(fileURL.pathExtension)")
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard abs(profile.durationSeconds - expectedDurationSeconds) <= 2 else {
            VideoPrepareDiagnostics.logValidationFailed(
                reason: "durationMismatch expected=\(expectedDurationSeconds) actual=\(profile.durationSeconds)"
            )
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard profile.orientedSize.width > 0, profile.orientedSize.height > 0 else {
            VideoPrepareDiagnostics.logValidationFailed(reason: "invalidOrientedSize")
            throw VideoPreparationFailure.outputValidationFailed
        }
        let longEdge = max(profile.orientedSize.width, profile.orientedSize.height)
        guard longEdge <= maxDeliveryLongEdge + 2 else {
            VideoPrepareDiagnostics.logValidationFailed(
                reason: "resolutionTooLarge longEdge=\(longEdge)"
            )
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard profile.frameRate <= maxDeliveryFrameRate + 2 else {
            VideoPrepareDiagnostics.logValidationFailed(
                reason: "frameRateTooHigh fps=\(profile.frameRate)"
            )
            throw VideoPreparationFailure.outputValidationFailed
        }
        try validateOutputFrameRate(
            sourceFPS: sourceFrameRate,
            targetFPS: targetFrameRate,
            outputFPS: profile.frameRate,
            outputFrameCount: transcodeMetrics?.outputVideoFrameCount,
            outputDurationSeconds: profile.durationSeconds,
            intentionalHighFPSReduction: transcodeMetrics?.intentionalHighFPSReduction ?? false
        )
        return profile
    }

    static func validateOutputFrameRate(
        sourceFPS: Double,
        targetFPS: Double,
        outputFPS: Double,
        outputFrameCount: Int?,
        outputDurationSeconds: Int,
        intentionalHighFPSReduction: Bool
    ) throws {
        let cadenceFPS = compositionOutputFrameRate(sourceFPS: sourceFPS, targetFPS: targetFPS)
        let minAcceptable = cadenceFPS * minOutputFrameRateRatio

        if intentionalHighFPSReduction {
            guard outputFPS >= minAcceptable else {
                VideoPrepareDiagnostics.logValidationFailed(
                    reason: "outputFPSTooLowAfterHighFPSReduction outputFPS=\(outputFPS) min=\(minAcceptable)"
                )
                throw VideoPreparationFailure.outputValidationFailed
            }
            return
        }

        guard outputFPS >= minAcceptable else {
            VideoPrepareDiagnostics.logValidationFailed(
                reason: "outputFPSTooLow outputFPS=\(outputFPS) min=\(minAcceptable) cadenceFPS=\(cadenceFPS)"
            )
            throw VideoPreparationFailure.outputValidationFailed
        }

        if let outputFrameCount, outputDurationSeconds > 0 {
            let measuredFPS = Double(outputFrameCount) / Double(outputDurationSeconds)
            guard measuredFPS >= minAcceptable else {
                VideoPrepareDiagnostics.logValidationFailed(
                    reason: "estimatedFrameCountTooLow measuredFPS=\(measuredFPS) min=\(minAcceptable) frames=\(outputFrameCount)"
                )
                throw VideoPreparationFailure.outputValidationFailed
            }
        }
    }

    /// When transcode was chosen for bitrate/size, accept any output strictly smaller than the source (ratios are diagnostic only).
    static func validateTranscodeEffectiveness(
        source: SourceProfile,
        output: SourceProfile,
        decisionReason: String
    ) throws {
        guard decisionReason.contains("bitrate") || decisionReason.contains("size") else { return }
        let byteRatio = Double(output.fileBytes) / Double(max(source.fileBytes, 1))
        let bitrateRatio = output.estimatedBitrate / max(source.estimatedBitrate, 1)
        if output.fileBytes < source.fileBytes {
            return
        }
        VideoPrepareDiagnostics.logTranscodeEffectivenessValidationFailed(
            reason: """
            transcodeNotSmallerThanSource sourceBytes=\(source.fileBytes) \
            outputBytes=\(output.fileBytes) byteRatio=\(String(format: "%.3f", byteRatio)) \
            bitrateRatio=\(String(format: "%.3f", bitrateRatio))
            """
        )
        throw VideoPreparationFailure.compressionFailed
    }

    // MARK: - Private export

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = Int(floor(value))
        return max(2, rounded - (rounded % 2))
    }

    /// Delivery transcode via AVAssetExportSession (orientation/scaling in video composition).
    private static func transcode(
        asset: AVURLAsset,
        outputURL: URL,
        profile: SourceProfile,
        target: DeliveryTarget,
        metrics: inout TranscodeMetrics,
        onProgress: ((Double) -> Void)?
    ) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoPreparationFailure.compressionFailed
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let oriented = orientedSize(naturalSize: naturalSize, transform: preferredTransform)

        let videoFormatDescriptions = try await videoTrack.load(.formatDescriptions)
        let videoSourceFormatHint = codecFourCC(from: videoFormatDescriptions.first) ?? "unknown"
        var audioSourceFormatHint = "none"
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            let audioFormatDescriptions = try await audioTrack.load(.formatDescriptions)
            audioSourceFormatHint = codecFourCC(from: audioFormatDescriptions.first) ?? "unknown"
        }

        let composition = makeTranscodeVideoComposition(
            videoTrack: videoTrack,
            duration: duration,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            oriented: oriented,
            sourceFrameRate: profile.frameRate,
            target: target
        )

        let presetResolution = await resolveExportPreset(for: asset, target: target)
        VideoTranscodeDiagnostics.logExportCompatiblePresets(
            presetResolution.compatiblePresets,
            preferred: presetResolution.preferred
        )
        if presetResolution.resolved != presetResolution.preferred {
            VideoTranscodeDiagnostics.logExportSetup(
                stage: "presetFallback",
                detail: "preferred=\(presetResolution.preferred) resolved=\(presetResolution.resolved)"
            )
        }
        let preset = presetResolution.resolved
        VideoTranscodeSessionAudit.logWriterConfiguration(
            outputFileType: AVFileType.mp4.rawValue,
            videoCodec: "h264-exportSession",
            videoWidth: Int(target.outputSize.width.rounded()),
            videoHeight: Int(target.outputSize.height.rounded()),
            videoBitrate: target.videoBitrate,
            videoBitrateIsExportPolicyOnly: true,
            expectedFPS: target.outputFrameRate,
            audioFormat: audioTracks.isEmpty ? "none" : "aac-exportSession",
            audioSampleRate: 0,
            audioChannels: 0,
            audioBitrate: target.audioBitrate,
            videoSourceFormatHint: "\(videoSourceFormatHint)-diagnosticOnly",
            audioSourceFormatHint: "\(audioSourceFormatHint)-diagnosticOnly",
            writerShouldOptimizeForNetworkUse: true
        )
        VideoTranscodeDiagnostics.logExportSessionStarted(
            preset: preset,
            outputURL: outputURL,
            targetSize: target.outputSize,
            targetFrameRate: target.outputFrameRate
        )

        try await exportWithSession(
            asset: asset,
            outputURL: outputURL,
            presetName: preset,
            compatiblePresets: presetResolution.compatiblePresets,
            videoComposition: composition,
            onProgress: onProgress
        )

        let durationSeconds = max(CMTimeGetSeconds(duration), 1)
        metrics.outputVideoFrameCount = max(
            1,
            Int((durationSeconds * target.outputFrameRate).rounded())
        )
    }

    private final class ExportSessionHandle: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }

        func cancel() {
            session.cancelExport()
        }
    }

    private static func makeTranscodeVideoComposition(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        oriented: CGSize,
        sourceFrameRate: Double,
        target: DeliveryTarget
    ) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = target.outputSize
        let cadenceFPS = compositionOutputFrameRate(
            sourceFPS: sourceFrameRate,
            targetFPS: target.outputFrameRate
        )
        composition.frameDuration = frameDuration(for: cadenceFPS)

        let scaleX = target.outputSize.width / max(oriented.width, 1)
        let scaleY = target.outputSize.height / max(oriented.height, 1)
        let scale = min(scaleX, scaleY)

        var transform = preferredTransform
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        return composition
    }

    private static func exportWithSession(
        asset: AVAsset,
        outputURL: URL,
        presetName: String,
        compatiblePresets: [String],
        videoComposition: AVVideoComposition?,
        onProgress: ((Double) -> Void)?
    ) async throws {
        VideoTranscodeDiagnostics.logExportSetup(
            stage: "begin",
            detail: "preset=\(presetName) output=\(outputURL.lastPathComponent) hasComposition=\(videoComposition != nil)"
        )
        try? FileManager.default.removeItem(at: outputURL)

        VideoTranscodeDiagnostics.logExportCompatiblePresets(compatiblePresets, preferred: presetName)

        guard compatiblePresets.contains(presetName) else {
            VideoTranscodeDiagnostics.logExportSetup(
                stage: "presetNotCompatible",
                detail: "preset=\(presetName) not in compatiblePresets"
            )
            VideoTranscodeFailureDiagnostics.logExportFailure(
                stage: "presetNotCompatible",
                presetName: presetName,
                outputURL: outputURL,
                sessionError: nil,
                extra: "compatibleCount=\(compatiblePresets.count)"
            )
            throw VideoPreparationFailure.compressionFailed
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            VideoTranscodeDiagnostics.logExportSetup(
                stage: "sessionInitNil",
                detail: "AVAssetExportSession(asset:presetName:) returned nil preset=\(presetName)"
            )
            VideoTranscodeFailureDiagnostics.logExportFailure(
                stage: "sessionInitNil",
                presetName: presetName,
                outputURL: outputURL,
                sessionError: nil,
                extra: "compatibleCount=\(compatiblePresets.count)"
            )
            throw VideoPreparationFailure.compressionFailed
        }

        let supportedFileTypes = session.supportedFileTypes
        let supportedTypeNames = supportedFileTypes.map(\.rawValue)
        let mp4Supported = isMP4Supported(in: supportedFileTypes)
        let compositionSize = exportCompositionRenderSizeDescription(videoComposition)

        VideoTranscodeDiagnostics.logExportSessionCreated(
            preset: presetName,
            status: "unknown",
            supportedFileTypes: supportedTypeNames,
            mp4Supported: mp4Supported,
            compositionRenderSize: compositionSize
        )

        guard let outputFileType = resolveExportOutputFileType(from: supportedFileTypes) else {
            VideoTranscodeDiagnostics.logExportSetup(
                stage: "noSupportedFileTypes",
                detail: "supportedFileTypes empty"
            )
            VideoTranscodeFailureDiagnostics.logExportFailure(
                stage: "noSupportedFileTypes",
                presetName: presetName,
                outputURL: outputURL,
                sessionError: nil,
                extra: "compositionRenderSize=\(compositionSize)"
            )
            throw VideoPreparationFailure.compressionFailed
        }

        if !mp4Supported {
            VideoTranscodeDiagnostics.logExportSetup(
                stage: "mp4UnsupportedUsingFallback",
                detail: "using outputFileType=\(outputFileType.rawValue)"
            )
        }

        session.outputURL = outputURL
        session.outputFileType = outputFileType
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition

        VideoTranscodeDiagnostics.logExportStarting(
            status: "unknown",
            outputFileType: outputFileType.rawValue
        )

        let exportSession = ExportSessionHandle(session)

        do {
            try await withTaskCancellationHandler {
                let progressTask: Task<Void, Never>? = onProgress.map { callback in
                    Task {
                        for await state in exportSession.session.states(updateInterval: 0.1) {
                            guard !Task.isCancelled else { break }
                            if case .exporting(let progress) = state {
                                callback(Double(progress.fractionCompleted))
                            }
                        }
                    }
                }
                defer { progressTask?.cancel() }
                try await exportSession.session.export(to: outputURL, as: outputFileType)
            } onCancel: {
                VideoTranscodeDiagnostics.logExportCancelled()
                exportSession.cancel()
            }
            try acceptCompletedExportOutput(at: outputURL)
            VideoTranscodeDiagnostics.logExportSessionFinished(
                status: "completed",
                errorSummary: "none"
            )
            onProgress?(1)
            logExportWithSessionReturnedIfPresent(at: outputURL)
        } catch let failure as VideoPreparationFailure {
            throw failure
        } catch {
            if Task.isCancelled || error is CancellationError {
                VideoTranscodeDiagnostics.logExportCancelled()
                let failedOutput = await VideoTranscodeFailureDiagnostics.inspectFailedOutput(at: outputURL)
                VideoTranscodeFailureDiagnostics.logFailedOutputInspection(failedOutput)
                try? FileManager.default.removeItem(at: outputURL)
                throw VideoPreparationFailure.cancelled
            }
            let info = VideoTranscodeFailureDiagnostics.outputFileInfo(at: outputURL)
            if info.exists, info.bytes > 0 {
                VideoTranscodeDiagnostics.logExportSetup(
                    stage: "exportThrowWithCompletedStatus",
                    detail: "exportAPIError=\(error)"
                )
                VideoTranscodeDiagnostics.logExportSessionFinished(
                    status: "completed",
                    errorSummary: "none"
                )
                onProgress?(1)
                logExportWithSessionReturnedIfPresent(at: outputURL)
                return
            }
            try await logAndThrowExportFailure(
                stage: "exportSessionFailed",
                exportError: error,
                statusLabel: "failed",
                presetName: presetName,
                outputURL: outputURL,
                compositionSize: compositionSize
            )
        }
    }

    private static func codecFourCC(from formatDescription: CMFormatDescription?) -> String? {
        guard let formatDescription else { return nil }
        let codec = CMFormatDescriptionGetMediaSubType(formatDescription)
        return fourCharacterString(code: codec)
    }

    private static func fourCharacterString(code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar((code >> 24) & 0xFF),
            CChar((code >> 16) & 0xFF),
            CChar((code >> 8) & 0xFF),
            CChar(code & 0xFF),
            0,
        ]
        return String(cString: bytes)
    }
}
