import Foundation

struct GuestSessionIssuance: Sendable, Equatable {
    var userID: UserID
    var accessToken: String
    var expiresAt: Date?
}

/// Asks the project to mint a read-only session for the designated showcase account
/// (``GuestShowcaseAccount`` / `SHOWCASE_USER_ID` on the `guest-session` edge function).
/// No password and no refresh token are returned.
enum GuestSessionClient {
    /// Test seam. Production uses ``liveIssue``.
    nonisolated(unsafe) static var issuer: @Sendable (AppConfiguration) async -> GuestSessionIssuance? = { configuration in
        await liveIssue(configuration: configuration)
    }

    static func issue(configuration: AppConfiguration) async -> GuestSessionIssuance? {
        await issuer(configuration)
    }

    private static func liveIssue(configuration: AppConfiguration) async -> GuestSessionIssuance? {
        guard let base = configuration.supabaseURL,
              let anonKey = configuration.supabaseAnonKey,
              !anonKey.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        let trimmed = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (trimmed.isEmpty ? "functions/v1/guest-session" : trimmed + "/functions/v1/guest-session")
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let issued = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard !issued.accessToken.isEmpty, !issued.userID.isEmpty else { return nil }
            let expiresAt = issued.expiresAt.map { Date(timeIntervalSince1970: $0) }
            return GuestSessionIssuance(
                userID: UserID(issued.userID),
                accessToken: issued.accessToken,
                expiresAt: expiresAt
            )
        } catch {
            return nil
        }
    }

    private struct ResponseBody: Decodable {
        var accessToken: String
        var userID: String
        var expiresAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case userID = "user_id"
            case expiresAt = "expires_at"
        }
    }
}
