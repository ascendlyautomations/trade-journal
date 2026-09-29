import Foundation
import Observation

@MainActor
@Observable
final class AdminContentReportDetailViewModel {
    private let reportsRepository: any AdminContentReportsRepository
    private let adminUsers: any AdminUsersRepository
    private let session: any SessionProviding

    var snapshot: AdminContentReportSnapshot
    var draftStatus: ContentReportStatus
    var statusMessage: String?
    var statusBusy = false

    var banReason: String
    var moderationMessage: String?
    var moderationBusy = false

    init(
        snapshot: AdminContentReportSnapshot,
        reportsRepository: any AdminContentReportsRepository,
        adminUsers: any AdminUsersRepository,
        session: any SessionProviding
    ) {
        self.snapshot = snapshot
        self.draftStatus = snapshot.row.status
        self.reportsRepository = reportsRepository
        self.adminUsers = adminUsers
        self.session = session
        self.banReason = ContentReportDisplay.suggestedBanReason(row: snapshot.row)
    }

    var reportedUserID: ProfileID? {
        AdminContentReportHydration.resolveReportedUserID(snapshot.row)
    }

    var reportedUserIsBanned: Bool {
        snapshot.reportedUser?.isBanned == true
    }

    var canSaveStatus: Bool {
        draftStatus != snapshot.row.status && !statusBusy
    }

    private var viewerID: ProfileID? {
        get async {
            guard let uid = await session.currentUserID else { return nil }
            return ProfileID(uid.rawValue)
        }
    }

    func saveStatus() async -> Bool {
        guard canSaveStatus else { return false }
        guard let reviewerID = await viewerID else {
            statusMessage = "Session expired."
            return false
        }
        statusBusy = true
        statusMessage = nil
        defer { statusBusy = false }
        do {
            try await reportsRepository.updateReportStatus(
                reportID: snapshot.row.id,
                status: draftStatus,
                reviewerID: reviewerID
            )
            snapshot.row.status = draftStatus
            snapshot.row.reviewedAt = Date()
            snapshot.row.reviewedBy = reviewerID
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func banReportedUser() async -> Bool {
        guard let targetID = reportedUserID, let adminID = await viewerID else {
            moderationMessage = "Session expired."
            return false
        }
        let reason = banReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            moderationMessage = "Enter a ban reason."
            return false
        }
        moderationBusy = true
        moderationMessage = nil
        defer { moderationBusy = false }
        do {
            try await adminUsers.banUser(
                targetUserID: targetID,
                adminUserID: adminID,
                reason: reason
            )
            refreshReportedUserBanned(true, reason: reason)
            return true
        } catch {
            moderationMessage = error.localizedDescription
            return false
        }
    }

    func unbanReportedUser() async -> Bool {
        guard let targetID = reportedUserID, let adminID = await viewerID else {
            moderationMessage = "Session expired."
            return false
        }
        moderationBusy = true
        moderationMessage = nil
        defer { moderationBusy = false }
        do {
            try await adminUsers.unbanUser(targetUserID: targetID, adminUserID: adminID)
            refreshReportedUserBanned(false, reason: nil)
            banReason = ContentReportDisplay.suggestedBanReason(row: snapshot.row)
            return true
        } catch {
            moderationMessage = error.localizedDescription
            return false
        }
    }

    private func refreshReportedUserBanned(_ banned: Bool, reason: String?) {
        guard let id = reportedUserID else { return }
        var profile = snapshot.reportedUser ?? AdminReportProfileSummary(
            id: id,
            username: nil,
            name: nil,
            avatarURL: nil,
            isBanned: banned,
            bannedReason: reason,
            bannedAt: banned ? Date() : nil
        )
        profile.isBanned = banned
        profile.bannedReason = reason
        profile.bannedAt = banned ? Date() : nil
        snapshot.reportedUser = profile
    }
}
