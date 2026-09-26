import AVFoundation
import Foundation

/// Structured AVAssetReader/AVAssetWriter failure logging for Clip preparation (DEBUG console).
nonisolated enum VideoTranscodeFailureDiagnostics {
    struct ErrorDetails: Equatable, Sendable {
        var domain: String
        var code: Int
        var description: String
        var failureReason: String
        var recoverySuggestion: String
        var underlying: String
    }

    struct Snapshot: Equatable, Sendable {
        var stage: String
        var writerStatus: String
        var errorDetails: ErrorDetails?
        var readerStatus: String
        var readerErrorDetails: ErrorDetails?
        var outputURL: String
        var outputFileExists: Bool
        var outputFileBytes: Int64
        var mediaType: String?
        var sampleIndex: Int?
        var presentationTimeSeconds: Double?
        var extra: String?
    }

    nonisolated static func errorDetails(from error: Error?) -> ErrorDetails? {
        guard let error else { return nil }
        let ns = error as NSError
        let underlying: String
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            underlying = "\(under.domain) code=\(under.code) \(under.localizedDescription)"
        } else {
            underlying = "none"
        }
        return ErrorDetails(
            domain: ns.domain,
            code: ns.code,
            description: ns.localizedDescription,
            failureReason: ns.localizedFailureReason ?? "none",
            recoverySuggestion: ns.localizedRecoverySuggestion ?? "none",
            underlying: underlying
        )
    }

    nonisolated static func outputFileInfo(at url: URL) -> (exists: Bool, bytes: Int64) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return (false, 0)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return (true, Int64(values?.fileSize ?? 0))
    }

    struct FailedOutputInspection: Equatable, Sendable {
        var url: String
        var exists: Bool
        var bytes: Int64
        var readableAsAVURLAsset: Bool
        var isPlayable: Bool
        var durationSeconds: Double?
        var videoTrackCount: Int
        var audioTrackCount: Int
        var videoTrackDurationSeconds: Double?
        var audioTrackDurationSeconds: Double?
    }

    nonisolated static func classifyWriterFinishFailure(writerError: Error?) -> String {
        writerError == nil ? "writerFailedWithNilError" : "writerFailedWithNSError"
    }

    nonisolated static func inspectFailedOutput(at url: URL) async -> FailedOutputInspection {
        let fileInfo = outputFileInfo(at: url)
        guard fileInfo.exists else {
            return FailedOutputInspection(
                url: url.path,
                exists: false,
                bytes: 0,
                readableAsAVURLAsset: false,
                isPlayable: false,
                durationSeconds: nil,
                videoTrackCount: 0,
                audioTrackCount: 0,
                videoTrackDurationSeconds: nil,
                audioTrackDurationSeconds: nil
            )
        }

        let asset = AVURLAsset(url: url)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            var videoDuration: Double?
            if let track = videoTracks.first {
                let range = try await track.load(.timeRange)
                videoDuration = CMTimeGetSeconds(range.duration)
            }
            var audioDuration: Double?
            if let track = audioTracks.first {
                let range = try await track.load(.timeRange)
                audioDuration = CMTimeGetSeconds(range.duration)
            }
            return FailedOutputInspection(
                url: url.path,
                exists: true,
                bytes: fileInfo.bytes,
                readableAsAVURLAsset: true,
                isPlayable: isPlayable,
                durationSeconds: durationSeconds.isFinite ? durationSeconds : nil,
                videoTrackCount: videoTracks.count,
                audioTrackCount: audioTracks.count,
                videoTrackDurationSeconds: videoDuration,
                audioTrackDurationSeconds: audioDuration
            )
        } catch {
            return FailedOutputInspection(
                url: url.path,
                exists: true,
                bytes: fileInfo.bytes,
                readableAsAVURLAsset: false,
                isPlayable: false,
                durationSeconds: nil,
                videoTrackCount: 0,
                audioTrackCount: 0,
                videoTrackDurationSeconds: nil,
                audioTrackDurationSeconds: nil
            )
        }
    }

    nonisolated static func logFailedOutputInspection(_ inspection: FailedOutputInspection) {
        #if DEBUG
        func fmt(_ value: Double?) -> String {
            value.map { String(format: "%.6f", $0) } ?? "unknown"
        }
        print(
            """
            [VideoFailedOutputAudit] url=\(inspection.url) exists=\(inspection.exists) bytes=\(inspection.bytes) \
            readableAsAVURLAsset=\(inspection.readableAsAVURLAsset) isPlayable=\(inspection.isPlayable) \
            duration=\(fmt(inspection.durationSeconds)) videoTracks=\(inspection.videoTrackCount) \
            audioTracks=\(inspection.audioTrackCount) videoTrackDuration=\(fmt(inspection.videoTrackDurationSeconds)) \
            audioTrackDuration=\(fmt(inspection.audioTrackDurationSeconds))
            """
        )
        print(
            """
            [VideoFailedOutputInspection] url=\(inspection.url) exists=\(inspection.exists) bytes=\(inspection.bytes) \
            readableAsAVURLAsset=\(inspection.readableAsAVURLAsset) isPlayable=\(inspection.isPlayable) \
            duration=\(fmt(inspection.durationSeconds)) videoTracks=\(inspection.videoTrackCount) \
            audioTracks=\(inspection.audioTrackCount) videoTrackDuration=\(fmt(inspection.videoTrackDurationSeconds)) \
            audioTrackDuration=\(fmt(inspection.audioTrackDurationSeconds))
            """
        )
        #endif
    }

    nonisolated static func sampleTimingDescription(_ sampleBuffer: CMSampleBuffer) -> (
        pts: Double?,
        dts: Double?,
        duration: Double?
    ) {
        let pts = VideoTranscodeTimelineAudit.seconds(from: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let dts = VideoTranscodeTimelineAudit.seconds(from: CMSampleBufferGetDecodeTimeStamp(sampleBuffer))
        let duration = VideoTranscodeTimelineAudit.seconds(from: CMSampleBufferGetDuration(sampleBuffer))
        return (pts, dts, duration)
    }

    nonisolated static func primaryFailureKind(
        readerStatus: AVAssetReader.Status,
        writerStatus: AVAssetWriter.Status
    ) -> String {
        switch (readerStatus, writerStatus) {
        case (.failed, .failed):
            return "readerAndWriterFailed"
        case (.failed, _):
            return "readerFailed"
        case (_, .failed):
            return "writerFailed"
        default:
            return "unknown"
        }
    }

    nonisolated static func makeSnapshot(
        stage: String,
        writer: AVAssetWriter?,
        reader: AVAssetReader?,
        outputURL: URL,
        writerError: Error? = nil,
        readerError: Error? = nil,
        mediaType: String? = nil,
        sampleIndex: Int? = nil,
        presentationTimeSeconds: Double? = nil,
        extra: String? = nil
    ) -> Snapshot {
        let fileInfo = outputFileInfo(at: outputURL)
        let resolvedWriterError = writerError ?? writer?.error
        let resolvedReaderError = readerError ?? reader?.error
        return Snapshot(
            stage: stage,
            writerStatus: writer.map { "\($0.status)" } ?? "unknown",
            errorDetails: errorDetails(from: resolvedWriterError),
            readerStatus: reader.map { "\($0.status)" } ?? "unknown",
            readerErrorDetails: errorDetails(from: resolvedReaderError),
            outputURL: outputURL.path,
            outputFileExists: fileInfo.exists,
            outputFileBytes: fileInfo.bytes,
            mediaType: mediaType,
            sampleIndex: sampleIndex,
            presentationTimeSeconds: presentationTimeSeconds,
            extra: extra
        )
    }

    nonisolated static func log(_ snapshot: Snapshot) {
        #if DEBUG
        let writerErr = snapshot.errorDetails
        let readerErr = snapshot.readerErrorDetails
        let pts = snapshot.presentationTimeSeconds.map { String(format: "%.6f", $0) } ?? "unknown"
        let sample = snapshot.sampleIndex.map(String.init) ?? "unknown"
        let media = snapshot.mediaType ?? "unknown"
        let extra = snapshot.extra ?? "none"
        print(
            """
            [VideoTranscodeFailure] stage=\(snapshot.stage) \
            writerStatus=\(snapshot.writerStatus) \
            errorDomain=\(writerErr?.domain ?? "none") \
            errorCode=\(writerErr.map { String($0.code) } ?? "none") \
            errorDescription=\(writerErr?.description ?? "none") \
            failureReason=\(writerErr?.failureReason ?? "none") \
            recoverySuggestion=\(writerErr?.recoverySuggestion ?? "none") \
            underlyingError=\(writerErr?.underlying ?? "none") \
            outputURL=\(snapshot.outputURL) \
            outputFileExists=\(snapshot.outputFileExists) \
            outputFileBytes=\(snapshot.outputFileBytes) \
            readerStatus=\(snapshot.readerStatus) \
            readerErrorDomain=\(readerErr?.domain ?? "none") \
            readerErrorCode=\(readerErr.map { String($0.code) } ?? "none") \
            readerErrorDescription=\(readerErr?.description ?? "none") \
            mediaType=\(media) sampleIndex=\(sample) pts=\(pts) extra=\(extra)
            """
        )
        #endif
    }

    nonisolated static func logFailure(
        stage: String,
        writer: AVAssetWriter?,
        reader: AVAssetReader?,
        outputURL: URL,
        writerError: Error? = nil,
        readerError: Error? = nil,
        mediaType: String? = nil,
        sampleIndex: Int? = nil,
        presentationTimeSeconds: Double? = nil,
        extra: String? = nil
    ) {
        log(
            makeSnapshot(
                stage: stage,
                writer: writer,
                reader: reader,
                outputURL: outputURL,
                writerError: writerError,
                readerError: readerError,
                mediaType: mediaType,
                sampleIndex: sampleIndex,
                presentationTimeSeconds: presentationTimeSeconds,
                extra: extra
            )
        )
    }

    nonisolated static func logExportFailure(
        stage: String,
        presetName: String,
        outputURL: URL,
        sessionError: Error?,
        extra: String? = nil
    ) {
        let fileInfo = outputFileInfo(at: outputURL)
        let err = errorDetails(from: sessionError)
        log(
            Snapshot(
                stage: stage,
                writerStatus: "exportSession",
                errorDetails: err,
                readerStatus: "n/a",
                readerErrorDetails: nil,
                outputURL: outputURL.path,
                outputFileExists: fileInfo.exists,
                outputFileBytes: fileInfo.bytes,
                mediaType: nil,
                sampleIndex: nil,
                presentationTimeSeconds: nil,
                extra: "preset=\(presetName) \(extra ?? "none")"
            )
        )
    }
}
