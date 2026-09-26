import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

/// Legacy reader/writer encoding helpers (unit tests). Production transcode uses AVAssetExportSession.
nonisolated enum VideoTranscodeWriterConfiguration {
    nonisolated static let outputFileType: AVFileType = .mp4
    nonisolated static let outputPathExtension = "mp4"

    /// Fast-start moov relocation during an active H.264/AAC encode can fail at finishWriting (nil error) on device.
    nonisolated static let optimizeForNetworkUseDuringTranscode = false

    struct VideoEncodingSettings: Equatable {
        var width: Int
        var height: Int
        var bitrate: Int
        var encoderFrameRateHint: Int
        var allowFrameReordering: Bool
        var dictionary: [String: Any]

        static func == (lhs: VideoEncodingSettings, rhs: VideoEncodingSettings) -> Bool {
            lhs.width == rhs.width
                && lhs.height == rhs.height
                && lhs.bitrate == rhs.bitrate
                && lhs.encoderFrameRateHint == rhs.encoderFrameRateHint
                && lhs.allowFrameReordering == rhs.allowFrameReordering
        }
    }

    struct AudioEncodingSettings: Equatable {
        var sampleRate: Int
        var channelCount: Int
        var bitrate: Int
        var dictionary: [String: Any]

        static func == (lhs: AudioEncodingSettings, rhs: AudioEncodingSettings) -> Bool {
            lhs.sampleRate == rhs.sampleRate
                && lhs.channelCount == rhs.channelCount
                && lhs.bitrate == rhs.bitrate
        }
    }

    nonisolated static func validateOutputContainerURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == outputPathExtension
    }

    nonisolated static func makeVideoEncodingSettings(
        outputWidth: Int,
        outputHeight: Int,
        encodeBitrate: Int,
        encoderFrameRateHint: Int
    ) -> VideoEncodingSettings {
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: encodeBitrate,
            AVVideoMaxKeyFrameIntervalKey: max(1, encoderFrameRateHint) * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoExpectedSourceFrameRateKey: max(1, encoderFrameRateHint),
            AVVideoAllowFrameReorderingKey: false,
        ]
        let dictionary: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: compression,
        ]
        return VideoEncodingSettings(
            width: outputWidth,
            height: outputHeight,
            bitrate: encodeBitrate,
            encoderFrameRateHint: max(1, encoderFrameRateHint),
            allowFrameReordering: false,
            dictionary: dictionary
        )
    }

    nonisolated static func makeAudioEncodingSettings(
        targetBitrate: Int,
        sourceChannelCount: Int?,
        sourceSampleRate: Double?
    ) -> AudioEncodingSettings {
        let channels = normalizedAudioChannelCount(sourceChannelCount)
        let sampleRate = normalizedAudioSampleRate(sourceSampleRate)
        let dictionary: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: targetBitrate,
        ]
        return AudioEncodingSettings(
            sampleRate: sampleRate,
            channelCount: channels,
            bitrate: targetBitrate,
            dictionary: dictionary
        )
    }

    nonisolated static func normalizedAudioChannelCount(_ sourceChannels: Int?) -> Int {
        guard let sourceChannels, sourceChannels > 0 else { return 2 }
        return min(2, max(1, sourceChannels))
    }

    nonisolated static func normalizedAudioSampleRate(_ sourceRate: Double?) -> Int {
        guard let sourceRate, sourceRate > 0 else { return 44_100 }
        let candidates: [Double] = [44_100, 48_000]
        let nearest = candidates.min(by: { abs($0 - sourceRate) < abs($1 - sourceRate) }) ?? 44_100
        return Int(nearest)
    }

    /// Session end must not precede any appended sample — use max track end (last PTS + duration when known).
    nonisolated static func sessionEndSourceTime(from summary: VideoTranscodeTimelineAudit.Summary) -> CMTime {
        let endSeconds = sessionEndSeconds(from: summary)
        return CMTime(seconds: endSeconds, preferredTimescale: 60_000)
    }

    nonisolated static func sessionEndSeconds(from summary: VideoTranscodeTimelineAudit.Summary) -> Double {
        let trackEnds = [
            VideoTranscodeTimelineAudit.endTime(for: summary.video),
            VideoTranscodeTimelineAudit.endTime(for: summary.audio),
        ].compactMap { $0 }
        if let maxEnd = trackEnds.max() {
            return maxEnd
        }
        let ptsFallback = [summary.video.lastPTS, summary.audio.lastPTS].compactMap { $0 }
        if let maxPTS = ptsFallback.max() {
            return maxPTS
        }
        return summary.assetDurationSeconds
    }

    nonisolated static func audioFormatDetails(from formatDescriptions: [CMFormatDescription]) -> (channels: Int?, sampleRate: Double?) {
        guard let description = formatDescriptions.first else { return (nil, nil) }
        guard let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return (nil, nil)
        }
        let channels = Int(basic.mChannelsPerFrame)
        let sampleRate = basic.mSampleRate
        return (channels > 0 ? channels : nil, sampleRate > 0 ? sampleRate : nil)
    }
}
