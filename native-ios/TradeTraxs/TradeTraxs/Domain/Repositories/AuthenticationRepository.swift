import Foundation

/// Auth capability contract — no Keychain / Supabase types here.
nonisolated protocol AuthenticationRepository: Sendable {
    func currentSessionUserID() async throws -> UserID?
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String) async throws -> User
    func signOut() async throws
    func requestPasswordReset(email: String) async throws
}
