import AVFoundation
import Foundation

/// Shared reel/clip delivery encoding — all native upload paths must use this before Storage upload.
enum ReelEncodingPipeline {
    struct ResolvedUploadVideo: Sendable {
        var fileURL: URL
        var byteCount: Int
        var durationSeconds: Int
        /// Temporary files to delete after upload attempt (excluding the draft's existing delivery URL when reused).
        var ephemeralURLs: [URL]
    }

    /// Copies prepared delivery media into a coordinator-owned temp file for background publish.
    static func captureUploadSnapshot(
        from draft: ReelDraft,
        publishID: String,
        captionOverride: String? = nil
    ) throws -> ReelDraftSnapshot {
        let preparedURL = draft.localVideoURL
        let preparedExists = FileManager.default.fileExists(atPath: preparedURL.path)
        let preparedBytes = preparedExists
            ? ((try? preparedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            : 0

        let sourceURL = draft.ownedSourceURL
        let sourceExists = sourceURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let sourceBytes: Int = {
            guard let sourceURL, sourceExists else { return 0 }
            return (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }()

        ReelHandoffDiagnostics.log(
            sourceURLExists: sourceExists,
            preparedURLExists: preparedExists,
            sourceBytes: sourceBytes,
            preparedBytes: preparedBytes
        )

        guard preparedExists, preparedBytes > 0 else {
            throw AppError.unknown(message: "Prepared video is no longer available.")
        }

        let ownedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-upload-\(publishID).mp4")
        try? FileManager.default.removeItem(at: ownedURL)
        try FileManager.default.copyItem(at: preparedURL, to: ownedURL)

        return ReelDraftSnapshot(
            selectionID: draft.selectionID,
            ownedSourceURL: nil,
            localVideoURL: ownedURL,
            contentType: "video/mp4",
            byteCount: sourceBytes,
            durationSeconds: draft.durationSeconds,
            thumbnailJPEG: draft.thumbnailJPEG,
            caption: captionOverride ?? draft.caption,
            linkedTradeID: draft.linkedTradeID
        )
    }

    /// Import-time optimization (Create Reel, Add Trade clip picker).
    static func prepareForUpload(
        from sourceURL: URL,
        contentType: String?,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> MediaVideoPreparation.PreparedLocalVideo {
        let started = ContinuousClock.now
        let prepared = try await encodeDeliveryAsset(
            from: sourceURL,
            contentType: contentType,
            onProgress: onProgress
        )
        let encodeMs = milliseconds(since: started)
        await logEncodeResult(
            sourceURL: sourceURL,
            outputURL: prepared.fileURL,
            encodeDurationMs: encodeMs
        )
        return prepared
    }

    /// Publish-time — reuse import-time delivery file when valid; never re-encode unnecessarily.
    static func resolveUploadVideo(
        draft: ReelDraft,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> ResolvedUploadVideo {
        let localURL = draft.localVideoURL
        let exists = FileManager.default.fileExists(atPath: localURL.path)
        let bytes = exists
            ? ((try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            : 0

        if exists, bytes > 0 {
            let localAsset = AVURLAsset(url: localURL)
            if let localProfile = try? await VideoDeliveryExporter.inspectSource(
                asset: localAsset,
                fileURL: localURL
            ) {
                let target = VideoDeliveryExporter.deliveryTarget(for: localProfile)
                if shouldReusePreparedDelivery(draft: draft, profile: localProfile) {
                    ReelResolveDiagnostics.log(
                        selectedURL: localURL,
                        exists: true,
                        bytes: localProfile.fileBytes,
                        decision: "reusePrepared",
                        reason: "import-time-delivery-ready"
                    )
                    onProgress?(1)
                    await logUpload(fileURL: localURL, durationSeconds: localProfile.durationSeconds)
                    return ResolvedUploadVideo(
                        fileURL: localURL,
                        byteCount: localProfile.fileBytes,
                        durationSeconds: localProfile.durationSeconds,
                        ephemeralURLs: []
                    )
                }

                let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(
                    profile: localProfile,
                    target: target
                )
                if mode == .passthrough, localProfile.isMP4Container {
                    ReelResolveDiagnostics.log(
                        selectedURL: localURL,
                        exists: true,
                        bytes: localProfile.fileBytes,
                        decision: "reusePrepared",
                        reason: reason
                    )
                    onProgress?(1)
                    await logUpload(fileURL: localURL, durationSeconds: localProfile.durationSeconds)
                    return ResolvedUploadVideo(
                        fileURL: localURL,
                        byteCount: localProfile.fileBytes,
                        durationSeconds: localProfile.durationSeconds,
                        ephemeralURLs: []
                    )
                }

                ReelResolveDiagnostics.log(
                    selectedURL: localURL,
                    exists: true,
                    bytes: localProfile.fileBytes,
                    decision: "reencodeSource",
                    reason: "local-needs-\(reason)"
                )
            } else {
                ReelResolveDiagnostics.log(
                    selectedURL: localURL,
                    exists: true,
                    bytes: bytes,
                    decision: "reusePrepared",
                    reason: "inspect-failed-fallback-bytes"
                )
                onProgress?(1)
                await logUpload(fileURL: localURL, durationSeconds: draft.durationSeconds)
                return ResolvedUploadVideo(
                    fileURL: localURL,
                    byteCount: bytes,
                    durationSeconds: draft.durationSeconds,
                    ephemeralURLs: []
                )
            }
        } else {
            ReelResolveDiagnostics.log(
                selectedURL: localURL,
                exists: false,
                bytes: 0,
                decision: "reencodeSource",
                reason: "prepared-file-missing"
            )
        }

        guard let sourceURL = draft.ownedSourceURL,
              FileManager.default.fileExists(atPath: sourceURL.path)
        else {
            throw AppError.unknown(message: "Prepared video is no longer available.")
        }

        let started = ContinuousClock.now
        let prepared = try await encodeDeliveryAsset(
            from: sourceURL,
            contentType: draft.contentType,
            onProgress: onProgress
        )
        let encodeMs = milliseconds(since: started)
        await logEncodeResult(
            sourceURL: sourceURL,
            outputURL: prepared.fileURL,
            encodeDurationMs: encodeMs
        )

        var ephemeral: [URL] = []
        if prepared.fileURL != draft.localVideoURL {
            ephemeral.append(prepared.fileURL)
        }

        await logUpload(fileURL: prepared.fileURL, durationSeconds: prepared.durationSeconds)

        return ResolvedUploadVideo(
            fileURL: prepared.fileURL,
            byteCount: prepared.byteCount,
            durationSeconds: prepared.durationSeconds,
            ephemeralURLs: ephemeral
        )
    }

    static func cleanupEphemeralFiles(_ urls: [URL], preserving preserved: Set<URL> = []) {
        for url in urls where !preserved.contains(url) {
            MediaVideoPreparation.cleanupTemporaryFile(at: url)
        }
    }

    // MARK: - Private

    private static func shouldReusePreparedDelivery(
        draft: ReelDraft,
        profile: VideoDeliveryExporter.SourceProfile
    ) -> Bool {
        guard profile.fileBytes > 0,
              profile.durationSeconds > 0,
              profile.durationSeconds <= MediaVideoPreparation.maxDurationSeconds,
              profile.fileBytes <= MediaVideoPreparation.maxFinalUploadBytes
        else { return false }

        if abs(profile.durationSeconds - draft.durationSeconds) > 2 { return false }

        let byteDelta = abs(profile.fileBytes - draft.byteCount)
        let byteTolerance = max(64 * 1024, Int(Double(max(draft.byteCount, 1)) * 0.2))
        guard byteDelta <= byteTolerance || profile.fileBytes <= draft.byteCount else { return false }

        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        return VideoDeliveryExporter.isDeliveryCompatibleVideo(profile: profile, target: target)
    }

    private static func encodeDeliveryAsset(
        from sourceURL: URL,
        contentType: String?,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> MediaVideoPreparation.PreparedLocalVideo {
        try await MediaVideoPreparation.prepareLocalVideo(
            from: sourceURL,
            contentType: contentType,
            onProgress: onProgress
        )
    }

    private static func logEncodeResult(
        sourceURL: URL,
        outputURL: URL,
        encodeDurationMs: Double
    ) async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let outputAsset = AVURLAsset(url: outputURL)
        guard
            let source = try? await VideoDeliveryExporter.inspectSource(asset: sourceAsset, fileURL: sourceURL),
            let output = try? await VideoDeliveryExporter.inspectSource(asset: outputAsset, fileURL: outputURL)
        else { return }

        ReelEncodeDiagnostics.log(
            sourceMB: megabytes(source.fileBytes),
            outputMB: megabytes(output.fileBytes),
            sizeChangePercent: sizeChangePercent(sourceBytes: source.fileBytes, outputBytes: output.fileBytes),
            sourceResolution: resolution(source.orientedSize),
            outputResolution: resolution(output.orientedSize),
            sourceBitrate: Int(source.effectiveBitrate),
            outputBitrate: Int(output.effectiveBitrate),
            sourceFPS: source.frameRate,
            outputFPS: output.frameRate,
            encodeDurationMs: encodeDurationMs
        )
    }

    static func logUpload(fileURL: URL, durationSeconds: Int) async {
        let asset = AVURLAsset(url: fileURL)
        guard let profile = try? await VideoDeliveryExporter.inspectSource(asset: asset, fileURL: fileURL) else {
            return
        }
        ReelEncodeDiagnostics.logUpload(
            fileMB: megabytes(profile.fileBytes),
            resolution: resolution(profile.orientedSize),
            bitrate: Int(profile.effectiveBitrate),
            duration: durationSeconds
        )
    }

    private static func megabytes(_ bytes: Int) -> Double {
        Double(bytes) / (1024 * 1024)
    }

    private static func resolution(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    private static func sizeChangePercent(sourceBytes: Int, outputBytes: Int) -> Double {
        guard sourceBytes > 0 else { return 0 }
        return (Double(outputBytes - sourceBytes) / Double(sourceBytes)) * 100
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }
}

#if DEBUG
enum ReelHandoffDiagnostics {
    static func log(
        sourceURLExists: Bool,
        preparedURLExists: Bool,
        sourceBytes: Int,
        preparedBytes: Int
    ) {
        print(
            """
            [REEL_HANDOFF] sourceURLExists=\(sourceURLExists) \
            preparedURLExists=\(preparedURLExists) \
            sourceBytes=\(sourceBytes) \
            preparedBytes=\(preparedBytes)
            """
        )
    }
}

enum ReelResolveDiagnostics {
    static func log(
        selectedURL: URL,
        exists: Bool,
        bytes: Int,
        decision: String,
        reason: String
    ) {
        print(
            """
            [REEL_RESOLVE] selectedURL=\(selectedURL.lastPathComponent) \
            exists=\(exists) \
            bytes=\(bytes) \
            decision=\(decision) \
            reason=\(reason)
            """
        )
    }
}

enum ReelEncodeDiagnostics {
    static func log(
        sourceMB: Double,
        outputMB: Double,
        sizeChangePercent: Double,
        sourceResolution: String,
        outputResolution: String,
        sourceBitrate: Int,
        outputBitrate: Int,
        sourceFPS: Double,
        outputFPS: Double,
        encodeDurationMs: Double
    ) {
        print(
            """
            [REEL_ENCODE] sourceMB=\(String(format: "%.2f", sourceMB)) \
            outputMB=\(String(format: "%.2f", outputMB)) \
            sizeChangePercent=\(String(format: "%+.1f", sizeChangePercent)) \
            sourceResolution=\(sourceResolution) \
            outputResolution=\(outputResolution) \
            sourceBitrate=\(sourceBitrate) \
            outputBitrate=\(outputBitrate) \
            sourceFPS=\(String(format: "%.2f", sourceFPS)) \
            outputFPS=\(String(format: "%.2f", outputFPS)) \
            encodeDurationMs=\(String(format: "%.0f", encodeDurationMs))
            """
        )
    }

    static func logUpload(fileMB: Double, resolution: String, bitrate: Int, duration: Int) {
        print(
            """
            [REEL_UPLOAD] fileMB=\(String(format: "%.2f", fileMB)) \
            resolution=\(resolution) \
            bitrate=\(bitrate) \
            duration=\(duration)
            """
        )
    }
}
#else
enum ReelHandoffDiagnostics {
    static func log(
        sourceURLExists: Bool,
        preparedURLExists: Bool,
        sourceBytes: Int,
        preparedBytes: Int
    ) {}
}

enum ReelResolveDiagnostics {
    static func log(
        selectedURL: URL,
        exists: Bool,
        bytes: Int,
        decision: String,
        reason: String
    ) {}
}

enum ReelEncodeDiagnostics {
    static func log(
        sourceMB: Double,
        outputMB: Double,
        sizeChangePercent: Double,
        sourceResolution: String,
        outputResolution: String,
        sourceBitrate: Int,
        outputBitrate: Int,
        sourceFPS: Double,
        outputFPS: Double,
        encodeDurationMs: Double
    ) {}

    static func logUpload(fileMB: Double, resolution: String, bitrate: Int, duration: Int) {}
}
#endif

extension VideoDeliveryExporter.SourceProfile {
    var effectiveBitrate: Double {
        VideoDeliveryExporter.effectiveBitrate(for: self)
    }
}
