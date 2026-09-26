import AVFoundation
import CoreMedia
import Foundation

/// Sample timestamp accumulation for reader/writer transcode (DEBUG summary + unit tests).
nonisolated enum VideoTranscodeTimelineAudit {
    struct TrackStats: Equatable, Sendable {
        var sampleCount: Int = 0
        var firstPTS: Double?
        var lastPTS: Double?
        var firstDTS: Double?
        var lastDTS: Double?
        var lastSampleDuration: Double?
        var monotonicityViolations: Int = 0
        var invalidTimestampCount: Int = 0
        var negativeTimestampCount: Int = 0
        var duplicateOrRegressingCount: Int = 0
        var gapCount: Int = 0
        var largestGapSeconds: Double = 0
    }

    struct Summary: Equatable, Sendable {
        var assetDurationSeconds: Double
        var videoTrackTimeRangeStart: Double?
        var videoTrackTimeRangeDuration: Double?
        var audioTrackTimeRangeStart: Double?
        var audioTrackTimeRangeDuration: Double?
        var video: TrackStats
        var audio: TrackStats

        var videoEndTime: Double? {
            VideoTranscodeTimelineAudit.endTime(for: video)
        }

        var audioEndTime: Double? {
            VideoTranscodeTimelineAudit.endTime(for: audio)
        }

        var audioVideoEndDelta: Double? {
            guard let videoEndTime, let audioEndTime else { return nil }
            return videoEndTime - audioEndTime
        }
    }

    nonisolated static func seconds(from time: CMTime) -> Double? {
        guard CMTimeCompare(time, .invalid) != 0 else { return nil }
        guard CMTimeCompare(time, .negativeInfinity) != 0 else { return nil }
        let value = CMTimeGetSeconds(time)
        guard value.isFinite else { return nil }
        return value
    }

    nonisolated static func endTime(for stats: TrackStats) -> Double? {
        guard let lastPTS = stats.lastPTS else { return nil }
        let duration = stats.lastSampleDuration ?? 0
        return lastPTS + max(0, duration)
    }

    nonisolated static func accumulate(sampleBuffer: CMSampleBuffer, into stats: inout TrackStats) {
        let ptsTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dtsTime = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        let durationTime = CMSampleBufferGetDuration(sampleBuffer)

        let pts = seconds(from: ptsTime)
        let dts = seconds(from: dtsTime)
        let duration = seconds(from: durationTime)

        if pts == nil && dts == nil {
            stats.invalidTimestampCount += 1
        }
        if let pts, pts < 0 {
            stats.negativeTimestampCount += 1
        }
        if let dts, dts < 0 {
            stats.negativeTimestampCount += 1
        }

        if let pts {
            if let previous = stats.lastPTS {
                if pts + 0.000_001 < previous {
                    stats.monotonicityViolations += 1
                    stats.duplicateOrRegressingCount += 1
                } else if abs(pts - previous) <= 0.000_001 {
                    stats.duplicateOrRegressingCount += 1
                } else if duration != nil || stats.lastSampleDuration != nil {
                    let gap = pts - previous - (stats.lastSampleDuration ?? 0)
                    if gap > 0.05 {
                        stats.gapCount += 1
                        stats.largestGapSeconds = max(stats.largestGapSeconds, gap)
                    }
                }
            }
            if stats.firstPTS == nil {
                stats.firstPTS = pts
            }
            stats.lastPTS = pts
        }

        if let dts {
            if stats.firstDTS == nil {
                stats.firstDTS = dts
            }
            stats.lastDTS = dts
        }

        if let duration, duration > 0 {
            stats.lastSampleDuration = duration
        }

        stats.sampleCount += 1
    }

    nonisolated static func timeRangeDescription(_ range: CMTimeRange?) -> (start: Double?, duration: Double?) {
        guard let range else { return (nil, nil) }
        let start = seconds(from: range.start)
        let duration = seconds(from: range.duration)
        return (start, duration)
    }

    nonisolated static func logSummary(_ summary: Summary) {
        #if DEBUG
        func fmt(_ value: Double?) -> String {
            value.map { String(format: "%.6f", $0) } ?? "unknown"
        }
        print(
            """
            [VideoTimelineAudit] assetDuration=\(fmt(summary.assetDurationSeconds)) \
            videoTrackTimeRangeStart=\(fmt(summary.videoTrackTimeRangeStart)) \
            videoTrackTimeRangeDuration=\(fmt(summary.videoTrackTimeRangeDuration)) \
            audioTrackTimeRangeStart=\(fmt(summary.audioTrackTimeRangeStart)) \
            audioTrackTimeRangeDuration=\(fmt(summary.audioTrackTimeRangeDuration)) \
            videoFirstPTS=\(fmt(summary.video.firstPTS)) videoLastPTS=\(fmt(summary.video.lastPTS)) \
            videoLastDuration=\(fmt(summary.video.lastSampleDuration)) videoEndTime=\(fmt(summary.videoEndTime)) \
            videoSamples=\(summary.video.sampleCount) videoMonotonicityViolations=\(summary.video.monotonicityViolations) \
            videoInvalidTimestamps=\(summary.video.invalidTimestampCount) videoNegativeTimestamps=\(summary.video.negativeTimestampCount) \
            videoDuplicateOrRegressing=\(summary.video.duplicateOrRegressingCount) videoGapCount=\(summary.video.gapCount) \
            audioFirstPTS=\(fmt(summary.audio.firstPTS)) audioLastPTS=\(fmt(summary.audio.lastPTS)) \
            audioLastDuration=\(fmt(summary.audio.lastSampleDuration)) audioEndTime=\(fmt(summary.audioEndTime)) \
            audioSamples=\(summary.audio.sampleCount) audioMonotonicityViolations=\(summary.audio.monotonicityViolations) \
            audioInvalidTimestamps=\(summary.audio.invalidTimestampCount) audioNegativeTimestamps=\(summary.audio.negativeTimestampCount) \
            audioDuplicateOrRegressing=\(summary.audio.duplicateOrRegressingCount) audioGapCount=\(summary.audio.gapCount) \
            audioVideoEndDelta=\(fmt(summary.audioVideoEndDelta))
            """
        )
        #endif
    }
}

