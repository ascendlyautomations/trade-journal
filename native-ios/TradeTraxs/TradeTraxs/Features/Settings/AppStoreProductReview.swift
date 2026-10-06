import Foundation

/// App Store write-review link for the explicit Settings action.
///
/// `requestReview()` is reserved for the one-time Getting Started milestone.
/// This URL is what “Leave a Rating” opens so the review page is reliable.
enum AppStoreProductReview {
    /// Numeric production App Store ID.
    static let appStoreID = "6808723069"

    static func writeReviewURL(appStoreID: String? = AppStoreProductReview.appStoreID) -> URL? {
        guard let appStoreID else { return nil }
        let trimmed = appStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(trimmed)?action=write-review")
    }
}
