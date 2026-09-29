import Foundation
import Observation

@MainActor
@Observable
final class AdminBugReportDetailViewModel {
    private let repository: any AdminBugReportsRepository
    private let adminUsers: any AdminUsersRepository

    var snapshot: AdminBugReportSnapshot
    var draftStatus: BugReportStatus
    var statusMessage: String?
    var statusBusy = false

    var openUserBusy = false
    var openUserError: String?

    init(
        snapshot: AdminBugReportSnapshot,
        repository: any AdminBugReportsRepository,
        adminUsers: any AdminUsersRepository
    ) {
        self.snapshot = snapshot
        self.draftStatus = snapshot.row.status
        self.repository = repository
        self.adminUsers = adminUsers
    }

    var canSaveStatus: Bool {
        draftStatus != snapshot.row.status && !statusBusy
    }

    func saveStatus() async -> Bool {
        guard canSaveStatus else { return false }
        statusBusy = true
        statusMessage = nil
        defer { statusBusy = false }
        let previous = snapshot.row.status
        do {
            try await repository.updateReportStatus(
                reportID: snapshot.row.id,
                status: draftStatus,
                previousStatus: previous,
                existingResolvedAt: snapshot.row.resolvedAt
            )
            snapshot.row.status = draftStatus
            if draftStatus == .resolved {
                if previous != .resolved {
                    snapshot.row.resolvedAt = Date()
                }
            } else {
                snapshot.row.resolvedAt = nil
            }
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func markResolved() async -> Bool {
        draftStatus = .resolved
        return await saveStatusForced()
    }

    private func saveStatusForced() async -> Bool {
        guard !statusBusy else { return false }
        statusBusy = true
        statusMessage = nil
        defer { statusBusy = false }
        let previous = snapshot.row.status
        do {
            try await repository.updateReportStatus(
                reportID: snapshot.row.id,
                status: .resolved,
                previousStatus: previous,
                existingResolvedAt: snapshot.row.resolvedAt
            )
            snapshot.row.status = .resolved
            if previous == .resolved, snapshot.row.resolvedAt != nil {
                // keep existing
            } else {
                snapshot.row.resolvedAt = Date()
            }
            draftStatus = .resolved
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func fetchUserForNavigation() async -> AdminUserSummary? {
        openUserBusy = true
        openUserError = nil
        defer { openUserBusy = false }
        do {
            var query = AdminUserDirectoryQuery(
                search: snapshot.row.userID.rawValue,
                bannedFilter: .all,
                proFilter: .all,
                privacyFilter: .all,
                limit: 20,
                offset: 0
            )
            let page = try await adminUsers.fetchDirectory(query)
            if let exact = page.rows.first(where: { $0.id == snapshot.row.userID }) {
                return exact
            }
            query.search = BugReportDisplay.profileHandle(snapshot.reporter).replacingOccurrences(of: "@", with: "")
            let byHandle = try await adminUsers.fetchDirectory(query)
            return byHandle.rows.first(where: { $0.id == snapshot.row.userID }) ?? byHandle.rows.first
        } catch {
            openUserError = error.localizedDescription
            return nil
        }
    }
}
