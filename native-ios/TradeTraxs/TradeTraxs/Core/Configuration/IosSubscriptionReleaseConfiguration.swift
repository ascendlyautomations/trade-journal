import Foundation

/// App Store release switch for in-app TraxPro / StoreKit commerce.
///
/// When `iosPaidSubscriptionsEnabled` is `false`, purchase UI and StoreKit product
/// loading stay dormant; usage caps from ``FreeTierPolicy`` are not applied client-side.
/// When `iosReferralProgramEnabled` is `false`, referral Settings and referral entry
/// points stay hidden. StoreKit, billing, and referral infrastructure remain for a later release.
nonisolated enum IosSubscriptionReleaseConfiguration {
    #if DEBUG
    /// Override in unit tests when exercising purchase flows.
    static var iosPaidSubscriptionsEnabled = false
    /// Override in unit tests when exercising the referral Settings surface.
    static var iosReferralProgramEnabled = false
    #else
    static let iosPaidSubscriptionsEnabled = false
    static let iosReferralProgramEnabled = false
    #endif

    /// Free-tier caps and paywall-oriented UX apply only when paid IAP is offered.
    static var appliesFreeTierUsageCaps: Bool {
        iosPaidSubscriptionsEnabled
    }
}
