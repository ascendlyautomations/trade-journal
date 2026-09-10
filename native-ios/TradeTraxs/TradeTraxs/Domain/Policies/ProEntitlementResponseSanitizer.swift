import Foundation

/// Maps Pro-gated BFF responses to neutral native copy — never expose web checkout steering.
nonisolated enum ProEntitlementResponseSanitizer {
    static func message(
        statusCode: Int,
        error: String? = nil,
        reply: String? = nil
    ) -> String {
        if statusCode == 403 {
            return TraxProFeatureMessaging.featureRequired
        }

        for candidate in [reply, error].compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard !candidate.isEmpty else { continue }
            if containsPurchaseSteering(candidate) {
                return TraxProFeatureMessaging.featureRequired
            }
        }

        if let reply = reply?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            return reply
        }
        if let error = error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return sanitizedOrNeutral(error)
        }

        return TraxProFeatureMessaging.featureRequired
    }

    static func sanitizedOrNeutral(_ text: String) -> String {
        if containsPurchaseSteering(text) {
            return TraxProFeatureMessaging.featureRequired
        }
        return text
    }

    static func containsPurchaseSteering(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let blocked = [
            "upgrade on web",
            "upgrade on the web",
            "upgrade your plan on the web",
            "visit tradetraxs.com",
            "tradetraxs.com/pricing",
            "tradetraxs.com/choose-plan",
            "choose-plan",
            "finish-trial",
            "stripe checkout",
            "checkout on the web",
            "subscribe on the web",
            "purchase on the website",
        ]
        return blocked.contains(where: { lowered.contains($0) })
    }
}
