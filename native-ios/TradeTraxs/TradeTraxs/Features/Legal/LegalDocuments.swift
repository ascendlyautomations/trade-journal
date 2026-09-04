import Foundation

/// Production legal document URLs — shared by Settings, auth, and disclaimers.
enum LegalDocuments {
    static let terms = URL(string: "https://www.tradetraxs.com/terms")!
    static let privacy = URL(string: "https://www.tradetraxs.com/privacy")!
    static let communityGuidelines = URL(string: "https://www.tradetraxs.com/community-guidelines")!
    static let refundPolicy = URL(string: "https://www.tradetraxs.com/refund-policy")!
}
