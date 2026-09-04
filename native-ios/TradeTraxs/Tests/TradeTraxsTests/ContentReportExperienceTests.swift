import XCTest
@testable import TradeTraxs

final class ContentReportExperienceTests: XCTestCase {
    func testDetailContentLinkReportTargetUsesOwnerID() {
        let owner = ProfileID("owner-1")
        let target = DetailContentLink.post(PostID("p1")).reportTarget(ownerID: owner)
        XCTAssertEqual(target.type, .post)
        XCTAssertEqual(target.targetID, "p1")
        XCTAssertEqual(target.reportedUserID, owner)
    }

    func testContentReportSheetViewModelSubmitSuccess() async {
        let repository = StubContentReportRepository(result: .init(reportID: "r1", wasDuplicate: false))
        let request = ContentReportRequest(
            target: .user(ProfileID("u2")),
            subjectTitle: "this user"
        )
        let viewModel = await MainActor.run {
            ContentReportSheetViewModel(request: request, repository: repository)
        }
        await MainActor.run {
            viewModel.selectReason(.spam)
        }
        await viewModel.submit()
        let phase = await MainActor.run { viewModel.phase }
        if case .succeeded(let wasDuplicate) = phase {
            XCTAssertFalse(wasDuplicate)
        } else {
            XCTFail("Expected success phase, got \(phase)")
        }
        XCTAssertEqual(repository.submitCount, 1)
    }

    func testContentReportSheetViewModelDuplicateSuccess() async {
        let repository = StubContentReportRepository(result: .init(reportID: nil, wasDuplicate: true))
        let request = ContentReportRequest(
            target: .story(StoryID("s1"), ownerID: ProfileID("u2")),
            subjectTitle: "this story"
        )
        let viewModel = await MainActor.run {
            ContentReportSheetViewModel(request: request, repository: repository)
        }
        await MainActor.run {
            viewModel.selectReason(.inappropriate)
        }
        await viewModel.submit()
        let phase = await MainActor.run { viewModel.phase }
        if case .succeeded(let wasDuplicate) = phase {
            XCTAssertTrue(wasDuplicate)
        } else {
            XCTFail("Expected duplicate success phase, got \(phase)")
        }
    }

    func testContentReportPresenterTracksActiveRequest() async {
        let presenter = await MainActor.run { ContentReportPresenter() }
        let request = ContentReportRequest(
            target: .comment(CommentID("c1"), authorID: ProfileID("u2")),
            subjectTitle: "this comment"
        )
        await MainActor.run {
            presenter.present(request)
            XCTAssertEqual(presenter.activeRequest?.target, request.target)
            presenter.dismiss()
            XCTAssertNil(presenter.activeRequest)
        }
    }
}

private final class StubContentReportRepository: ContentReportRepository, @unchecked Sendable {
    var result: ContentReportSubmissionResult
    private(set) var submitCount = 0

    init(result: ContentReportSubmissionResult) {
        self.result = result
    }

    func submit(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportSubmissionResult {
        submitCount += 1
        return result
    }
}
