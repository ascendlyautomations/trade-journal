import AVFoundation
import Foundation

#if DEBUG
enum VideoTranscodeDiagnostics {
    nonisolated static func logReaderStarted() {
        print("[VideoTranscode] readerStarted")
    }

    nonisolated static func logWriterStarted() {
        print("[VideoTranscode] writerStarted")
    }

    nonisolated static func logVideoPumpStarted() {
        print("[VideoTranscode] videoPumpStarted")
    }

    nonisolated static func logVideoProgress(samples: Int, pts: Double, writerReady: Bool) {
        print(
            """
            [VideoTranscode] videoProgress samples=\(samples) \
            pts=\(String(format: "%.3f", pts)) writerReady=\(writerReady)
            """
        )
    }

    nonisolated static func logVideoPumpFinished(samples: Int) {
        print("[VideoTranscode] videoPumpFinished samples=\(samples)")
    }

    nonisolated static func logAudioPumpStarted() {
        print("[VideoTranscode] audioPumpStarted")
    }

    nonisolated static func logAudioProgress(samples: Int, pts: Double, writerReady: Bool) {
        print(
            """
            [VideoTranscode] audioProgress samples=\(samples) \
            pts=\(String(format: "%.3f", pts)) writerReady=\(writerReady)
            """
        )
    }

    nonisolated static func logAudioPumpFinished(samples: Int) {
        print("[VideoTranscode] audioPumpFinished samples=\(samples)")
    }

    nonisolated static func logInputsMarkedFinished() {
        print("[VideoTranscode] inputsMarkedFinished")
    }

    nonisolated static func logWriterFinishStarted() {
        print("[VideoTranscode] writerFinishStarted")
    }

    nonisolated static func logWriterFinishCompleted(status: String, writerErrorSummary: String? = nil) {
        let err = writerErrorSummary ?? "none"
        print("[VideoTranscode] writerFinishCompleted status=\(status) writerError=\(err)")
    }

    nonisolated static func logStall(
        readerStatus: String,
        writerStatus: String,
        videoReady: Bool,
        audioReady: Bool,
        videoSamples: Int,
        audioSamples: Int,
        lastVideoPTS: Double,
        lastAudioPTS: Double,
        secondsSinceProgress: TimeInterval
    ) {
        print(
            """
            [VideoTranscode] stallDetected readerStatus=\(readerStatus) \
            writerStatus=\(writerStatus) \
            videoReady=\(videoReady) audioReady=\(audioReady) \
            videoSamples=\(videoSamples) audioSamples=\(audioSamples) \
            lastVideoPTS=\(String(format: "%.3f", lastVideoPTS)) \
            lastAudioPTS=\(String(format: "%.3f", lastAudioPTS)) \
            secondsSinceProgress=\(String(format: "%.1f", secondsSinceProgress))
            """
        )
    }

    nonisolated static func logExportSessionStarted(
        preset: String,
        outputURL: URL,
        targetSize: CGSize,
        targetFrameRate: Double
    ) {
        print(
            """
            [VideoTranscode] mode=exportSession preset=\(preset) \
            outputURL=\(outputURL.lastPathComponent) \
            renderSize=\(Int(targetSize.width))x\(Int(targetSize.height)) \
            targetFPS=\(String(format: "%.3f", targetFrameRate))
            """
        )
    }

    nonisolated static func logExportSessionFinished(status: String, errorSummary: String) {
        print("[VideoTranscode] exportSessionFinished status=\(status) error=\(errorSummary)")
    }

    nonisolated static func logExportSetup(
        stage: String,
        detail: String
    ) {
        print("[VideoTranscode] exportSetup stage=\(stage) \(detail)")
    }

    nonisolated static func logExportCompatiblePresets(_ presets: [String], preferred: String) {
        let joined = presets.isEmpty ? "none" : presets.joined(separator: ",")
        print(
            """
            [VideoTranscode] exportCompatiblePresets preferred=\(preferred) \
            count=\(presets.count) presets=\(joined)
            """
        )
    }

