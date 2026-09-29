import Foundation

/// StoreKit introductory-offer text. Period and price come from the product, not a fixed trial length.
enum IntroductoryOfferCopy {
    enum PaymentMode: String, Sendable {
        case freeTrial
        case payAsYouGo
        case payUpFront
    }

    enum PeriodUnit: String, Sendable {
        case day
        case week
        case month
        case year
    }

    static func summary(
        paymentMode: PaymentMode,
        periodValue: Int,
        periodUnit: PeriodUnit,
        displayPrice: String
    ) -> String? {
        let value = max(periodValue, 1)
        let period: String
        switch periodUnit {
        case .day:
            period = value == 1 ? "1 day" : "\(value) days"
        case .week:
            period = value == 1 ? "1 week" : "\(value) weeks"
        case .month:
            period = value == 1 ? "1 month" : "\(value) months"
        case .year:
            period = value == 1 ? "1 year" : "\(value) years"
        }

        switch paymentMode {
        case .freeTrial:
            return "\(period) free trial"
        case .payAsYouGo, .payUpFront:
            let price = displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !price.isEmpty else { return nil }
            return "\(price) for \(period)"
        }
    }
}
