import AVFoundation
import XCTest
@testable import TradeTraxs

final class VideoTranscodeWriterConfigurationTests: XCTestCase {
    func testOutputContainerMatchesMP4Extension() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-delivery-\(UUID().uuidString).mp4")
        XCTAssertTrue(VideoTranscodeWriterConfiguration.validateOutputContainerURL(url))
        XCTAssertEqual(VideoTranscodeWriterConfiguration.outputFileType, .mp4)
    }

    func testOutputContainerRejectsMismatchedExtension() {
        let url = URL(fileURLWithPath: "/tmp/reel-delivery-\(UUID().uuidString).mov")
        XCTAssertFalse(VideoTranscodeWriterConfiguration.validateOutputContainerURL(url))
    }

    func testVideoSettingsDisableFrameReorderingDuringTranscode() {
        let settings = VideoTranscodeWriterConfiguration.makeVideoEncodingSettings(
            outputWidth: 1080,
            outputHeight: 1920,
            encodeBitrate: 5_500_000,
            encoderFrameRateHint: 52
        )
        XCTAssertFalse(settings.allowFrameReordering)
        let compression = settings.dictionary[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoAllowFrameReorderingKey] as? Bool, false)
    }

    func testTranscodeDoesNotOptimizeForNetworkUseDuringEncode() {
        XCTAssertFalse(VideoTranscodeWriterConfiguration.optimizeForNetworkUseDuringTranscode)
    }

    func testAudioSettingsNormalizeChannelsAndSampleRate() {
        let stereo = VideoTranscodeWriterConfiguration.makeAudioEncodingSettings(
            targetBitrate: 128_000,
            sourceChannelCount: 2,
            sourceSampleRate: 48_000
        )
        XCTAssertEqual(stereo.channelCount, 2)
        XCTAssertEqual(stereo.sampleRate, 48_000)

        let mono = VideoTranscodeWriterConfiguration.makeAudioEncodingSettings(
            targetBitrate: 128_000,
            sourceChannelCount: 1,
            sourceSampleRate: 44_100
        )
        XCTAssertEqual(mono.channelCount, 1)
        XCTAssertEqual(mono.sampleRate, 44_100)
    }

    func testSessionEndSourceTimeUsesMaxTrackEndTimeNotVideoOnly() {
        let summary = VideoTranscodeTimelineAudit.Summary(
            assetDurationSeconds: 51.686,
            videoTrackTimeRangeStart: 0,
            videoTrackTimeRangeDuration: 51.686,
            audioTrackTimeRangeStart: 0,
            audioTrackTimeRangeDuration: 51.686,
            video: VideoTranscodeTimelineAudit.TrackStats(
                sampleCount: 2373,
                firstPTS: 0,
                lastPTS: 51.647,
                lastSampleDuration: 0.019
            ),
            audio: VideoTranscodeTimelineAudit.TrackStats(
                sampleCount: 280,
                firstPTS: 0,
                lastPTS: 51.663,
                lastSampleDuration: 0.023
            )
        )
        XCTAssertEqual(summary.videoEndTime ?? 0, 51.666, accuracy: 0.001)
        XCTAssertEqual(summary.audioEndTime ?? 0, 51.686, accuracy: 0.001)
        let endSeconds = VideoTranscodeWriterConfiguration.sessionEndSeconds(from: summary)
        XCTAssertEqual(endSeconds, summary.audioEndTime ?? 0, accuracy: 0.0001)
        XCTAssertGreaterThan(endSeconds, summary.videoEndTime ?? 0)
    }

    func testWriterFinishFailureClassificationPreserved() {
        XCTAssertEqual(
            VideoTranscodeFailureDiagnostics.classifyWriterFinishFailure(writerError: nil),
            "writerFailedWithNilError"
        )
    }
}
