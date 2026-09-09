import AVFoundation
import Foundation

#if DEBUG
enum VideoTranscodeDiagnostics {
    static func logReaderStarted() {
        print("[VideoTranscode] readerStarted")
    }

    static func logWriterStarted() {
        print("[VideoTranscode] writerStarted")
    }

    static func logVideoPumpStarted() {
        print("[VideoTranscode] videoPumpStarted")
    }

    static func logVideoProgress(samples: Int, pts: Double, writerReady: Bool) {
        print(
            """
            [VideoTranscode] videoProgress samples=\(samples) \
            pts=\(String(format: "%.3f", pts)) writerReady=\(writerReady)
            """
        )
    }

    static func logVideoPumpFinished(samples: Int) {
        print("[VideoTranscode] videoPumpFinished samples=\(samples)")
    }

    static func logAudioPumpStarted() {
        print("[VideoTranscode] audioPumpStarted")
    }

    static func logAudioProgress(samples: Int, pts: Double, writerReady: Bool) {
        print(
            """
            [VideoTranscode] audioProgress samples=\(samples) \
            pts=\(String(format: "%.3f", pts)) writerReady=\(writerReady)
            """
        )
    }

    static func logAudioPumpFinished(samples: Int) {
        print("[VideoTranscode] audioPumpFinished samples=\(samples)")
    }

    static func logInputsMarkedFinished() {
        print("[VideoTranscode] inputsMarkedFinished")
    }

    static func logWriterFinishStarted() {
        print("[VideoTranscode] writerFinishStarted")
    }

    static func logWriterFinishCompleted(status: String) {
        print("[VideoTranscode] writerFinishCompleted status=\(status)")
    }

    static func logStall(
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
    static func logReaderStarted() {}
    static func logWriterStarted() {}
    static func logVideoPumpStarted() {}
    static func logVideoProgress(samples: Int, pts: Double, writerReady: Bool) {}
    static func logVideoPumpFinished(samples: Int) {}
    static func logAudioPumpStarted() {}
    static func logAudioProgress(samples: Int, pts: Double, writerReady: Bool) {}
    static func logAudioPumpFinished(samples: Int) {}
    static func logInputsMarkedFinished() {}
    static func logWriterFinishStarted() {}
    static func logWriterFinishCompleted(status: String) {}
    static func logStall(
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
