import XCTest
@testable import TradeTraxs

final class AdminContentReportsTests: XCTestCase {
    func testDefaultPageSizeIsBounded() {
        XCTAssertEqual(AdminContentReportListQuery.defaultPageSize, 25)
    }

    func testStatusFilterLabelsMatchWebStatuses() {
        XCTAssertEqual(AdminContentReportStatusFilter.open.rawValue, "open")
        XCTAssertEqual(AdminContentReportStatusFilter.reviewing.rawValue, "reviewing")
        XCTAssertEqual(AdminContentReportStatusFilter.resolved.rawValue, "resolved")
        XCTAssertEqual(AdminContentReportStatusFilter.dismissed.rawValue, "dismissed")
    }

    func testParseRowMapsDTOFields() {
        let dto = ContentReportRowDTO(
            id: "r1",
            reporter_user_id: "11111111-1111-1111-1111-111111111111",
            target_type: "post",
            target_id: "p1",
            reported_user_id: "22222222-2222-2222-2222-222222222222",
            reason: "spam",
            details: "details",
            status: "open",
            created_at: "2026-01-01T12:00:00.000Z",
            reviewed_at: nil,
            reviewed_by: nil
        )
        let row = AdminContentReportParsing.parseRow(dto)
        XCTAssertEqual(row?.id, "r1")
        XCTAssertEqual(row?.targetType, .post)
        XCTAssertEqual(row?.reason, .spam)
        XCTAssertEqual(row?.status, .open)
    }

    func testSnapshotResolveReportedUserPrefersExplicitField() {
        let row = AdminContentReportRow(
            id: "r1",
            reporterUserID: ProfileID("11111111-1111-1111-1111-111111111111"),
            targetType: .post,
            targetID: "p1",
            reportedUserID: ProfileID("22222222-2222-2222-2222-222222222222"),
            reason: .spam,
            details: nil,
            status: .open,
            createdAt: nil,
            reviewedAt: nil,
            reviewedBy: nil
        )
        XCTAssertEqual(
            AdminContentReportHydration.resolveReportedUserID(row)?.rawValue,
            "22222222-2222-2222-2222-222222222222"
        )
    }

    @MainActor
    func testFilterChangeClearsStaleRows() async {
        let repo = MockAdminContentReportsRepository()
        repo.pages = [
            AdminContentReportPage(
                rows: [sampleRow(id: "a")],
                enrichment: .init(profiles: [:], targets: [:]),
                hasMore: false
            ),
            AdminContentReportPage(
                rows: [sampleRow(id: "b")],
                enrichment: .init(profiles: [:], targets: [:]),
                hasMore: false
            ),
        ]
        let vm = AdminContentReportsViewModel(repository: repo)
        await vm.reload()
        XCTAssertEqual(vm.snapshots.map(\.row.id), ["a"])
        vm.statusFilter = .resolved
        await vm.onFilterChanged()
        XCTAssertEqual(vm.snapshots.map(\.row.id), ["b"])
        XCTAssertEqual(repo.fetchCalls.map(\.status), [.open, .resolved])
    }

    @MainActor
    func testPaginationIncrementsOffset() async {
        let repo = MockAdminContentReportsRepository()
        repo.pages = [
            AdminContentReportPage(
                rows: (0..<25).map { sampleRow(id: "p\($0)") },
                enrichment: .init(profiles: [:], targets: [:]),
                hasMore: true
            ),
            AdminContentReportPage(
                rows: [sampleRow(id: "tail")],
                enrichment: .init(profiles: [:], targets: [:]),
                hasMore: false
            ),
        ]
        let vm = AdminContentReportsViewModel(repository: repo)
        await vm.reload()
        XCTAssertTrue(vm.hasMore)
        await vm.loadMore()
        XCTAssertEqual(vm.snapshots.last?.row.id, "tail")
        XCTAssertEqual(repo.fetchCalls.last?.offset, 25)
    }

