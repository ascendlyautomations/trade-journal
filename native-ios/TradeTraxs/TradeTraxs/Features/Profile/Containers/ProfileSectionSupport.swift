import Foundation

nonisolated enum ProfileSectionSupport {
    /// Debug development sessions use `dev.*` IDs that are not in Supabase.
    static func isLocalDevelopmentProfile(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }

    static func message(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return UserFacingError.map(AppError.unknown(message: error.localizedDescription)).message
    }
}
