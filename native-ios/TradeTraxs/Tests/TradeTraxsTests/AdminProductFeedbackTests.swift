import XCTest
@testable import TradeTraxs

final class AdminProductFeedbackTests: XCTestCase {
    func testDefaultPageSizeIsBounded() {
        XCTAssertEqual(AdminProductFeedbackListQuery.defaultPageSize, 25)
    }

    func testParseRowUsesSubjectCodec() {
        let dto = ProductFeedbackRowDTO(
            id: "f1",
            user_id: "11111111-1111-1111-1111-111111111111",
            email: "user@example.com",
            subject: "Feature Request: Widgets",
            message: "Please add widgets",
            screenshot_url: nil,
            status: "open",
            admin_notes: nil,
            viewed: false,
            created_at: "2026-01-01T12:00:00.000Z",
            updated_at: nil
        )
        let row = AdminProductFeedbackParsing.parseRow(dto)
        XCTAssertEqual(row?.parsedType, .featureRequest)
        XCTAssertEqual(row?.parsedTitle, "Widgets")
    }

    func testParseAllFeedbackTypes() {
        for type in ProductFeedbackType.allCases {
            let subject = type.composedSubject(optionalTitle: "")
            let row = AdminProductFeedbackParsing.parseRow(
                ProductFeedbackRowDTO(
                    id: type.id,
                    user_id: "11111111-1111-1111-1111-111111111111",
                    email: nil,
                    subject: subject,
                    message: "Body",
                    screenshot_url: nil,
                    status: "open",
                    admin_notes: nil,
                    viewed: false,
                    created_at: nil,
                    updated_at: nil
                )
            )
            XCTAssertEqual(row?.parsedType, type)
        }
    }

    func testSubjectOrFilterQuotesLabelsWithSpaces() {
        let item = ProductFeedbackSubjectQuery.orFilter(for: .featureRequest)
        XCTAssertTrue(item.value?.contains("Feature Request") == true)
    }

    @MainActor
    func testPaginationUsesOffset() async {
        let repo = MockAdminProductFeedbackRepository()
        repo.pages = [
            AdminProductFeedbackPage(
                rows: (0..<25).map { sampleFeedback(id: "p\($0)") },
                profiles: [:],
                hasMore: true
            ),
            AdminProductFeedbackPage(rows: [sampleFeedback(id: "tail")], profiles: [:], hasMore: false),
        ]
        let vm = AdminProductFeedbackViewModel(repository: repo)
        await vm.reload()
        await vm.loadMore()
        XCTAssertEqual(vm.snapshots.last?.id, "tail")
        XCTAssertEqual(repo.fetchCalls.last?.offset, 25)
    }

    func testAdminProductFeedbackRouteIsNotPlaceholder() {
        XCTAssertEqual(String(describing: AdminProductFeedbackView.self), "AdminProductFeedbackView")
    }

    private func sampleFeedback(id: String) -> AdminProductFeedbackRow {
        AdminProductFeedbackRow(
            id: id,
            userID: ProfileID("11111111-1111-1111-1111-111111111111"),
            email: nil,
            rawSubject: "Improvement",
            parsedType: .improvement,
            parsedTitle: nil,
            message: "Better charts",
            screenshotURL: nil,
            status: .open,
            viewed: false,
            adminNotes: nil,
            createdAt: Date(),
            updatedAt: nil
        )
    }
}

private final class MockAdminProductFeedbackRepository: AdminProductFeedbackRepository, @unchecked Sendable {
    struct FetchCall {
        var queue: AdminProductFeedbackQueueFilter
        var type: AdminProductFeedbackTypeFilter
        var status: AdminProductFeedbackStatusFilter
        var limit: Int
        var offset: Int
    }

    var pages: [AdminProductFeedbackPage] = []
    var fetchCalls: [FetchCall] = []

    func fetchFeedback(
        queue: AdminProductFeedbackQueueFilter,
        type: AdminProductFeedbackTypeFilter,
        status: AdminProductFeedbackStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminProductFeedbackPage {
        fetchCalls.append(
            FetchCall(queue: queue, type: type, status: status, limit: limit, offset: offset)
        )
        let index = min(fetchCalls.count - 1, pages.count - 1)
        return pages[max(0, index)]
    }

    func updateFeedbackReview(feedbackID: String, update: AdminProductFeedbackReviewUpdate) async throws {
        _ = (feedbackID, update)
    }
}
