import Foundation

/// App Store Connect product identifiers for TraxPro auto-renewable subscriptions.
///
/// Override via Info.plist keys (see ``TraxProProductConfiguration/infoPlistKey``) for
/// sandbox vs production without rebuilding. Defaults are placeholders until products
/// exist in App Store Connect.
///
/// All products must share one TraxPro subscription group (monthly / 6-month / yearly).
nonisolated enum TraxProProductConfiguration {
    static let monthlyInfoPlistKey = "TRAXPRO_IAP_PRODUCT_ID_MONTHLY"
    static let sixMonthInfoPlistKey = "TRAXPRO_IAP_PRODUCT_ID_SIX_MONTH"
    static let yearlyInfoPlistKey = "TRAXPRO_IAP_PRODUCT_ID_YEARLY"

    static let defaultMonthlyProductID = "com.tradetraxs.traxpro.monthly"
    static let defaultSixMonthProductID = "com.tradetraxs.traxpro.sixmonth"
    static let defaultYearlyProductID = "com.tradetraxs.traxpro.yearly"

    static var allProductIDs: [String] {
        [monthlyProductID, sixMonthProductID, yearlyProductID]
    }

    static var monthlyProductID: String {
        readInfoPlistString(monthlyInfoPlistKey) ?? defaultMonthlyProductID
    }

    static var sixMonthProductID: String {
        readInfoPlistString(sixMonthInfoPlistKey) ?? defaultSixMonthProductID
    }

    static var yearlyProductID: String {
        readInfoPlistString(yearlyInfoPlistKey) ?? defaultYearlyProductID
    }

    static func billingInterval(for productID: String) -> BillingInterval? {
        switch productID {
        case monthlyProductID:
            return .monthly
        case sixMonthProductID:
            return .sixMonth
        case yearlyProductID:
            return .yearly
        default:
            return nil
        }
    }

    private static func readInfoPlistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
