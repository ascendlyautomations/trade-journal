import XCTest
@testable import TradeTraxs

final class AdminSupportTicketsTests: XCTestCase {
    func testDefaultPageSizeIsBounded() {
        XCTAssertEqual(AdminSupportTicketListQuery.defaultPageSize, 25)
    }

    func testCategoryLabelIncludesBrokerIntegration() {
        XCTAssertEqual(SupportTicketDisplay.categoryLabel("broker_integration"), "Broker Integration")
        XCTAssertEqual(SupportTicketDisplay.categoryLabel("account"), "Account")
    }

    func testParseRowMapsDTO() {
        let dto = SupportTicketRowDTO(
            id: "t1",
            user_id: "11111111-1111-1111-1111-111111111111",
            email: "user@example.com",
            category: "broker_integration",
            subject: "Broker Integration support request",
            message: "Need help syncing",
            screenshot_url: "https://example.com/s.png",
            status: "open",
            priority: "normal",
            admin_notes: nil,
            viewed: false,
            created_at: "2026-01-01T12:00:00.000Z",
            updated_at: nil
        )
        let row = AdminSupportTicketParsing.parseRow(dto)
        XCTAssertEqual(row?.category, "broker_integration")
        XCTAssertEqual(row?.status, .open)
    }

    @MainActor
    func testPaginationUsesOffset() async {
        let repo = MockAdminSupportTicketsRepository()
        repo.pages = [
            AdminSupportTicketPage(
                rows: (0..<25).map { sampleTicket(id: "p\($0)") },
                profiles: [:],
                hasMore: true
            ),
            AdminSupportTicketPage(rows: [sampleTicket(id: "tail")], profiles: [:], hasMore: false),
        ]
        let vm = AdminSupportTicketsViewModel(repository: repo)
        await vm.reload()
        await vm.loadMore()
        XCTAssertEqual(vm.snapshots.last?.id, "tail")
        XCTAssertEqual(repo.fetchCalls.last?.offset, 25)
    }

    @MainActor
    func testReviewMutationUpdatesLocalSnapshot() async {
        let repo = MockAdminSupportTicketsRepository()
        let snapshot = AdminSupportTicketSnapshot(row: sampleTicket(id: "t1"), submitter: nil)
        let vm = AdminSupportTicketDetailViewModel(
            snapshot: snapshot,
            repository: repo,
            adminUsers: MockAdminUsersForSupportTickets(),
            session: MockSessionForAdminReview(userID: "22222222-2222-2222-2222-222222222222")
        )
        vm.draftViewed = true
        vm.draftStatus = .in_progress
        vm.draftAdminNotes = "Looking into this"
        let ok = await vm.saveReview()
        XCTAssertTrue(ok)
        XCTAssertTrue(vm.snapshot.row.viewed)
        XCTAssertEqual(vm.snapshot.row.status, .in_progress)
        XCTAssertNotNil(repo.lastReviewUpdate)
    }

    func testAdminSupportRouteIsNotPlaceholder() {
        XCTAssertEqual(String(describing: AdminSupportTicketsView.self), "AdminSupportTicketsView")
        XCTAssertNotEqual(String(describing: AdminProfileDestinationView.self), "AdminPlaceholderView")
    }

    private func sampleTicket(id: String) -> AdminSupportTicketRow {
        AdminSupportTicketRow(
            id: id,
            userID: ProfileID("11111111-1111-1111-1111-111111111111"),
            email: "user@example.com",
            category: "general",
            subject: "General support request",
            message: "Help",
            screenshotURL: nil,
            status: .open,
            priority: "normal",
            viewed: false,
            adminNotes: nil,
            createdAt: Date(),
            updatedAt: nil
        )
    }
}

private final class MockAdminSupportTicketsRepository: AdminSupportTicketsRepository, @unchecked Sendable {
    struct FetchCall {
        var queue: AdminSupportTicketQueueFilter
        var limit: Int
        var offset: Int
    }

    var pages: [AdminSupportTicketPage] = []
    var fetchCalls: [FetchCall] = []
    var lastReviewUpdate: AdminSupportTicketReviewUpdate?

    func fetchTickets(
        queue: AdminSupportTicketQueueFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminSupportTicketPage {
        fetchCalls.append(FetchCall(queue: queue, limit: limit, offset: offset))
        let index = min(fetchCalls.count - 1, pages.count - 1)
        return pages[max(0, index)]
    }

    func updateTicketReview(ticketID: String, update: AdminSupportTicketReviewUpdate) async throws {
        _ = ticketID
        lastReviewUpdate = update
    }
}

private struct MockAdminUsersForSupportTickets: AdminUsersRepository {
    func fetchDirectory(_ query: AdminUserDirectoryQuery) async throws -> AdminUserDirectoryPage {
        _ = query
        return AdminUserDirectoryPage(rows: [], total: 0)
    }

    func fetchActivityCounts(targetUserID: ProfileID) async throws -> AdminUserActivityCounts {
        _ = targetUserID
        return AdminUserActivityCounts(
            trades: 0,
            posts: 0,
            achievements: 0,
            feedback: 0,
            supportTickets: 0
        )
    }

    func banUser(targetUserID: ProfileID, adminUserID: ProfileID, reason: String) async throws {
        _ = (targetUserID, adminUserID, reason)
    }

    func unbanUser(targetUserID: ProfileID, adminUserID: ProfileID) async throws {
        _ = (targetUserID, adminUserID)
    }

    func fetchDeletionPreview(targetUserID: ProfileID) async throws -> AdminUserDeletionPreview {
        _ = targetUserID
        throw AppError.authentication(.sessionMissing)
    }

    func deleteUser(targetUserID: ProfileID) async throws {
        _ = targetUserID
    }
}

private struct MockSessionForAdminReview: SessionProviding {
    let userID: String

    var currentUserID: UserID? {
        get async { UserID(rawValue: userID) }
    }

    var accessToken: String? {
        get async { "token" }
    }
}