    nonisolated static func logExportSessionCreated(
        preset: String,
        status: String,
        supportedFileTypes: [String],
        mp4Supported: Bool,
        compositionRenderSize: String
    ) {
        let types = supportedFileTypes.isEmpty ? "none" : supportedFileTypes.joined(separator: ",")
        print(
            """
            [VideoTranscode] exportSessionCreated preset=\(preset) status=\(status) \
            supportedFileTypes=\(types) mp4Supported=\(mp4Supported) \
            compositionRenderSize=\(compositionRenderSize)
            """
        )
    }

    nonisolated static func logExportStarting(status: String, outputFileType: String) {
        print(
            """
            [VideoTranscode] exportStarting sessionStatus=\(status) \
            outputFileType=\(outputFileType)
            """
        )
    }

    nonisolated static func logExportCancelled() {
        print("[VideoTranscode] exportCancelled")
    }

    nonisolated static func logCompletedOutputCheck(outputURL: URL, exists: Bool, fileBytes: Int64) {
        print(
            """
            [VideoTranscode] completedOutputCheck outputURL=\(outputURL.lastPathComponent) \
            exists=\(exists) fileBytes=\(fileBytes)
            """
        )
    }

    nonisolated static func logCompletedOutputAccepted(fileBytes: Int64) {
        print("[VideoTranscode] completedOutputAccepted fileBytes=\(fileBytes)")
    }

    nonisolated static func logCompletedOutputRejected(reason: String) {
        print("[VideoTranscode] completedOutputRejected reason=\(reason)")
    }

    nonisolated static func logExportWithSessionReturned(outputURL: URL, fileBytes: Int64) {
        print(
            """
            [VideoTranscode] exportWithSessionReturned output=\(outputURL.lastPathComponent) \
            bytes=\(fileBytes)
            """
        )
    }
}
#else
enum VideoTranscodeDiagnostics {
    nonisolated static func logReaderStarted() {}
    nonisolated static func logWriterStarted() {}
    nonisolated static func logVideoPumpStarted() {}
    nonisolated static func logVideoProgress(samples: Int, pts: Double, writerReady: Bool) {}
    nonisolated static func logVideoPumpFinished(samples: Int) {}
    nonisolated static func logAudioPumpStarted() {}
    nonisolated static func logAudioProgress(samples: Int, pts: Double, writerReady: Bool) {}
    nonisolated static func logAudioPumpFinished(samples: Int) {}
    nonisolated static func logInputsMarkedFinished() {}
    nonisolated static func logWriterFinishStarted() {}
    nonisolated static func logWriterFinishCompleted(status: String, writerErrorSummary: String? = nil) {}
    nonisolated static func logStall(
        readerStatus: String,
        writerStatus: String,
        videoReady: Bool,
        audioReady: Bool,
        videoSamples: Int,
        audioSamples: Int,
        lastVideoPTS: Double,
        lastAudioPTS: Double,
        secondsSinceProgress: TimeInterval
    ) {}

    nonisolated static func logExportSessionStarted(
        preset: String,
        outputURL: URL,
        targetSize: CGSize,
        targetFrameRate: Double
    ) {}

    nonisolated static func logExportSessionFinished(status: String, errorSummary: String) {}

    nonisolated static func logExportSetup(stage: String, detail: String) {}

    nonisolated static func logExportCompatiblePresets(_ presets: [String], preferred: String) {}

    nonisolated static func logExportSessionCreated(
        preset: String,
        status: String,
        supportedFileTypes: [String],
        mp4Supported: Bool,
        compositionRenderSize: String
    ) {}

    nonisolated static func logExportStarting(status: String, outputFileType: String) {}

    nonisolated static func logExportCancelled() {}

    nonisolated static func logCompletedOutputCheck(outputURL: URL, exists: Bool, fileBytes: Int64) {}

    nonisolated static func logCompletedOutputAccepted(fileBytes: Int64) {}

    nonisolated static func logCompletedOutputRejected(reason: String) {}

    nonisolated static func logExportWithSessionReturned(outputURL: URL, fileBytes: Int64) {}
}
#endif
