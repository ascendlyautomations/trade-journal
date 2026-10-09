import Foundation

/// Production Supabase auth user for Explore as Guest (`guest-session` edge function).
///
/// The app receives this id from ``GuestSessionClient`` at runtime; keep in sync with
/// `SHOWCASE_USER_ID` / default in `supabase/functions/guest-session/index.ts`.
enum GuestShowcaseAccount {
    static let productionUserIDRaw = "3daf15b8-2f5d-48c8-ac98-75bca6c878f4"

    static var productionUserID: UserID { UserID(productionUserIDRaw) }

    static var productionProfileID: ProfileID { ProfileID(productionUserIDRaw) }
}
