import XCTest
@testable import TradeTraxs

final class AdminBugReportsTests: XCTestCase {
    func testDefaultPageSizeIsBounded() {
        XCTAssertEqual(AdminBugReportListQuery.defaultPageSize, 25)
    }

    func testStatusAndSeverityValuesMatchSchema() {
        XCTAssertEqual(BugReportStatus.open.rawValue, "open")
        XCTAssertEqual(BugReportStatus.in_progress.rawValue, "in_progress")
        XCTAssertEqual(BugReportStatus.resolved.rawValue, "resolved")
        XCTAssertEqual(BugReportSeverity.critical.rawValue, "critical")
    }

    func testParseRowMapsDTO() {
        let dto = BugReportRowDTO(
            id: "b1",
            user_id: "11111111-1111-1111-1111-111111111111",
            title: "Crash",
            description: "Steps to reproduce",
            screenshot_url: "https://example.com/s.png",
            page_url: "ios://settings/support/bug-report",
            browser_info: "TradeTraxs 1.0 · iOS 18",
            severity: "high",
            status: "open",
            created_at: "2026-01-01T12:00:00.000Z",
            resolved_at: nil
        )
        let row = AdminBugReportParsing.parseRow(dto)
        XCTAssertEqual(row?.title, "Crash")
        XCTAssertEqual(row?.severity, .high)
        XCTAssertEqual(row?.pageURL, "ios://settings/support/bug-report")
    }

    func testEnvironmentLabelsForNativeMetadata() {
        XCTAssertEqual(
            BugReportDisplay.environmentContextLabel(pageURL: "ios://settings/support/bug-report"),
            "App route"
        )
        XCTAssertEqual(
            BugReportDisplay.environmentClientLabel(browserInfo: "TradeTraxs 1.0 · iPhone"),
            "App / device"
        )
        XCTAssertEqual(
            BugReportDisplay.environmentClientLabel(browserInfo: "Mozilla/5.0"),
            "Browser"
        )
    }

    @MainActor
    func testFilterChangeClearsStaleResults() async {
        let repo = MockAdminBugReportsRepository()
        repo.pages = [
            AdminBugReportPage(rows: [sampleRow(id: "a")], profiles: [:], hasMore: false),
            AdminBugReportPage(rows: [sampleRow(id: "b")], profiles: [:], hasMore: false),
        ]
        let vm = AdminBugReportsViewModel(repository: repo)
        await vm.reload()
        XCTAssertEqual(vm.snapshots.map(\.id), ["a"])
        vm.statusFilter = .resolved
        await vm.onFilterChanged()
        XCTAssertEqual(vm.snapshots.map(\.id), ["b"])
    }

    @MainActor
    func testPaginationUsesOffset() async {
        let repo = MockAdminBugReportsRepository()
        repo.pages = [
            AdminBugReportPage(
                rows: (0..<25).map { sampleRow(id: "p\($0)") },
                profiles: [:],
                hasMore: true
            ),
            AdminBugReportPage(rows: [sampleRow(id: "tail")], profiles: [:], hasMore: false),
        ]
        let vm = AdminBugReportsViewModel(repository: repo)
        await vm.reload()
        await vm.loadMore()
        XCTAssertEqual(vm.snapshots.last?.id, "tail")
        XCTAssertEqual(repo.fetchCalls.last?.offset, 25)
    }

    @MainActor
    func testStatusMutationUpdatesLocalRow() async {
        let repo = MockAdminBugReportsRepository()
        let snapshot = AdminBugReportSnapshot(row: sampleRow(id: "r1"), reporter: nil)
        let vm = AdminBugReportDetailViewModel(
            snapshot: snapshot,
            repository: repo,
            adminUsers: MockAdminUsersForBugReports()
        )
        vm.draftStatus = .in_progress
        let ok = await vm.saveStatus()
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.snapshot.row.status, .in_progress)
        XCTAssertEqual(repo.updatedStatus, .in_progress)
    }

    @MainActor
    func testMarkResolvedSetsResolvedAt() async {
        let repo = MockAdminBugReportsRepository()
        let snapshot = AdminBugReportSnapshot(row: sampleRow(id: "r1"), reporter: nil)
        let vm = AdminBugReportDetailViewModel(
            snapshot: snapshot,
            repository: repo,
            adminUsers: MockAdminUsersForBugReports()
        )
        let ok = await vm.markResolved()
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.snapshot.row.status, .resolved)
        XCTAssertNotNil(vm.snapshot.row.resolvedAt)
    }

    func testLoginShellRepositoryBlocksPrivilegedAccess() async {
        let repo = LoginShellAdminBugReportsRepositoryProbe()
        do {
            _ = try await repo.fetchReports(status: .open, severity: .all, limit: 25, offset: 0)
            XCTFail("Expected failure")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    private func sampleRow(id: String) -> AdminBugReportRow {
        AdminBugReportRow(
            id: id,
            userID: ProfileID("11111111-1111-1111-1111-111111111111"),
            title: "Title",
            description: "Description",
            screenshotURL: nil,
            pageURL: nil,
            browserInfo: nil,
            severity: .medium,
            status: .open,
            createdAt: Date(),
            resolvedAt: nil
        )
    }
}

private struct LoginShellAdminBugReportsRepositoryProbe: AdminBugReportsRepository {
    func fetchReports(
        status: AdminBugReportStatusFilter,
        severity: AdminBugReportSeverityFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminBugReportPage {
        throw AppError.authentication(.sessionMissing)
    }

    func updateReportStatus(
        reportID: String,
        status: BugReportStatus,
        previousStatus: BugReportStatus,
        existingResolvedAt: Date?
    ) async throws {
        throw AppError.authentication(.sessionMissing)
    }
}

private final class MockAdminBugReportsRepository: AdminBugReportsRepository, @unchecked Sendable {
    struct FetchCall: Sendable {
        var status: AdminBugReportStatusFilter
        var severity: AdminBugReportSeverityFilter
        var limit: Int
        var offset: Int
    }

    var pages: [AdminBugReportPage] = []
    var fetchCalls: [FetchCall] = []
    var updatedStatus: BugReportStatus?

    func fetchReports(
        status: AdminBugReportStatusFilter,
        severity: AdminBugReportSeverityFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminBugReportPage {
        fetchCalls.append(FetchCall(status: status, severity: severity, limit: limit, offset: offset))
        let index = min(fetchCalls.count - 1, max(0, pages.count - 1))
        return pages[index]
    }

    func updateReportStatus(
        reportID: String,
        status: BugReportStatus,
        previousStatus: BugReportStatus,
        existingResolvedAt: Date?
    ) async throws {
        _ = (reportID, previousStatus, existingResolvedAt)
        updatedStatus = status
    }
}

private struct MockAdminUsersForBugReports: AdminUsersRepository {
    func fetchDirectory(_ query: AdminUserDirectoryQuery) async throws -> AdminUserDirectoryPage {
        _ = query
        return AdminUserDirectoryPage(rows: [], total: 0)
    }

    func fetchActivityCounts(targetUserID: ProfileID) async throws -> AdminUserActivityCounts {
        throw AppError.authentication(.sessionMissing)
    }

    func banUser(targetUserID: ProfileID, adminUserID: ProfileID, reason: String) async throws {}
    func unbanUser(targetUserID: ProfileID, adminUserID: ProfileID) async throws {}
    func fetchDeletionPreview(targetUserID: ProfileID) async throws -> AdminUserDeletionPreview {
        throw AppError.authentication(.sessionMissing)
    }
    func deleteUser(targetUserID: ProfileID) async throws {}
}
