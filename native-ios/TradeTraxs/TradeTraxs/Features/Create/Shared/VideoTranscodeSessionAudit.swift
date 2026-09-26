import AVFoundation
import Foundation

#if DEBUG
nonisolated enum VideoTranscodeSessionAudit {
    nonisolated static func logWriterConfiguration(
        outputFileType: String,
        videoCodec: String,
        videoWidth: Int,
        videoHeight: Int,
        videoBitrate: Int,
        videoBitrateIsExportPolicyOnly: Bool = false,
        expectedFPS: Double,
        audioFormat: String,
        audioSampleRate: Int,
        audioChannels: Int,
        audioBitrate: Int,
        videoSourceFormatHint: String,
        audioSourceFormatHint: String,
        writerShouldOptimizeForNetworkUse: Bool
    ) {
        let bitrateLabel = videoBitrateIsExportPolicyOnly
            ? "videoBitratePolicy=\(videoBitrate) exportEncoderBitrateConfigured=false"
            : "videoBitrate=\(videoBitrate)"
        print(
            """
            [VideoWriterConfiguration] outputFileType=\(outputFileType) videoCodec=\(videoCodec) \
            videoWidth=\(videoWidth) videoHeight=\(videoHeight) \(bitrateLabel) \
            expectedFPS=\(String(format: "%.3f", expectedFPS)) audioFormat=\(audioFormat) \
            audioSampleRate=\(audioSampleRate) audioChannels=\(audioChannels) audioBitrate=\(audioBitrate) \
            videoSourceFormatHint=\(videoSourceFormatHint) audioSourceFormatHint=\(audioSourceFormatHint) \
            writerShouldOptimizeForNetworkUse=\(writerShouldOptimizeForNetworkUse)
            """
        )
    }

    nonisolated static func logSessionStart(
        sessionStartTimeSeconds: Double,
        sessionStartCount: Int,
        assetDurationSeconds: Double,
        videoTrackTimeRangeStart: Double?,
        videoTrackTimeRangeDuration: Double?,
        audioTrackTimeRangeStart: Double?,
        audioTrackTimeRangeDuration: Double?,
        endSessionWillBeCalled: Bool
    ) {
        func fmt(_ value: Double?) -> String {
            value.map { String(format: "%.6f", $0) } ?? "unknown"
        }
        print(
            """
            [VideoTranscodeSession] sessionStartTimeSeconds=\(String(format: "%.6f", sessionStartTimeSeconds)) \
            sessionStartInvocations=\(sessionStartCount) assetDurationSeconds=\(String(format: "%.6f", assetDurationSeconds)) \
            videoTrackTimeRangeStart=\(fmt(videoTrackTimeRangeStart)) \
            videoTrackTimeRangeDuration=\(fmt(videoTrackTimeRangeDuration)) \
            audioTrackTimeRangeStart=\(fmt(audioTrackTimeRangeStart)) \
            audioTrackTimeRangeDuration=\(fmt(audioTrackTimeRangeDuration)) \
            endSessionWillBeCalled=\(endSessionWillBeCalled)
            """
        )
    }

    nonisolated static func logSessionEnd(
        videoEndTimeSeconds: Double?,
        audioEndTimeSeconds: Double?,
        endSourceTimeSeconds: Double
    ) {
        func fmt(_ value: Double?) -> String {
            value.map { String(format: "%.6f", $0) } ?? "unknown"
        }
        print(
            """
            [VideoTranscodeSession] endSessionCalled=true \
            videoEndTime=\(fmt(videoEndTimeSeconds)) audioEndTime=\(fmt(audioEndTimeSeconds)) \
            endSourceTimeSeconds=\(String(format: "%.6f", endSourceTimeSeconds))
            """
        )
    }

    nonisolated static func logFinalizationReadiness(
        videoPumpFinished: Bool,
        audioPumpFinished: Bool,
        hasAudioTrack: Bool,
        readerStatus: String,
        writerStatus: String,
        videoInputReadyForMoreMediaData: Bool,
        audioInputReadyForMoreMediaData: Bool?,
        finishWritingAboutToStart: Bool
    ) {
        let audioReady = audioInputReadyForMoreMediaData.map(String.init) ?? "n/a"
        print(
            """
            [VideoTranscodeFinalizationAudit] videoPumpFinished=\(videoPumpFinished) \
            audioPumpFinished=\(audioPumpFinished) hasAudioTrack=\(hasAudioTrack) \
            readerStatus=\(readerStatus) writerStatus=\(writerStatus) \
            videoInputReadyForMoreMediaData=\(videoInputReadyForMoreMediaData) \
            audioInputReadyForMoreMediaData=\(audioReady) \
            finishWritingAboutToStart=\(finishWritingAboutToStart) \
            concurrentPumpTasksCompleted=true
            """
        )
    }
}
#else
nonisolated enum VideoTranscodeSessionAudit {
    nonisolated static func logWriterConfiguration(
        outputFileType: String,
        videoCodec: String,
        videoWidth: Int,
        videoHeight: Int,
        videoBitrate: Int,
        videoBitrateIsExportPolicyOnly: Bool = false,
        expectedFPS: Double,
        audioFormat: String,
        audioSampleRate: Int,
        audioChannels: Int,
        audioBitrate: Int,
        videoSourceFormatHint: String,
        audioSourceFormatHint: String,
        writerShouldOptimizeForNetworkUse: Bool
    ) {}

    nonisolated static func logSessionStart(
        sessionStartTimeSeconds: Double,
        sessionStartCount: Int,
        assetDurationSeconds: Double,
        videoTrackTimeRangeStart: Double?,
        videoTrackTimeRangeDuration: Double?,
        audioTrackTimeRangeStart: Double?,
        audioTrackTimeRangeDuration: Double?,
        endSessionWillBeCalled: Bool
    ) {}

    nonisolated static func logSessionEnd(
        videoEndTimeSeconds: Double?,
        audioEndTimeSeconds: Double?,
        endSourceTimeSeconds: Double
    ) {}

    nonisolated static func logFinalizationReadiness(
        videoPumpFinished: Bool,
        audioPumpFinished: Bool,
        hasAudioTrack: Bool,
        readerStatus: String,
        writerStatus: String,
        videoInputReadyForMoreMediaData: Bool,
        audioInputReadyForMoreMediaData: Bool?,
        finishWritingAboutToStart: Bool
    ) {}
}
#endif
