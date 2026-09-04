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

        let response = try await transport.send(
            host: .bff,
            path: "/api/delete-account",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: Data("{}".utf8),
            requiresAuthentication: true
        )

        let decoded = try? JSONDecoder().decode(DeleteAccountResponse.self, from: response.data)

        switch response.statusCode {
        case 200 ... 299:
            guard decoded?.success == true else {
                throw AccountDeletionError.serverMessage(
                    decoded?.error ?? "Account deletion failed. Please try again."
                )
            }
        case 401:
            throw AccountDeletionError.notAuthenticated
        default:
            let message = decoded?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AccountDeletionError.serverMessage(
                (message?.isEmpty == false ? message : nil)
                    ?? "Account deletion failed. Please contact support."
            )
        }
    }
}

private nonisolated struct DeleteAccountResponse: Decodable {
    var success: Bool?
    var error: String?
}
