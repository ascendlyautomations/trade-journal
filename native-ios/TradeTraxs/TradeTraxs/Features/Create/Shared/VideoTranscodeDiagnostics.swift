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

    nonisolated static func logWriterFinishCompleted(status: String) {
        print("[VideoTranscode] writerFinishCompleted status=\(status)")
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
    nonisolated static func logWriterFinishCompleted(status: String) {}
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
}
#endif
