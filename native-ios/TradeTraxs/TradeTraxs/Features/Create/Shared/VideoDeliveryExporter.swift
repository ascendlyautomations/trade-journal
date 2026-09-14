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

    /// Frame counts collected during reader/writer transcode (DEBUG validation + logging).
    struct TranscodeMetrics: Sendable {
        var outputVideoFrameCount: Int = 0
        var intentionalHighFPSReduction: Bool = false
    }

    /// Minimum acceptable output FPS as a fraction of the delivery target (guards silent frame drops).
    static let minOutputFrameRateRatio = 0.92

    // MARK: - Limits

    static let maxDeliveryLongEdge: CGFloat = 1920
    static let maxDeliveryShortEdge: CGFloat = 1080
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

    static func deliveryTarget(for profile: SourceProfile) -> DeliveryTarget {
        let outputSize = targetOutputSize(for: profile.orientedSize)
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

    static func targetOutputSize(for orientedSize: CGSize) -> CGSize {
        let width = max(orientedSize.width, 1)
        let height = max(orientedSize.height, 1)
        let scale = min(
            1.0,
            maxDeliveryLongEdge / max(width, height),
            maxDeliveryShortEdge / min(width, height)
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

    static func validateOutput(
        asset: AVURLAsset,
        fileURL: URL,
        expectedDurationSeconds: Int,
        sourceFrameRate: Double,
        targetFrameRate: Double,
        transcodeMetrics: TranscodeMetrics? = nil
    ) async throws -> SourceProfile {
        let profile = try await inspectSource(asset: asset, fileURL: fileURL)
        guard profile.fileBytes > 0 else { throw VideoPreparationFailure.outputValidationFailed }
        guard profile.isMP4Container || fileURL.pathExtension.lowercased() == "mp4" else {
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard abs(profile.durationSeconds - expectedDurationSeconds) <= 2 else {
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard profile.orientedSize.width > 0, profile.orientedSize.height > 0 else {
            throw VideoPreparationFailure.outputValidationFailed
        }
        let longEdge = max(profile.orientedSize.width, profile.orientedSize.height)
        guard longEdge <= maxDeliveryLongEdge + 2 else {
            throw VideoPreparationFailure.outputValidationFailed
        }
        guard profile.frameRate <= maxDeliveryFrameRate + 2 else {
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
                throw VideoPreparationFailure.outputValidationFailed
            }
            return
        }

        guard outputFPS >= minAcceptable else {
            throw VideoPreparationFailure.outputValidationFailed
        }

        if let outputFrameCount, outputDurationSeconds > 0 {
            let measuredFPS = Double(outputFrameCount) / Double(outputDurationSeconds)
            guard measuredFPS >= minAcceptable else {
                throw VideoPreparationFailure.outputValidationFailed
            }
        }
    }

    /// When transcode was chosen for excessive bitrate, output must be materially smaller.
    static func validateTranscodeEffectiveness(
        source: SourceProfile,
        output: SourceProfile,
        decisionReason: String
    ) throws {
        guard decisionReason.contains("bitrate") else { return }
        let byteRatio = Double(output.fileBytes) / Double(max(source.fileBytes, 1))
        let bitrateRatio = output.estimatedBitrate / max(source.estimatedBitrate, 1)
        if byteRatio > 0.85 && bitrateRatio > 0.85 {
            throw VideoPreparationFailure.compressionFailed
        }
    }

    // MARK: - Private export

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = Int(floor(value))
        return max(2, rounded - (rounded % 2))
    }

    private static func transcode(
        asset: AVURLAsset,
        outputURL: URL,
        profile: SourceProfile,
        target: DeliveryTarget,
        metrics: inout TranscodeMetrics,
        onProgress: ((Double) -> Void)?
    ) async throws {
        try await transcodeWithReaderWriter(
            asset: asset,
            outputURL: outputURL,
            profile: profile,
            sourceFrameRate: profile.frameRate,
            target: target,
            metrics: &metrics,
            onProgress: onProgress
        )
    }

    /// Serializes `copyNextSampleBuffer` — AVAssetReader must not be read concurrently across outputs.
    private final class ExportSessionHandle: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }

        func cancel() {
            session.cancelExport()
        }
    }

    private final class ReaderSampleGate: @unchecked Sendable {
        private let lock = NSLock()

        func copyNext(from output: AVAssetReaderOutput) -> CMSampleBuffer? {
            lock.lock()
            defer { lock.unlock() }
            return output.copyNextSampleBuffer()
        }
    }

    private enum TranscodeTrack: Sendable {
        case video
        case audio
    }

    private struct TranscodeProgressSnapshot: Sendable {
        var videoSampleCount: Int
        var audioSampleCount: Int
        var lastVideoPTS: Double
        var lastAudioPTS: Double
        var secondsSinceProgress: TimeInterval
        var videoFinished: Bool
        var audioFinished: Bool
    }

    private final class TranscodeProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var lastProgressAt = Date()
        private(set) var videoSampleCount = 0
        private(set) var audioSampleCount = 0
        private(set) var lastVideoPTS: Double = -1
        private(set) var lastAudioPTS: Double = -1
        private(set) var videoFinished = false
        private(set) var audioFinished = false

        func recordVideo(sampleCount: Int, pts: Double) {
            lock.lock()
            defer { lock.unlock() }
            videoSampleCount = sampleCount
            lastVideoPTS = pts
            lastProgressAt = Date()
        }

        func recordAudio(sampleCount: Int, pts: Double) {
            lock.lock()
            defer { lock.unlock() }
            audioSampleCount = sampleCount
            lastAudioPTS = pts
            lastProgressAt = Date()
        }

        func markVideoFinished(sampleCount: Int) {
            lock.lock()
            defer { lock.unlock() }
            videoSampleCount = sampleCount
            videoFinished = true
            lastProgressAt = Date()
        }

        func markAudioFinished(sampleCount: Int) {
            lock.lock()
            defer { lock.unlock() }
            audioSampleCount = sampleCount
            audioFinished = true
            lastProgressAt = Date()
        }

        func snapshot() -> TranscodeProgressSnapshot {
            lock.lock()
            defer { lock.unlock() }
            return TranscodeProgressSnapshot(
                videoSampleCount: videoSampleCount,
                audioSampleCount: audioSampleCount,
                lastVideoPTS: lastVideoPTS,
                lastAudioPTS: lastAudioPTS,
                secondsSinceProgress: Date().timeIntervalSince(lastProgressAt),
                videoFinished: videoFinished,
                audioFinished: audioFinished
            )
        }

        func markPumpsStarted() {
            lock.lock()
            defer { lock.unlock() }
            lastProgressAt = Date()
        }
    }

    /// Holds AVFoundation writer/reader handles for `@Sendable` sample pump callbacks.
    private final class WriterSamplePump: @unchecked Sendable {
        let track: TranscodeTrack
        let readerOutput: AVAssetReaderOutput
        let writerInput: AVAssetWriterInput
        private let readerSampleGate: ReaderSampleGate
        private let totalSeconds: Double
        private let progressTracker: TranscodeProgressTracker
        private let onFrameAppended: (() -> Void)?
        private let onProgress: ((Double) -> Void)?
        private var sampleCount = 0

        init(
            track: TranscodeTrack,
            readerOutput: AVAssetReaderOutput,
            writerInput: AVAssetWriterInput,
            readerSampleGate: ReaderSampleGate,
            totalSeconds: Double,
            progressTracker: TranscodeProgressTracker,
            onFrameAppended: (() -> Void)?,
            onProgress: ((Double) -> Void)?
        ) {
            self.track = track
            self.readerOutput = readerOutput
            self.writerInput = writerInput
            self.readerSampleGate = readerSampleGate
            self.totalSeconds = totalSeconds
            self.progressTracker = progressTracker
            self.onFrameAppended = onFrameAppended
            self.onProgress = onProgress
        }

        func drain(continuation: CheckedContinuation<Void, Error>) {
            while writerInput.isReadyForMoreMediaData {
                if Task.isCancelled {
                    writerInput.markAsFinished()
                    continuation.resume(throwing: VideoPreparationFailure.cancelled)
                    return
                }

                guard let sampleBuffer = readerSampleGate.copyNext(from: readerOutput) else {
                    writerInput.markAsFinished()
                    switch track {
                    case .video:
                        progressTracker.markVideoFinished(sampleCount: sampleCount)
                        VideoTranscodeDiagnostics.logVideoPumpFinished(samples: sampleCount)
                    case .audio:
                        progressTracker.markAudioFinished(sampleCount: sampleCount)
                        VideoTranscodeDiagnostics.logAudioPumpFinished(samples: sampleCount)
                    }
                    continuation.resume()
                    return
                }

                if !writerInput.append(sampleBuffer) {
                    continuation.resume(throwing: VideoPreparationFailure.compressionFailed)
                    return
                }

                sampleCount += 1
                onFrameAppended?()

                let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                switch track {
                case .video:
                    progressTracker.recordVideo(sampleCount: sampleCount, pts: pts)
                    if sampleCount == 1 || sampleCount % 30 == 0 {
                        VideoTranscodeDiagnostics.logVideoProgress(
                            samples: sampleCount,
                            pts: pts,
                            writerReady: writerInput.isReadyForMoreMediaData
                        )
                    }
                case .audio:
                    progressTracker.recordAudio(sampleCount: sampleCount, pts: pts)
                    if sampleCount == 1 || sampleCount % 50 == 0 {
                        VideoTranscodeDiagnostics.logAudioProgress(
                            samples: sampleCount,
                            pts: pts,
                            writerReady: writerInput.isReadyForMoreMediaData
                        )
                    }
                }

                if let onProgress, totalSeconds > 0, track == .video {
                    onProgress(min(1, pts / totalSeconds))
                }
            }
        }
    }

    private static func transcodeWithReaderWriter(
        asset: AVURLAsset,
        outputURL: URL,
        profile: SourceProfile,
        sourceFrameRate: Double,
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

        let videoComposition = makeTranscodeVideoComposition(
            videoTrack: videoTrack,
            duration: duration,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            oriented: oriented,
            sourceFrameRate: sourceFrameRate,
            target: target
        )

        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let readerSampleGate = ReaderSampleGate()

        let readerVideoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ]
        )
        readerVideoOutput.videoComposition = videoComposition
        readerVideoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerVideoOutput) else {
            throw VideoPreparationFailure.compressionFailed
        }
        reader.add(readerVideoOutput)

        let outputWidth = evenDimension(target.outputSize.width)
        let outputHeight = evenDimension(target.outputSize.height)
        let encoderFPS = encoderHintFrameRate(
            for: compositionOutputFrameRate(sourceFPS: sourceFrameRate, targetFPS: target.outputFrameRate)
        )
        let encodeBitrate = transcodeVideoBitrate(
            profile: profile,
            ceiling: target.videoBitrate
        )
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: encodeBitrate,
                AVVideoMaxKeyFrameIntervalKey: max(1, encoderFPS) * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: max(1, encoderFPS),
                AVVideoAllowFrameReorderingKey: true,
            ],
        ]

        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerVideoInput) else {
            throw VideoPreparationFailure.compressionFailed
        }
        writer.add(writerVideoInput)

        var readerAudioOutput: AVAssetReaderTrackOutput?
        var writerAudioInput: AVAssetWriterInput?

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            let decompressedAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16,
            ]
            let audioReaderOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: decompressedAudioSettings
            )
            audioReaderOutput.alwaysCopiesSampleData = false
            if reader.canAdd(audioReaderOutput) {
                reader.add(audioReaderOutput)
                readerAudioOutput = audioReaderOutput
            }

            let audioWriterSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: target.audioBitrate,
            ]
            let audioWriterInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioWriterSettings
            )
            audioWriterInput.expectsMediaDataInRealTime = false
            if writer.canAdd(audioWriterInput) {
                writer.add(audioWriterInput)
                writerAudioInput = audioWriterInput
            }
        }

        guard reader.startReading() else {
            throw VideoPreparationFailure.compressionFailed
        }
        VideoTranscodeDiagnostics.logReaderStarted()

        guard writer.startWriting() else {
            throw VideoPreparationFailure.compressionFailed
        }
        VideoTranscodeDiagnostics.logWriterStarted()
        writer.startSession(atSourceTime: .zero)

        let durationSeconds = CMTimeGetSeconds(duration)
        let progressTracker = TranscodeProgressTracker()
        let hasAudio = readerAudioOutput != nil && writerAudioInput != nil
        progressTracker.markPumpsStarted()

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await runTranscodeWatchdog(
                        tracker: progressTracker,
                        reader: reader,
                        writer: writer,
                        videoInput: writerVideoInput,
                        audioInput: writerAudioInput,
                        hasAudio: hasAudio,
                        durationSeconds: durationSeconds
                    )
                }
                group.addTask {
                    VideoTranscodeDiagnostics.logVideoPumpStarted()
                    try await pumpSamples(
                        track: .video,
                        from: readerVideoOutput,
                        to: writerVideoInput,
                        readerSampleGate: readerSampleGate,
                        duration: duration,
                        progressTracker: progressTracker,
                        onFrameAppended: nil,
                        onProgress: { value in
                            onProgress?(value * 0.95)
                        }
                    )
                }
                if let readerAudioOutput, let writerAudioInput {
                    group.addTask {
                        VideoTranscodeDiagnostics.logAudioPumpStarted()
                        try await pumpSamples(
                            track: .audio,
                            from: readerAudioOutput,
                            to: writerAudioInput,
                            readerSampleGate: readerSampleGate,
                            duration: duration,
                            progressTracker: progressTracker,
                            onFrameAppended: nil,
                            onProgress: nil
                        )
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        metrics.outputVideoFrameCount = progressTracker.snapshot().videoSampleCount
        VideoTranscodeDiagnostics.logInputsMarkedFinished()

        if Task.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoPreparationFailure.cancelled
        }

        if reader.status == .failed || writer.status == .failed {
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoPreparationFailure.compressionFailed
        }

        VideoTranscodeDiagnostics.logWriterFinishStarted()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        VideoTranscodeDiagnostics.logWriterFinishCompleted(status: "\(writer.status)")

        if writer.status != .completed {
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoPreparationFailure.compressionFailed
        }

        onProgress?(1)
    }

    private static func runTranscodeWatchdog(
        tracker: TranscodeProgressTracker,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        audioInput: AVAssetWriterInput?,
        hasAudio: Bool,
        durationSeconds: Double
    ) async throws {
        let stallLimit = max(30.0, durationSeconds * 2.5)
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let snap = tracker.snapshot()
            if snap.videoFinished && (!hasAudio || snap.audioFinished) {
                return
            }
            if snap.secondsSinceProgress >= stallLimit {
                VideoTranscodeDiagnostics.logStall(
                    readerStatus: "\(reader.status)",
                    writerStatus: "\(writer.status)",
                    videoReady: videoInput.isReadyForMoreMediaData,
                    audioReady: audioInput?.isReadyForMoreMediaData ?? false,
                    videoSamples: snap.videoSampleCount,
                    audioSamples: snap.audioSampleCount,
                    lastVideoPTS: snap.lastVideoPTS,
                    lastAudioPTS: snap.lastAudioPTS,
                    secondsSinceProgress: snap.secondsSinceProgress
                )
                throw VideoPreparationFailure.compressionFailed
            }
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

    private static func pumpSamples(
        track: TranscodeTrack,
        from readerOutput: AVAssetReaderOutput,
        to writerInput: AVAssetWriterInput,
        readerSampleGate: ReaderSampleGate,
        duration: CMTime,
        progressTracker: TranscodeProgressTracker,
        onFrameAppended: (() -> Void)?,
        onProgress: ((Double) -> Void)?
    ) async throws {
        let totalSeconds = CMTimeGetSeconds(duration)
        let pump = WriterSamplePump(
            track: track,
            readerOutput: readerOutput,
            writerInput: writerInput,
            readerSampleGate: readerSampleGate,
            totalSeconds: totalSeconds,
            progressTracker: progressTracker,
            onFrameAppended: onFrameAppended,
            onProgress: onProgress
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let label = track == .video ? "video" : "audio"
            let queue = DispatchQueue(label: "com.tradetraxs.video-transcode.\(label).\(UUID().uuidString)")
            pump.writerInput.requestMediaDataWhenReady(on: queue) {
                pump.drain(continuation: continuation)
            }
        }
    }

    private static func exportWithSession(
        asset: AVAsset,
        outputURL: URL,
        presetName: String,
        videoComposition: AVVideoComposition?,
        onProgress: ((Double) -> Void)?
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoPreparationFailure.compressionFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition

        let progressTask: Task<Void, Never>? = onProgress.map { callback in
            Task {
                for await state in session.states(updateInterval: 0.1) {
                    guard !Task.isCancelled else { break }
                    if case .exporting(let progress) = state {
                        callback(Double(progress.fractionCompleted))
                    }
                }
            }
        }

        let exportSession = ExportSessionHandle(session)

        do {
            try await withTaskCancellationHandler {
                try await exportSession.session.export(to: outputURL, as: .mp4)
            } onCancel: {
                exportSession.cancel()
            }
            progressTask?.cancel()
            onProgress?(1)
        } catch {
            progressTask?.cancel()
            try? FileManager.default.removeItem(at: outputURL)
            if Task.isCancelled {
                throw VideoPreparationFailure.cancelled
            }
            throw VideoPreparationFailure.compressionFailed
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
