import Foundation

/// BFF client for verified StoreKit transaction synchronization.
protocol AppleSubscriptionSyncClienting: Sendable {
    func sync(transactionID: String, signedTransactionInfo: String) async throws -> AppleSubscriptionSyncResponse
    func fetchEntitlement() async throws -> BillingEntitlementResponse
    func fetchMonetizationConfig() async throws -> IosMonetizationConfigResponse
}

struct IosMonetizationConfigResponse: Decodable, Sendable {
    var iosPaywallEnabled: Bool
    var entitlementEnforcementEnabled: Bool
    /// False when the global settings row could not be read.
    var settingsPresent: Bool?
    var globalIosPaywallEnabled: Bool?
    /// Null inherits the global paywall flag.
    var accountIosPaywallOverride: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iosPaywallEnabled = try container.decode(Bool.self, forKey: .iosPaywallEnabled)
        entitlementEnforcementEnabled = try container.decode(Bool.self, forKey: .entitlementEnforcementEnabled)
        settingsPresent = try container.decodeIfPresent(Bool.self, forKey: .settingsPresent)
        globalIosPaywallEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalIosPaywallEnabled)
        accountIosPaywallOverride = try container.decodeIfPresent(Bool.self, forKey: .accountIosPaywallOverride)
    }

    private enum CodingKeys: String, CodingKey {
        case iosPaywallEnabled
        case entitlementEnforcementEnabled
        case settingsPresent
        case globalIosPaywallEnabled
        case accountIosPaywallOverride
    }
}

nonisolated struct AppleSubscriptionSyncRequest: Encodable, Equatable, Sendable {
    var transactionId: String
    var signedTransactionInfo: String
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
    var accessExpiresAt: String? = nil
    var issuedAt: String? = nil
    var appleSubscriptionStatus: String? = nil
    var appleRevokedAt: String? = nil
}

struct AppleSubscriptionSyncClient: AppleSubscriptionSyncClienting {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func sync(transactionID: String, signedTransactionInfo: String) async throws -> AppleSubscriptionSyncResponse {
        let data = try transport.encodeJSON(
            AppleSubscriptionSyncRequest(
                transactionId: transactionID,
                signedTransactionInfo: signedTransactionInfo
            )
        )
        let response = try await transport.send(
            host: .bff,
            path: "/api/apple/subscription/sync",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            let serverMessage = Self.parseErrorMessage(from: response.data)
            if let serverMessage, !serverMessage.isEmpty {
                throw AppError.unknown(message: serverMessage)
            }
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

    private static func parseErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            var error: String?
            var code: String?
        }
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return nil
        }
        return body.error?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchMonetizationConfig() async throws -> IosMonetizationConfigResponse {
        let response = try await transport.send(
            host: .bff,
            path: "/api/billing/ios-config",
            method: .get,
            body: nil,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Monetization config fetch failed (\(response.statusCode))")
        }
        do {
            return try transport.decoder.decode(IosMonetizationConfigResponse.self, from: response)
        } catch {
            throw AppError.unknown(message: "Monetization config response was malformed")
        }
    }
}
