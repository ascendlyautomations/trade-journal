import AVFoundation
import CoreGraphics
import CoreMedia
import XCTest
@testable import TradeTraxs

final class VideoDeliveryExporterTests: XCTestCase {
    func testTargetOutputSizePortrait4KScalesTo1080x1920() {
        let size = VideoDeliveryExporter.targetOutputSize(for: CGSize(width: 2160, height: 3840))
        XCTAssertEqual(size.width, 1080, accuracy: 1)
        XCTAssertEqual(size.height, 1920, accuracy: 1)
    }

    func testTargetOutputSizeLandscape4KScalesTo1920x1080() {
        let size = VideoDeliveryExporter.targetOutputSize(for: CGSize(width: 3840, height: 2160))
        XCTAssertEqual(size.width, 1920, accuracy: 1)
        XCTAssertEqual(size.height, 1080, accuracy: 1)
    }

    func testTargetOutputSizeSquare1080Unchanged() {
        let size = VideoDeliveryExporter.targetOutputSize(for: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(size.width, 1080, accuracy: 0.5)
        XCTAssertEqual(size.height, 1080, accuracy: 0.5)
    }

    func testTargetOutputSize720pUnchanged() {
        let size = VideoDeliveryExporter.targetOutputSize(for: CGSize(width: 1280, height: 720))
        XCTAssertEqual(size.width, 1280, accuracy: 0.5)
        XCTAssertEqual(size.height, 720, accuracy: 0.5)
    }

    func testTargetFrameRatePreserves23976() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 23.976), 23.976, accuracy: 0.001)
    }

    func testTargetFrameRatePreserves24() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 24), 24)
    }

    func testTargetFrameRatePreserves25() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 25), 25)
    }

    func testTargetFrameRatePreserves2997() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 29.97), 29.97, accuracy: 0.001)
    }

    func testTargetFrameRatePreserves30() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 30), 30)
    }

    func testTargetFrameRatePreserves30Point02() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 30.02), 30.02, accuracy: 0.001)
    }

    func testTargetFrameRatePreserves50() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 50), 50)
    }

    func testTargetFrameRatePreserves5994() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 59.94), 59.94, accuracy: 0.001)
    }

    func testTargetFrameRatePreserves60() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 60), 60)
    }

    func testTargetFrameRateCaps120To60() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 120), 60)
    }

    func testTargetFrameRateCaps240To60() {
        XCTAssertEqual(VideoDeliveryExporter.targetFrameRate(sourceFPS: 240), 60)
    }

    func testCompositionOutputFrameRatePreserves60() {
        XCTAssertEqual(
            VideoDeliveryExporter.compositionOutputFrameRate(sourceFPS: 60, targetFPS: 60),
            60,
            accuracy: 0.001
        )
    }

    func testCompositionOutputFrameRateCaps120To60() {
        XCTAssertEqual(
            VideoDeliveryExporter.compositionOutputFrameRate(sourceFPS: 120, targetFPS: 60),
            60,
            accuracy: 0.001
        )
    }

    func testCompositionOutputFrameRatePreserves30Point02() {
        XCTAssertEqual(
            VideoDeliveryExporter.compositionOutputFrameRate(sourceFPS: 30.02, targetFPS: 30.02),
            30.02,
            accuracy: 0.001
        )
    }

    func testFrameDurationPreserves3002WithoutForcing2997() {
        let duration = VideoDeliveryExporter.frameDuration(for: 30.02)
        let fps = Double(duration.timescale) / Double(duration.value)
        XCTAssertEqual(fps, 30.02, accuracy: 0.05)
    }

    func testFrameDurationUsesNTSCFor2997() {
        let duration = VideoDeliveryExporter.frameDuration(for: 29.97)
        let fps = Double(duration.timescale) / Double(duration.value)
        XCTAssertEqual(fps, 29.97, accuracy: 0.01)
    }

    func testTargetVideoBitrate1080p30() {
        XCTAssertEqual(
            VideoDeliveryExporter.targetVideoBitrate(longEdge: 1920, targetFPS: 30),
            4_500_000
        )
    }

    func testTargetVideoBitrate1080p60() {
        XCTAssertEqual(
            VideoDeliveryExporter.targetVideoBitrate(longEdge: 1920, targetFPS: 60),
            5_500_000
        )
    }

    func testTargetVideoBitrate720p30() {
        XCTAssertEqual(
            VideoDeliveryExporter.targetVideoBitrate(longEdge: 1280, targetFPS: 30),
            2_800_000
        )
    }

    func testTargetVideoBitrate720p60() {
        XCTAssertEqual(
            VideoDeliveryExporter.targetVideoBitrate(longEdge: 1280, targetFPS: 60),
            3_500_000
        )
    }

    func testDeliveryExportPresetName1080Delivery() {
        let target = VideoDeliveryExporter.DeliveryTarget(
            outputSize: CGSize(width: 1080, height: 1920),
            outputFrameRate: 30,
            videoBitrate: 4_500_000,
            audioBitrate: 128_000
        )
        XCTAssertEqual(
            VideoDeliveryExporter.deliveryExportPresetName(for: target),
            AVAssetExportPreset1920x1080
        )
    }

    func testDeliveryExportPresetName720Delivery() {
        let target = VideoDeliveryExporter.DeliveryTarget(
            outputSize: CGSize(width: 720, height: 1280),
            outputFrameRate: 30,
            videoBitrate: 2_800_000,
            audioBitrate: 128_000
        )
        XCTAssertEqual(
            VideoDeliveryExporter.deliveryExportPresetName(for: target),
            AVAssetExportPreset1280x720
        )
    }

    func testValidateOutputFrameRateRejectsSilentDropTo20FPS() {
        XCTAssertThrowsError(
            try VideoDeliveryExporter.validateOutputFrameRate(
                sourceFPS: 30.02,
                targetFPS: 30.02,
                outputFPS: 20.73,
                outputFrameCount: 332,
                outputDurationSeconds: 16,
                intentionalHighFPSReduction: false
            )
        ) { error in
            XCTAssertEqual(error as? VideoPreparationFailure, .outputValidationFailed)
        }
    }

    func testValidateOutputFrameRateRejects60To30AccidentalHalving() {
        XCTAssertThrowsError(
            try VideoDeliveryExporter.validateOutputFrameRate(
                sourceFPS: 60,
                targetFPS: 60,
                outputFPS: 30,
                outputFrameCount: 480,
                outputDurationSeconds: 16,
                intentionalHighFPSReduction: false
            )
        ) { error in
            XCTAssertEqual(error as? VideoPreparationFailure, .outputValidationFailed)
        }
    }

    func testValidateOutputFrameRateAccepts2997ClassOutput() throws {
        XCTAssertNoThrow(
            try VideoDeliveryExporter.validateOutputFrameRate(
                sourceFPS: 30.02,
                targetFPS: 30.02,
                outputFPS: 29.97,
                outputFrameCount: 480,
                outputDurationSeconds: 16,
                intentionalHighFPSReduction: false
            )
        )
    }

    func testValidateOutputFrameRateAcceptsIntentional120To60Reduction() throws {
        XCTAssertNoThrow(
            try VideoDeliveryExporter.validateOutputFrameRate(
                sourceFPS: 120,
                targetFPS: 60,
                outputFPS: 60,
                outputFrameCount: 960,
                outputDurationSeconds: 16,
                intentionalHighFPSReduction: true
            )
        )
    }

    func testValidateOutputFrameRateUsesMeasuredFrameCount() {
        XCTAssertThrowsError(
            try VideoDeliveryExporter.validateOutputFrameRate(
                sourceFPS: 30,
                targetFPS: 30,
                outputFPS: 30,
                outputFrameCount: 332,
                outputDurationSeconds: 16,
                intentionalHighFPSReduction: false
            )
        ) { error in
            XCTAssertEqual(error as? VideoPreparationFailure, .outputValidationFailed)
        }
    }

    func testDecideTranscodeForOversized4K60() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 30,
            orientedSize: CGSize(width: 2160, height: 3840),
            frameRate: 60,
            estimatedBitrate: 25_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 80_000_000,
            containerExtension: "mov",
            isMP4Container: false
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, _) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .transcode)
        XCTAssertEqual(target.outputFrameRate, 60, accuracy: 0.001)
    }

    func testDecidePassthroughFor1080p60EfficientlyEncoded() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 20,
            orientedSize: CGSize(width: 1920, height: 1080),
            frameRate: 60,
            estimatedBitrate: 3_500_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 9_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .passthrough)
        XCTAssertTrue(reason.contains("mp4"))
        XCTAssertEqual(target.videoBitrate, 5_500_000)
    }

    func testDecideTranscodeWhenTrackBitrateUnderReportsFileAverage() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 30,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 30,
            estimatedBitrate: 2_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 17_560_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .transcode)
        XCTAssertTrue(reason.contains("bitrate"))
    }

    func testDecideTranscodeFor1080p60HighBitrate() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 20,
            orientedSize: CGSize(width: 1920, height: 1080),
            frameRate: 60,
            estimatedBitrate: 30_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 75_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .transcode)
        XCTAssertTrue(reason.contains("bitrate"))
    }

    func testDecideTranscodeFor1080p120FPSReduction() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 20,
            orientedSize: CGSize(width: 1920, height: 1080),
            frameRate: 120,
            estimatedBitrate: 5_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 12_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .transcode)
        XCTAssertTrue(reason.contains("fps"))
        XCTAssertEqual(target.outputFrameRate, 60, accuracy: 0.001)
    }

    func testDecidePassthroughWhenAudioCodecDiffersButVideoIsEfficient() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 41,
            orientedSize: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            estimatedBitrate: 1_020_000,
            videoCodec: "avc1",
            audioCodec: "lpcm",
            hasAudio: true,
            fileBytes: 5_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .passthrough)
        XCTAssertTrue(reason.contains("mp4"))
    }

    func testTranscodeVideoBitrateCapsToSourceEffectiveRate() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 41,
            orientedSize: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            estimatedBitrate: 1_020_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 5_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let ceiling = VideoDeliveryExporter.targetVideoBitrate(longEdge: 1920, targetFPS: 30)
        let capped = VideoDeliveryExporter.transcodeVideoBitrate(profile: profile, ceiling: ceiling)
        XCTAssertEqual(capped, 892_000)
        XCTAssertLessThan(capped, ceiling)
    }

    func testDecidePassthroughForDeliveryReadyMP4() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 20,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 30,
            estimatedBitrate: 4_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 10_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .passthrough)
        XCTAssertTrue(reason.contains("mp4"))
    }

    func testDecideRemuxForCompatibleMOV() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 20,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 30,
            estimatedBitrate: 4_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 10_000_000,
            containerExtension: "mov",
            isMP4Container: false
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, _) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .remux)
    }

    func testDecideTranscodeForHighBitrate1080p() {
        let profile = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 30,
            orientedSize: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            estimatedBitrate: 30_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 50_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let target = VideoDeliveryExporter.deliveryTarget(for: profile)
        let (mode, reason) = VideoDeliveryExporter.decideDeliveryMode(profile: profile, target: target)
        XCTAssertEqual(mode, .transcode)
        XCTAssertTrue(reason.contains("bitrate"))
    }

    func testValidateTranscodeEffectivenessRejectsLargerOrEqualOutput() {
        let source = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 48,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 30,
            estimatedBitrate: 15_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 89_536_947,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let output = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 48,
            orientedSize: CGSize(width: 720, height: 1280),
            frameRate: 30,
            estimatedBitrate: 15_100_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 90_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )

        XCTAssertThrowsError(
            try VideoDeliveryExporter.validateTranscodeEffectiveness(
                source: source,
                output: output,
                decisionReason: "audio+bitrate"
            )
        ) { error in
            XCTAssertEqual(error as? VideoPreparationFailure, .compressionFailed)
        }
    }

    func testValidateTranscodeEffectivenessAllowsAnySmallerOutput() throws {
        let source = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 52,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 51.81,
            estimatedBitrate: 9_310_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 60_895_101,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let output = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 52,
            orientedSize: CGSize(width: 720, height: 1280),
            frameRate: 51.81,
            estimatedBitrate: 8_070_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 52_911_970,
            containerExtension: "mp4",
            isMP4Container: true
        )

        XCTAssertNoThrow(
            try VideoDeliveryExporter.validateTranscodeEffectiveness(
                source: source,
                output: output,
                decisionReason: "bitrate"
            )
        )
    }

    func testValidateTranscodeEffectivenessAllowsMaterialCompression() throws {
        let source = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 48,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 30,
            estimatedBitrate: 15_000_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 89_536_947,
            containerExtension: "mp4",
            isMP4Container: true
        )
        let output = VideoDeliveryExporter.SourceProfile(
            durationSeconds: 48,
            orientedSize: CGSize(width: 1080, height: 1920),
            frameRate: 30,
            estimatedBitrate: 4_800_000,
            videoCodec: "avc1",
            audioCodec: "mp4a",
            hasAudio: true,
            fileBytes: 28_000_000,
            containerExtension: "mp4",
            isMP4Container: true
        )

        XCTAssertNoThrow(
            try VideoDeliveryExporter.validateTranscodeEffectiveness(
                source: source,
                output: output,
                decisionReason: "audio+bitrate"
            )
        )
    }

    func testMediaVideoSourceLimitIsHigherThanFinalUploadLimit() {
        XCTAssertGreaterThan(
            MediaVideoPreparation.maxSourceFileBytes,
            MediaVideoPreparation.maxFinalUploadBytes
        )
    }
}
