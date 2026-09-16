import Foundation

/// App Store release switch for in-app TraxPro / StoreKit commerce.
///
/// When `iosPaidSubscriptionsEnabled` is `false`, purchase UI and StoreKit product
/// loading stay dormant; usage caps from ``FreeTierPolicy`` are not applied client-side.
/// StoreKit infrastructure, product IDs, and entitlement resolution remain for a future enable.
nonisolated enum IosSubscriptionReleaseConfiguration {
    #if DEBUG
    /// Override in unit tests when exercising purchase flows.
    static var iosPaidSubscriptionsEnabled = false
    #else
    static let iosPaidSubscriptionsEnabled = false
    #endif

    /// Free-tier caps and paywall-oriented UX apply only when paid IAP is offered.
    static var appliesFreeTierUsageCaps: Bool {
        iosPaidSubscriptionsEnabled
    }
}
