import Foundation

/// BFF client for verified StoreKit transaction synchronization.
protocol AppleSubscriptionSyncClienting: Sendable {
    func sync(transactionID: String) async throws -> AppleSubscriptionSyncResponse
    func fetchEntitlement() async throws -> BillingEntitlementResponse
}

struct AppleSubscriptionSyncResponse: Decodable, Sendable {
    var traxProActive: Bool
    var source: String?
    var productId: String?
    var billingInterval: String?
    var expiresAt: String?
    var appleSubscriptionStatus: String?
}

struct BillingEntitlementResponse: Decodable, Sendable {
    var traxProActive: Bool
    var source: String?
    var plan: String?
    var billingInterval: String?
    var subscriptionStatus: String?
    var trialEndsAt: String?
    var currentPeriodEndsAt: String?
    var cancelAtPeriodEnd: Bool?
    var appleExpiresAt: String?
    var appleProductId: String?
}

struct AppleSubscriptionSyncClient: AppleSubscriptionSyncClienting {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func sync(transactionID: String) async throws -> AppleSubscriptionSyncResponse {
        struct Body: Encodable {
            var transactionId: String
        }

        let data = try transport.encodeJSON(Body(transactionId: transactionID))
        let response = try await transport.send(
            host: .bff,
            path: "/api/apple/subscription/sync",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Apple subscription sync failed (\(response.statusCode))")
        }
        return try transport.decoder.decode(AppleSubscriptionSyncResponse.self, from: response)
    }

    func fetchEntitlement() async throws -> BillingEntitlementResponse {
        let response = try await transport.send(
            host: .bff,
            path: "/api/billing/entitlement",
            method: .get,
            body: nil,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Billing entitlement fetch failed (\(response.statusCode))")
        }
        return try transport.decoder.decode(BillingEntitlementResponse.self, from: response)
    }
}
