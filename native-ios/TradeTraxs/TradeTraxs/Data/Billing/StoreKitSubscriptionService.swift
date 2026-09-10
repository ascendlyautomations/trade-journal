import Foundation
import OSLog
import StoreKit

/// StoreKit 2 TraxPro subscription foundation — purchase, restore, and server sync.
protocol StoreKitEntitlementSyncing: Sendable {
    func syncVerifiedTransactionsToServer() async throws
    func startTransactionListenerIfNeeded() async
}

protocol StoreKitSubscriptionServicing: StoreKitEntitlementSyncing, Sendable {
    func loadProducts() async throws -> [StoreKitTraxProProduct]
    func purchase(productID: String) async -> StoreKitPurchaseOutcome
    func restorePurchases() async throws -> Bool
}

struct StoreKitTraxProProduct: Sendable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var displayPrice: String
    var subscriptionPeriodLabel: String
    var billingInterval: BillingInterval?
    var hasEligibleIntroductoryOffer: Bool
}

enum StoreKitPurchaseOutcome: Sendable, Equatable {
    case success
    case userCancelled
    case pending
    case unverified
    case failed(String)
}

actor StoreKitSubscriptionService: StoreKitSubscriptionServicing {
    private let syncClient: any AppleSubscriptionSyncClienting
    private var updatesTask: Task<Void, Never>?
    private var listenerStarted = false

    init(syncClient: any AppleSubscriptionSyncClienting) {
        self.syncClient = syncClient
    }

    deinit {
        updatesTask?.cancel()
    }

    func startTransactionListenerIfNeeded() async {
        guard !listenerStarted else { return }
        listenerStarted = true
        updatesTask = Task { [syncClient] in
            for await update in Transaction.updates {
                await self.handle(update, syncClient: syncClient)
            }
        }
    }

    func loadProducts() async throws -> [StoreKitTraxProProduct] {
        let ids = TraxProProductConfiguration.allProductIDs
        let products = try await Product.products(for: ids)
        return products
            .sorted { lhs, rhs in
                Self.sortOrder(for: lhs.id) < Self.sortOrder(for: rhs.id)
            }
            .map { Self.makeProduct($0) }
    }

    func purchase(productID: String) async -> StoreKitPurchaseOutcome {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                return .failed("TraxPro product unavailable")
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    do {
                        try await syncVerifiedTransaction(transaction)
                        await transaction.finish()
                        return .success
                    } catch {
                        // Leave unfinished so Transaction.updates / restore / foreground sync can retry.
                        AppLog.application.error(
                            "StoreKit purchase sync failed — transaction left open for retry: \(error.localizedDescription, privacy: .public)"
                        )
                        return .failed("Could not sync your purchase. We'll retry automatically.")
                    }
                case .unverified:
                    return .unverified
                }
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Purchase could not be completed")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async throws -> Bool {
        var syncedAny = false
        for await entitlement in Transaction.currentEntitlements {
            let transaction = try Self.checkVerified(entitlement)
            try await syncVerifiedTransaction(transaction)
            syncedAny = true
        }
        return syncedAny
    }

    func syncVerifiedTransactionsToServer() async throws {
        var syncedAny = false
        for await entitlement in Transaction.currentEntitlements {
            let transaction = try Self.checkVerified(entitlement)
            try await syncVerifiedTransaction(transaction)
            syncedAny = true
        }
        if !syncedAny {
            AppLog.application.debug("StoreKit sync: no current entitlements to upload")
        }
    }

    private func syncVerifiedTransaction(_ transaction: Transaction) async throws {
        let transactionID = String(transaction.id)
        guard !transactionID.isEmpty else {
            throw AppError.unknown(message: "Missing transaction id")
        }
        _ = try await syncClient.sync(transactionID: transactionID)
    }

    private func handle(
        _ update: VerificationResult<Transaction>,
        syncClient: any AppleSubscriptionSyncClienting
    ) async {
        do {
            let transaction = try Self.checkVerified(update)
            _ = try await syncClient.sync(transactionID: String(transaction.id))
            await transaction.finish()
        } catch {
            AppLog.application.error(
                "StoreKit transaction update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw AppError.unknown(message: "Unverified App Store transaction")
        }
    }

    private static func makeProduct(_ product: Product) -> StoreKitTraxProProduct {
        let periodLabel = product.subscription.map { subscriptionPeriodLabel($0.subscriptionPeriod) } ?? "Subscription"
        let introEligible = product.subscription?.introductoryOffer != nil
        return StoreKitTraxProProduct(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            subscriptionPeriodLabel: periodLabel,
            billingInterval: TraxProProductConfiguration.billingInterval(for: product.id),
            hasEligibleIntroductoryOffer: introEligible
        )
    }

    private static func subscriptionPeriodLabel(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return period.value == 1 ? "Daily" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "Weekly" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "Monthly" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "Yearly" : "\(period.value) years"
        @unknown default:
            return "Subscription"
        }
    }

    private static func sortOrder(for productID: String) -> Int {
        switch TraxProProductConfiguration.billingInterval(for: productID) {
        case .monthly: return 0
        case .sixMonth: return 1
        case .yearly: return 2
        case .none: return 99
        }
    }
}

#if DEBUG
/// DEBUG-only surface for StoreKit sandbox testing without subscription UI (Phase 2).
enum StoreKitSubscriptionDebugProbe {
    static func logProductLoad(_ products: [StoreKitTraxProProduct]) {
        AppLog.application.debug(
            "StoreKit products loaded count=\(products.count, privacy: .public)"
        )
    }
}
#endif
