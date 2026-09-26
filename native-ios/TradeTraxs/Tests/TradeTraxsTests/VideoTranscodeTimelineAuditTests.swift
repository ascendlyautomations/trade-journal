import CoreMedia
import XCTest
@testable import TradeTraxs

final class VideoTranscodeTimelineAuditTests: XCTestCase {
    func testEndTimeUsesLastPTSPlusDuration() {
        var stats = VideoTranscodeTimelineAudit.TrackStats(
            sampleCount: 2,
            firstPTS: 0,
            lastPTS: 51.589,
            lastSampleDuration: 0.019
        )
        XCTAssertEqual(VideoTranscodeTimelineAudit.endTime(for: stats) ?? 0, 51.608, accuracy: 0.001)
    }

    func testMonotonicityViolationDetected() {
        var stats = VideoTranscodeTimelineAudit.TrackStats()
        appendSyntheticSample(pts: 0, dts: 0, duration: 0.02, into: &stats)
        appendSyntheticSample(pts: 0.5, dts: 0.5, duration: 0.02, into: &stats)
        appendSyntheticSample(pts: 0.4, dts: 0.4, duration: 0.02, into: &stats)
        XCTAssertEqual(stats.monotonicityViolations, 1)
        XCTAssertEqual(stats.duplicateOrRegressingCount, 1)
    }

    func testSummaryAudioVideoEndDelta() {
        var video = VideoTranscodeTimelineAudit.TrackStats(
            sampleCount: 100,
            firstPTS: 0,
            lastPTS: 51.589,
            lastSampleDuration: 0.019
        )
        var audio = VideoTranscodeTimelineAudit.TrackStats(
            sampleCount: 50,
            firstPTS: 0,
            lastPTS: 46.254,
            lastSampleDuration: 0.023
        )
        let summary = VideoTranscodeTimelineAudit.Summary(
            assetDurationSeconds: 52,
            videoTrackTimeRangeStart: 0,
            videoTrackTimeRangeDuration: 52,
            audioTrackTimeRangeStart: 0,
            audioTrackTimeRangeDuration: 46.5,
            video: video,
            audio: audio
        )
        XCTAssertEqual(summary.videoEndTime ?? 0, 51.608, accuracy: 0.01)
        XCTAssertEqual(summary.audioEndTime ?? 0, 46.277, accuracy: 0.01)
        XCTAssertEqual(summary.audioVideoEndDelta ?? 0, 5.331, accuracy: 0.05)
    }

    func testClassifyWriterFinishFailureDistinguishesNilError() {
        XCTAssertEqual(
            VideoTranscodeFailureDiagnostics.classifyWriterFinishFailure(writerError: nil),
            "writerFailedWithNilError"
        )
        XCTAssertEqual(
            VideoTranscodeFailureDiagnostics.classifyWriterFinishFailure(
                writerError: NSError(domain: "Test", code: 1)
            ),
            "writerFailedWithNSError"
        )
    }

    func testFailedOutputInspectionMissingFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-output-\(UUID().uuidString).mp4")
        let inspection = await VideoTranscodeFailureDiagnostics.inspectFailedOutput(at: url)
        XCTAssertFalse(inspection.exists)
        XCTAssertFalse(inspection.readableAsAVURLAsset)
    }

    // MARK: - Helpers

    private func appendSyntheticSample(
        pts: Double,
        dts: Double,
        duration: Double,
        into stats: inout VideoTranscodeTimelineAudit.TrackStats
    ) {
        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 600),
            decodeTimeStamp: CMTime(seconds: dts, preferredTimescale: 600)
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: nil,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else {
            XCTFail("Failed to create synthetic sample buffer")
            return
        }
        VideoTranscodeTimelineAudit.accumulate(sampleBuffer: sampleBuffer, into: &stats)
    }
}
