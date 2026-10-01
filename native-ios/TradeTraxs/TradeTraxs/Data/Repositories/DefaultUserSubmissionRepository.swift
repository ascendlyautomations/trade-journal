import Foundation
import OSLog
import UIKit

nonisolated struct DefaultUserSubmissionRepository: UserSubmissionRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding
    private let profiles: any ProfileRepository

    init(
        supabase: SupabaseInfrastructure,
        session: any SessionProviding,
        profiles: any ProfileRepository
    ) {
        self.supabase = supabase
        self.session = session
        self.profiles = profiles
    }

    func submitSupportTicket(_ submission: SupportTicketSubmission) async throws {
        let subject = submission.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = submission.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !message.isEmpty else {
            throw UserSubmissionError.validation("Subject and message are required.")
        }

        let context = try await authenticatedContext()
        let screenshotURL = try await uploadScreenshotIfNeeded(
            submission.screenshot,
            userID: context.userID,
            prefix: "support"
        )

        struct InsertBody: Encodable {
            var user_id: String
            var email: String?
            var category: String
            var subject: String
            var message: String
            var screenshot_url: String?
            var status: String
            var priority: String
            var viewed: Bool
        }

        struct IDRow: Decodable {
            var id: String
        }

        let body = InsertBody(
            user_id: context.userID,
            email: context.email,
            category: submission.category.rawValue,
            subject: subject,
            message: message,
            screenshot_url: screenshotURL,
            status: "open",
            priority: "normal",
            viewed: false
        )

        let row: IDRow
        do {
            row = try await supabase.database.insert(
                body,
                into: "support_tickets",
                query: [SupabaseQuery.select("id")],
                returning: IDRow.self
            )
        } catch {
            await deleteUploadedScreenshot(screenshotURL)
            throw error
        }
        await notifyAdmin(type: "support_ticket", recordID: row.id)
    }

    func submitFeedback(_ submission: FeedbackSubmission) async throws {
        let subject = submission.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = submission.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw UserSubmissionError.validation("Message is required.")
        }

        let context = try await authenticatedContext()
        let screenshotURL = try await uploadScreenshotIfNeeded(
            submission.screenshot,
            userID: context.userID,
            prefix: "feedback"
        )

        struct InsertBody: Encodable {
            var user_id: String
            var email: String?
            var subject: String?
            var message: String
            var screenshot_url: String?
            var status: String
        }

        struct IDRow: Decodable {
            var id: String
        }

        let body = InsertBody(
            user_id: context.userID,
            email: context.email,
            subject: subject.isEmpty ? nil : subject,
            message: message,
            screenshot_url: screenshotURL,
            status: "open"
        )

        let row: IDRow
        do {
            row = try await supabase.database.insert(
                body,
                into: "feedback_submissions",
                query: [SupabaseQuery.select("id")],
                returning: IDRow.self
            )
        } catch {
            await deleteUploadedScreenshot(screenshotURL)
            throw error
        }
        await notifyAdmin(type: "feedback_submission", recordID: row.id)
    }

    func submitBugReport(_ submission: BugReportSubmission) async throws {
        let title = submission.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = submission.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !description.isEmpty else {
            throw UserSubmissionError.validation("Title and description are required.")
        }
        guard title.count <= 200 else {
            throw UserSubmissionError.validation("Title must be 200 characters or fewer.")
        }

        let context = try await authenticatedContext()
        let screenshotURL = try await uploadScreenshotIfNeeded(
            submission.screenshot,
            userID: context.userID,
            prefix: "bug-reports"
        )

        struct InsertBody: Encodable {
            var user_id: String
            var title: String
            var description: String
            var severity: String
            var screenshot_url: String?
            var page_url: String
            var browser_info: String
            var status: String
        }

        struct IDRow: Decodable {
            var id: String
        }

        let browserInfo = await SubmissionDeviceMetadata.compactEnvironmentStringForSubmission()
        let body = InsertBody(
            user_id: context.userID,
            title: title,
            description: description,
            severity: submission.severity.rawValue,
            screenshot_url: screenshotURL,
            page_url: SubmissionDeviceMetadata.bugReportPageURL,
            browser_info: browserInfo,
            status: "open"
        )

        let row: IDRow
        do {
            row = try await supabase.database.insert(
                body,
                into: "bug_reports",
                query: [SupabaseQuery.select("id")],
                returning: IDRow.self
            )
        } catch {
            await deleteUploadedScreenshot(screenshotURL)
            throw error
        }
        await notifyAdmin(type: "bug_report", recordID: row.id)
    }

    private struct AuthContext: Sendable {
        var userID: String
        var email: String?
    }

    private func authenticatedContext() async throws -> AuthContext {
        guard supabase.transport?.isConfigured == true else {
            throw UserSubmissionError.persistence("Network transport unavailable.")
        }
        guard let userID = await session.currentUserID?.rawValue else {
            throw UserSubmissionError.notAuthenticated
        }
        let email = try? await profiles.currentUser().email
        return AuthContext(userID: userID, email: email)
    }

    private func uploadScreenshotIfNeeded(
        _ image: UIImage?,
        userID: String,
        prefix: String
    ) async throws -> String? {
        guard let image else { return nil }
        do {
            return try await SubmissionScreenshotUpload.uploadJPEG(
                image: image,
                userID: userID,
                prefix: prefix,
                storage: supabase.storage
            )
        } catch let error as UserSubmissionError {
            throw error
        } catch {
            throw UserSubmissionError.screenshotUpload(error.localizedDescription)
        }
    }

    private func deleteUploadedScreenshot(_ url: String?) async {
        guard let url else { return }
        await OwnedMediaStorageCleanup.removePublicObjects(
            urls: [url],
            storage: supabase.storage
        )
    }

    private func notifyAdmin(type: String, recordID: String) async {
        guard let transport = supabase.transport else { return }
        struct Body: Encodable {
            var type: String
            var recordId: String
        }
        do {
            let data = try transport.encodeJSON(Body(type: type, recordId: recordID))
            let response = try await transport.send(
                host: .bff,
                path: "/api/admin-notify/submission",
                method: .post,
                headers: ["Content-Type": "application/json"],
                body: data,
                requiresAuthentication: true
            )
            if !(200 ... 299).contains(response.statusCode) {
                AppLog.networking.error(
                    "userSubmission.adminNotify failed type=\(type, privacy: .public) status=\(response.statusCode, privacy: .public)"
                )
            }
        } catch {
            AppLog.networking.error(
                "userSubmission.adminNotify error type=\(type, privacy: .public) \(String(describing: error), privacy: .public)"
            )
        }
    }
}
