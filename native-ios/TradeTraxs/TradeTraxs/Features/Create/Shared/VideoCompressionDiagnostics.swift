import CoreGraphics
import Foundation

#if DEBUG
enum VideoCompressionDiagnostics {
    static func logSource(
        duration: Int,
        fileBytes: Int,
        orientedSize: CGSize,
        fps: Double,
        bitrate: Double,
        codec: String?
    ) {
        print(
            """
            [VideoCompression] stage=source sourceFPS=\(String(format: "%.2f", fps)) \
            resolution=\(Int(orientedSize.width))x\(Int(orientedSize.height)) \
            bitrate=\(Int(bitrate)) \
            duration=\(duration) \
            fileBytes=\(fileBytes) \
            codec=\(codec ?? "unknown")
            """
        )
    }

    static func logDecision(
        mode: String,
        reason: String,
        targetFPS: Double,
        targetVideoBitrate: Int
    ) {
        print(
            """
            [VideoCompression] stage=decision mode=\(mode) reason=\(reason) \
            targetFPS=\(String(format: "%.2f", targetFPS)) \
            targetVideoBitrate=\(targetVideoBitrate)
            """
        )
    }

    static func logOutput(
        sourceFPS: Double,
        targetFPS: Double,
        outputFPS: Double,
        sourceDuration: Int,
        outputDuration: Int,
        sourceBytes: Int,
        outputBytes: Int,
        outputBitrate: Double,
        outputFrameCount: Int? = nil
    ) {
        let ratio = sourceBytes > 0 ? Double(outputBytes) / Double(sourceBytes) : 0
        var extras = ""
        if let outputFrameCount {
            extras = " outputFrameCount=\(outputFrameCount)"
        }
        print(
            """
            [VideoCompression] stage=output sourceFPS=\(String(format: "%.2f", sourceFPS)) \
            targetFPS=\(String(format: "%.2f", targetFPS)) \
            outputFPS=\(String(format: "%.2f", outputFPS)) \
            sourceDuration=\(sourceDuration) \
            outputDuration=\(outputDuration) \
            outputBitrate=\(Int(outputBitrate)) \
            sourceBytes=\(sourceBytes) \
            outputBytes=\(outputBytes) \
            compressionRatio=\(String(format: "%.3f", ratio))\(extras)
            """
        )
    }
}
#else
enum VideoCompressionDiagnostics {
    static func logSource(
        duration: Int,
        fileBytes: Int,
        orientedSize: CGSize,
        fps: Double,
        bitrate: Double,
        codec: String?
    ) {}

    static func logDecision(
        mode: String,
        reason: String,
        targetFPS: Double,
        targetVideoBitrate: Int
    ) {}

    static func logOutput(
        sourceFPS: Double,
        targetFPS: Double,
        outputFPS: Double,
        sourceDuration: Int,
        outputDuration: Int,
        sourceBytes: Int,
        outputBytes: Int,
        outputBitrate: Double,
        outputFrameCount: Int? = nil
    ) {}
}
#endif