/// Thread-safe timeline tracker used by concurrent video/audio pumps.
final class TranscodeTimelineTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var video = VideoTranscodeTimelineAudit.TrackStats()
    private var audio = VideoTranscodeTimelineAudit.TrackStats()

    func recordVideo(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        VideoTranscodeTimelineAudit.accumulate(sampleBuffer: sampleBuffer, into: &video)
        lock.unlock()
    }

    func recordAudio(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        VideoTranscodeTimelineAudit.accumulate(sampleBuffer: sampleBuffer, into: &audio)
        lock.unlock()
    }

    func makeSummary(
        assetDurationSeconds: Double,
        videoTrackTimeRange: CMTimeRange?,
        audioTrackTimeRange: CMTimeRange?
    ) -> VideoTranscodeTimelineAudit.Summary {
        lock.lock()
        defer { lock.unlock() }
        let videoRange = VideoTranscodeTimelineAudit.timeRangeDescription(videoTrackTimeRange)
        let audioRange = VideoTranscodeTimelineAudit.timeRangeDescription(audioTrackTimeRange)
        return VideoTranscodeTimelineAudit.Summary(
            assetDurationSeconds: assetDurationSeconds,
            videoTrackTimeRangeStart: videoRange.start,
            videoTrackTimeRangeDuration: videoRange.duration,
            audioTrackTimeRangeStart: audioRange.start,
            audioTrackTimeRangeDuration: audioRange.duration,
            video: video,
            audio: audio
        )
    }
}
