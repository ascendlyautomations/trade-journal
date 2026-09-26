import AVFoundation
import XCTest
@testable import TradeTraxs

final class VideoTranscodeFailureDiagnosticsTests: XCTestCase {
    func testErrorDetailsExtractsUnderlyingNSError() {
        let underlying = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [
            NSLocalizedDescriptionKey: "Underlying failure",
        ])
        let top = NSError(domain: "NSOSStatusErrorDomain", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Top failure",
            NSLocalizedFailureReasonErrorKey: "Because encoding failed",
            NSLocalizedRecoverySuggestionErrorKey: "Try another clip",
            NSUnderlyingErrorKey: underlying,
        ])

        let details = VideoTranscodeFailureDiagnostics.errorDetails(from: top)
        XCTAssertEqual(details?.domain, "NSOSStatusErrorDomain")
        XCTAssertEqual(details?.code, -1)
        XCTAssertEqual(details?.description, "Top failure")
        XCTAssertEqual(details?.failureReason, "Because encoding failed")
        XCTAssertEqual(details?.recoverySuggestion, "Try another clip")
        XCTAssertTrue(details?.underlying.contains("AVFoundationErrorDomain") == true)
    }

    func testPrimaryFailureKindClassifiesReaderVsWriter() {
        XCTAssertEqual(
            VideoTranscodeFailureDiagnostics.primaryFailureKind(
                readerStatus: .failed,
                writerStatus: .writing
            ),
            "readerFailed"
        )
        XCTAssertEqual(
            VideoTranscodeFailureDiagnostics.primaryFailureKind(
                readerStatus: .completed,
                writerStatus: .failed
            ),
            "writerFailed"
        )
        XCTAssertEqual(
            VideoTranscodeFailureDiagnostics.primaryFailureKind(
                readerStatus: .failed,
                writerStatus: .failed
            ),
            "readerAndWriterFailed"
        )
    }

    func testOutputFileInfoReflectsExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcode-failure-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let missing = VideoTranscodeFailureDiagnostics.outputFileInfo(at: url)
        XCTAssertFalse(missing.exists)
        XCTAssertEqual(missing.bytes, 0)

        let payload = Data(repeating: 0xAB, count: 128)
        try payload.write(to: url)
        let existing = VideoTranscodeFailureDiagnostics.outputFileInfo(at: url)
        XCTAssertTrue(existing.exists)
        XCTAssertEqual(existing.bytes, 128)
    }

    func testFinishWritingFailureSnapshotPreservesInjectedWriterError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-finish-\(UUID().uuidString).mp4")
        let writerError = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [
            NSLocalizedDescriptionKey: "Cannot Save",
            NSLocalizedFailureReasonErrorKey: "Finishing failed",
        ])

        let snapshot = VideoTranscodeFailureDiagnostics.makeSnapshot(
            stage: "finishWriting",
            writer: nil,
            reader: nil,
            outputURL: url,
            writerError: writerError,
            readerError: nil,
            extra: "writerStatus=AVAssetWriterStatus(rawValue: 2)"
        )
        XCTAssertEqual(snapshot.stage, "finishWriting")
        XCTAssertEqual(snapshot.errorDetails?.domain, "AVFoundationErrorDomain")
        XCTAssertEqual(snapshot.errorDetails?.code, -11800)
        XCTAssertEqual(snapshot.errorDetails?.failureReason, "Finishing failed")
    }

    func testSuccessfulWriterFinalizationSnapshotHasNoWriterError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-success-\(UUID().uuidString).mp4")
        try Data(repeating: 0x01, count: 256).write(to: url)

        let snapshot = VideoTranscodeFailureDiagnostics.makeSnapshot(
            stage: "finishWriting",
            writer: nil,
            reader: nil,
            outputURL: url,
            writerError: nil,
            readerError: nil,
            extra: "writerStatus=AVAssetWriterStatus(rawValue: 3)"
        )
        XCTAssertNil(snapshot.errorDetails)
        XCTAssertTrue(snapshot.outputFileExists)
        XCTAssertEqual(snapshot.outputFileBytes, 256)

        try FileManager.default.removeItem(at: url)
    }

    func testAppendFailureStageIsDistinctFromFinishFailure() {
        let snapshot = VideoTranscodeFailureDiagnostics.makeSnapshot(
            stage: "sampleAppend",
            writer: nil,
            reader: nil,
            outputURL: URL(fileURLWithPath: "/tmp/out.mp4"),
            mediaType: "video",
            sampleIndex: 42,
            presentationTimeSeconds: 1.5
        )
        XCTAssertEqual(snapshot.stage, "sampleAppend")
        XCTAssertEqual(snapshot.mediaType, "video")
        XCTAssertEqual(snapshot.sampleIndex, 42)
        XCTAssertEqual(snapshot.presentationTimeSeconds, 1.5)
    }

    func testCleanupOnlyAfterFailedFinishLeavesDiagnosticsSnapshotFirst() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-order-\(UUID().uuidString).mp4")
        try Data(repeating: 0xCD, count: 64).write(to: url)

        let before = VideoTranscodeFailureDiagnostics.outputFileInfo(at: url)
        XCTAssertTrue(before.exists)
        XCTAssertEqual(before.bytes, 64)

        let snapshot = VideoTranscodeFailureDiagnostics.makeSnapshot(
            stage: "finishWriting",
            writer: nil,
            reader: nil,
            outputURL: url,
            writerError: NSError(domain: "TestDomain", code: 99, userInfo: [
                NSLocalizedDescriptionKey: "Simulated finish failure",
            ])
        )
        XCTAssertTrue(snapshot.outputFileExists)
        XCTAssertEqual(snapshot.outputFileBytes, 64)
        XCTAssertEqual(snapshot.errorDetails?.code, 99)

        try FileManager.default.removeItem(at: url)
        let after = VideoTranscodeFailureDiagnostics.outputFileInfo(at: url)
        XCTAssertFalse(after.exists)
    }
}
