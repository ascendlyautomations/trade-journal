import Foundation
import Observation

@MainActor
@Observable
final class AdminUserDetailViewModel {
    private let repository: any AdminUsersRepository
    private let session: any SessionProviding

    var user: AdminUserSummary
    var activity: AdminUserActivityCounts?
    var activityError: String?
    var isLoadingActivity = false

    var banReason: String
    var moderationMessage: String?
    var moderationBusy = false

    var deletePreview: AdminUserDeletionPreview?
    var deletePreviewError: String?
    var isLoadingDeletePreview = false
    var deleteConfirmText = ""
    var deleteBusy = false
    var deleteError: String?
    var didDelete = false

    init(
        repository: any AdminUsersRepository,
        session: any SessionProviding,
        user: AdminUserSummary
    ) {
        self.repository = repository
        self.session = session
        self.user = user
        self.banReason = user.bannedReason ?? ""
    }

    var viewerID: ProfileID? {
        get async {
            guard let uid = await session.currentUserID else { return nil }
            return ProfileID(uid.rawValue)
        }
    }

    var canDeleteSelf: Bool {
        false
    }

    func loadActivity() async {
        isLoadingActivity = true
        activityError = nil
        do {
            activity = try await repository.fetchActivityCounts(targetUserID: user.id)
        } catch {
            activityError = error.localizedDescription
            activity = nil
        }
        isLoadingActivity = false
    }

    func loadDeletePreview() async {
        isLoadingDeletePreview = true
        deletePreviewError = nil
        do {
            deletePreview = try await repository.fetchDeletionPreview(targetUserID: user.id)
        } catch {
            deletePreview = nil
            deletePreviewError = localized(error)
        }
        isLoadingDeletePreview = false
    }

    func ban() async -> Bool {
        guard let adminID = await viewerID else {
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
            try await repository.banUser(
                targetUserID: user.id,
                adminUserID: adminID,
                reason: reason
            )
            user.isBanned = true
            user.bannedReason = reason
            user.bannedAt = Date()
            return true
        } catch {
            moderationMessage = error.localizedDescription
            return false
        }
    }

    func setHiddenFromCommunity(_ hidden: Bool) async -> Bool {
        guard let adminID = await viewerID else {
            moderationMessage = "Session expired."
            return false
        }
        moderationBusy = true
        moderationMessage = nil
        defer { moderationBusy = false }
        do {
            try await repository.setHiddenFromCommunity(
                targetUserID: user.id,
                adminUserID: adminID,
                hidden: hidden
            )
            user.isHiddenFromCommunity = hidden
            return true
        } catch {
            moderationMessage = error.localizedDescription
            return false
        }
    }

    func unban() async -> Bool {
        guard let adminID = await viewerID else {
            moderationMessage = "Session expired."
            return false
        }
        moderationBusy = true
        moderationMessage = nil
        defer { moderationBusy = false }
        do {
            try await repository.unbanUser(targetUserID: user.id, adminUserID: adminID)
            user.isBanned = false
            user.bannedReason = nil
            user.bannedAt = nil
            banReason = ""
            return true
        } catch {
            moderationMessage = error.localizedDescription
            return false
        }
    }

    func deleteUser() async -> Bool {
        guard deleteConfirmText == "DELETE" else {
            deleteError = "Type DELETE to confirm."
            return false
        }
        deleteBusy = true
        deleteError = nil
        defer { deleteBusy = false }
        do {
            try await repository.deleteUser(targetUserID: user.id)
            didDelete = true
            return true
        } catch let failure as AdminUserDeletionFailure {
            deleteError = localized(failure)
            return false
        } catch {
            deleteError = error.localizedDescription
            return false
        }
    }

    private func localized(_ error: Error) -> String {
        if let failure = error as? AdminUserDeletionFailure {
            switch failure {
            case .notAuthenticated: return "Session expired."
            case .forbidden: return "You don't have permission to perform this action."
            case .selfDelete: return "You cannot delete your own account."
            case .adminTarget: return "Admin accounts cannot be deleted."
            case .validation(let message): return message
            case .server(_, _, let message): return message
            }
        }
        return error.localizedDescription
    }
}
