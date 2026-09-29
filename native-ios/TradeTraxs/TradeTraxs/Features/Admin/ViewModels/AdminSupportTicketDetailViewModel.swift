import Foundation
import Observation

@MainActor
@Observable
final class AdminSupportTicketDetailViewModel {
    private let repository: any AdminSupportTicketsRepository
    private let adminUsers: any AdminUsersRepository
    private let session: any SessionProviding

    var snapshot: AdminSupportTicketSnapshot
    var draftViewed: Bool
    var draftStatus: SupportTicketStatus
    var draftAdminNotes: String
    var saveMessage: String?
    var saveBusy = false

    var openUserBusy = false
    var openUserError: String?

    init(
        snapshot: AdminSupportTicketSnapshot,
        repository: any AdminSupportTicketsRepository,
        adminUsers: any AdminUsersRepository,
        session: any SessionProviding
    ) {
        self.snapshot = snapshot
        self.repository = repository
        self.adminUsers = adminUsers
        self.session = session
        self.draftViewed = snapshot.row.viewed
        self.draftStatus = snapshot.row.status
        self.draftAdminNotes = snapshot.row.adminNotes ?? ""
    }

    var canSave: Bool {
        !saveBusy
            && (
                draftViewed != snapshot.row.viewed
                    || draftStatus != snapshot.row.status
                    || draftAdminNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        != (snapshot.row.adminNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
    }

    private var viewerID: ProfileID? {
        get async {
            guard let uid = await session.currentUserID else { return nil }
            return ProfileID(uid.rawValue)
        }
    }

    func saveReview() async -> Bool {
        guard canSave else { return false }
        guard let adminID = await viewerID else {
            saveMessage = "Session expired."
            return false
        }
        saveBusy = true
        saveMessage = nil
        defer { saveBusy = false }
        do {
            try await repository.updateTicketReview(
                ticketID: snapshot.row.id,
                update: AdminSupportTicketReviewUpdate(
                    viewed: draftViewed,
                    status: draftStatus,
                    adminNotes: draftAdminNotes,
                    adminUserID: adminID
                )
            )
            snapshot.row.viewed = draftViewed
            snapshot.row.status = draftStatus
            snapshot.row.adminNotes = draftAdminNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.row.updatedAt = Date()
            return true
        } catch {
            saveMessage = error.localizedDescription
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
            if let email = snapshot.row.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                query.search = email
                let byEmail = try await adminUsers.fetchDirectory(query)
                if let match = byEmail.rows.first(where: { $0.id == snapshot.row.userID }) {
                    return match
                }
            }
            query.search = SupportTicketDisplay.profileHandle(snapshot.submitter).replacingOccurrences(of: "@", with: "")
            let byHandle = try await adminUsers.fetchDirectory(query)
            return byHandle.rows.first(where: { $0.id == snapshot.row.userID }) ?? byHandle.rows.first
        } catch {
            openUserError = error.localizedDescription
            return nil
        }
    }
}
