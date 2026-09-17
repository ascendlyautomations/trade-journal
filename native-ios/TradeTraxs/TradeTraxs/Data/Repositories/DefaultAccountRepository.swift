import Foundation

/// Calls the existing BFF `POST /api/delete-account` pipeline (same as web Settings).
nonisolated struct DefaultAccountRepository: AccountRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func deleteAuthenticatedAccount() async throws {
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

#if DEBUG
        AccountDeletionDebugLog.requestStarted()
#endif

        let response = try await transport.send(
            host: .bff,
            path: "/api/delete-account",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: Data("{}".utf8),
            requiresAuthentication: true
        )

#if DEBUG
        AccountDeletionDebugLog.response(status: response.statusCode)
#endif

        let decoded = try? JSONDecoder().decode(DeleteAccountResponse.self, from: response.data)

        switch response.statusCode {
        case 200 ... 299:
            guard decoded?.success == true else {
                let message = decoded?.error ?? "Account deletion failed. Please try again."
#if DEBUG
                AccountDeletionDebugLog.failed(reason: message)
#endif
                throw AccountDeletionError.serverMessage(message)
            }
#if DEBUG
            AccountDeletionDebugLog.accountDeleted()
            AccountDeletionDebugLog.appleRevocation(phase: "serverPipelineCompleted")
#endif
        case 401:
#if DEBUG
            AccountDeletionDebugLog.failed(reason: "unauthorized")
#endif
            throw AccountDeletionError.notAuthenticated
        default:
            let message = decoded?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = (message?.isEmpty == false ? message : nil)
                ?? "Account deletion failed. Please contact support."
#if DEBUG
            AccountDeletionDebugLog.failed(reason: resolved)
#endif
            throw AccountDeletionError.serverMessage(resolved)
        }
    }
}

private nonisolated struct DeleteAccountResponse: Decodable {
    var success: Bool?
    var error: String?
}
