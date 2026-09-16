import Foundation

/// Registers Apple authorization codes with the BFF for server-side refresh token storage (revocation on delete).
nonisolated struct AppleSignInRevocationCredentialClient: Sendable {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func register(authorizationCode: String) async {
        let code = authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        struct Body: Encodable {
            var authorizationCode: String
        }

        do {
            _ = try await transport.send(
                host: .bff,
                path: "/api/auth/apple/revocation-credentials",
                method: .post,
                headers: ["Content-Type": "application/json"],
                body: try transport.encodeJSON(Body(authorizationCode: code)),
                requiresAuthentication: true
            )
        } catch {
            // Best-effort — Sign in with Apple must not fail if revocation storage fails.
        }
    }
}