    @MainActor
    func testStatusMutationUpdatesLocalRow() async {
        let reports = MockAdminContentReportsRepository()
        let users = MockAdminUsersRepositoryForReports()
        let session = MockSessionProvider(userID: "admin-admin-admin-admin-adminadmin")
        let snapshot = AdminContentReportSnapshot(
            row: sampleRow(id: "r1"),
            targetPreview: AdminReportTargetPreview(
                targetType: .user,
                targetID: "u1",
                headline: "User",
                subline: nil,
                ownerUserID: nil,
                unavailable: false,
                openDestination: nil
            ),
            reporter: nil,
            reportedUser: nil
        )
        let vm = AdminContentReportDetailViewModel(
            snapshot: snapshot,
            reportsRepository: reports,
            adminUsers: users,
            session: session
        )
        vm.draftStatus = .resolved
        let ok = await vm.saveStatus()
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.snapshot.row.status, .resolved)
        XCTAssertEqual(reports.updatedStatus, .resolved)
    }

    @MainActor
    func testBanUsesAdminUsersRepository() async {
        let reports = MockAdminContentReportsRepository()
        let users = MockAdminUsersRepositoryForReports()
        let session = MockSessionProvider(userID: "admin-admin-admin-admin-adminadmin")
        let reported = ProfileID("22222222-2222-2222-2222-222222222222")
        var row = sampleRow(id: "r1")
        row.targetType = .user
        row.targetID = reported.rawValue
        let snapshot = AdminContentReportSnapshot(
            row: row,
            targetPreview: AdminReportTargetPreview(
                targetType: .user,
                targetID: reported.rawValue,
                headline: "@trader",
                subline: nil,
                ownerUserID: reported,
                unavailable: false,
                openDestination: .profile(reported)
            ),
            reporter: nil,
            reportedUser: AdminReportProfileSummary(
                id: reported,
                username: "trader",
                name: nil,
                avatarURL: nil,
                isBanned: false,
                bannedReason: nil,
                bannedAt: nil
            )
        )
        let vm = AdminContentReportDetailViewModel(
            snapshot: snapshot,
            reportsRepository: reports,
            adminUsers: users,
            session: session
        )
        vm.banReason = "Spam"
        let ok = await vm.banReportedUser()
        XCTAssertTrue(ok)
        XCTAssertEqual(users.lastBanTarget, reported)
        XCTAssertTrue(vm.snapshot.reportedUser?.isBanned == true)
    }

    func testLoginShellAdminContentReportsRepositoryRejectsMutations() async {
        let repo = LoginShellAdminContentReportsRepositoryProbe()
        do {
            _ = try await repo.fetchReports(status: .open, limit: 25, offset: 0)
            XCTFail("Expected session missing")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    private func sampleRow(id: String) -> AdminContentReportRow {
        AdminContentReportRow(
            id: id,
            reporterUserID: ProfileID("11111111-1111-1111-1111-111111111111"),
            targetType: .post,
            targetID: "post-\(id)",
            reportedUserID: ProfileID("22222222-2222-2222-2222-222222222222"),
            reason: .spam,
            details: nil,
            status: .open,
            createdAt: Date(),
            reviewedAt: nil,
            reviewedBy: nil
        )
    }
}

private struct LoginShellAdminContentReportsRepositoryProbe: AdminContentReportsRepository {
    func fetchReports(
        status: AdminContentReportStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminContentReportPage {
        throw AppError.authentication(.sessionMissing)
    }

    func updateReportStatus(
        reportID: String,
        status: ContentReportStatus,
        reviewerID: ProfileID
    ) async throws {
        throw AppError.authentication(.sessionMissing)
    }
}

private final class MockAdminContentReportsRepository: AdminContentReportsRepository, @unchecked Sendable {
    struct FetchCall: Sendable {
        var status: AdminContentReportStatusFilter
        var limit: Int
        var offset: Int
    }

    var pages: [AdminContentReportPage] = []
    var fetchCalls: [FetchCall] = []
    var updatedStatus: ContentReportStatus?

    func fetchReports(
        status: AdminContentReportStatusFilter,
        limit: Int,
        offset: Int
    ) async throws -> AdminContentReportPage {
        fetchCalls.append(FetchCall(status: status, limit: limit, offset: offset))
        let index = min(fetchCalls.count - 1, max(0, pages.count - 1))
        return pages[index]
    }

    func updateReportStatus(
        reportID: String,
        status: ContentReportStatus,
        reviewerID: ProfileID
    ) async throws {
        _ = reportID
        _ = reviewerID
        updatedStatus = status
    }
}

private final class MockAdminUsersRepositoryForReports: AdminUsersRepository, @unchecked Sendable {
    var lastBanTarget: ProfileID?

    func fetchDirectory(_ query: AdminUserDirectoryQuery) async throws -> AdminUserDirectoryPage {
        throw AppError.authentication(.sessionMissing)
    }

    func fetchActivityCounts(targetUserID: ProfileID) async throws -> AdminUserActivityCounts {
        throw AppError.authentication(.sessionMissing)
    }

    func banUser(targetUserID: ProfileID, adminUserID: ProfileID, reason: String) async throws {
        _ = (adminUserID, reason)
        lastBanTarget = targetUserID
    }

    func unbanUser(targetUserID: ProfileID, adminUserID: ProfileID) async throws {
        _ = (targetUserID, adminUserID)
    }

    func fetchDeletionPreview(targetUserID: ProfileID) async throws -> AdminUserDeletionPreview {
        throw AppError.authentication(.sessionMissing)
    }

    func deleteUser(targetUserID: ProfileID) async throws {
        throw AppError.authentication(.sessionMissing)
    }
}

private struct MockSessionProvider: SessionProviding {
    let userID: String

    var currentUserID: UserID? {
        get async { UserID(userID) }
    }

    var accessToken: String? { get async { "token" } }
}
