import Foundation
import OSLog
import StoreKit
import UIKit

/// StoreKit 2 TraxPro subscription foundation — purchase, restore, and server sync.
protocol StoreKitEntitlementSyncing: Sendable {
    func syncVerifiedTransactionsToServer() async throws
    func startTransactionListenerIfNeeded() async
}

protocol StoreKitSubscriptionServicing: StoreKitEntitlementSyncing, Sendable {
    func loadProducts() async throws -> [StoreKitTraxProProduct]
    func purchase(productID: String, appAccountToken: UUID?) async -> StoreKitPurchaseOutcome
    func restorePurchases() async throws -> Bool
    /// Presents Apple's native offer-code redemption sheet (`AppStore.presentOfferCodeRedeemSheet`).
    func presentOfferCodeRedemption() async throws
}

struct StoreKitTraxProProduct: Sendable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var displayPrice: String
    var subscriptionPeriodLabel: String
    var billingInterval: BillingInterval?
    var hasEligibleIntroductoryOffer: Bool
    /// Present only when StoreKit says the user is eligible for the product's introductory offer.
    var introductoryOfferSummary: String? = nil
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
    private var inFlightSync: [String: Task<Void, Error>] = [:]

    init(syncClient: any AppleSubscriptionSyncClienting) {
        self.syncClient = syncClient
    }

    deinit {
        updatesTask?.cancel()
    }

    func startTransactionListenerIfNeeded() async {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return }
        guard !listenerStarted else { return }
        listenerStarted = true
        updatesTask = Task {
            for await update in Transaction.updates {
                await self.handle(update)
            }
        }
    }

    func loadProducts() async throws -> [StoreKitTraxProProduct] {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else {
            logStoreKitProducts(requested: [], loaded: [], loadError: "paywall disabled")
            return []
        }
        let ids = TraxProProductConfiguration.allProductIDs
        let products: [Product]
        do {
            products = try await Product.products(for: ids)
        } catch {
            logStoreKitProducts(requested: ids, loaded: [], loadError: String(describing: error))
            throw error
        }
        logStoreKitProducts(
            requested: ids,
            loaded: products.map(\.id),
            loadError: products.isEmpty ? "StoreKit returned no products" : "none"
        )
        let sorted = products.sorted { lhs, rhs in
            Self.sortOrder(for: lhs.id) < Self.sortOrder(for: rhs.id)
        }
        var mapped: [StoreKitTraxProProduct] = []
        for product in sorted {
            mapped.append(await Self.makeProduct(product))
        }
        return mapped
    }

    func purchase(productID: String, appAccountToken: UUID?) async -> StoreKitPurchaseOutcome {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else {
            return .failed("In-app subscriptions aren't available in this version of TradeTraxs.")
        }
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                return .failed("TraxPro product unavailable")
            }

            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    do {
                        try await syncVerifiedTransaction(
                            transaction,
                            signedTransactionInfo: verification.jwsRepresentation
                        )
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
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return false }
        var syncedAny = false
        for await entitlement in Transaction.currentEntitlements {
            let transaction = try Self.checkVerified(entitlement)
            try await syncVerifiedTransaction(
                transaction,
                signedTransactionInfo: entitlement.jwsRepresentation
            )
            syncedAny = true
        }
        return syncedAny
    }

    func presentOfferCodeRedemption() async throws {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return }
        guard let scene = await StoreKitSubscriptionWindowScene.foreground() else {
            throw AppError.unknown(message: "Offer code redemption is unavailable right now.")
        }
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }

    func syncVerifiedTransactionsToServer() async throws {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return }
        var syncedAny = false
        for await entitlement in Transaction.currentEntitlements {
            let transaction = try Self.checkVerified(entitlement)
            try await syncVerifiedTransaction(
                transaction,
                signedTransactionInfo: entitlement.jwsRepresentation
            )
            syncedAny = true
        }
        if !syncedAny {
            AppLog.application.debug("StoreKit sync: no current entitlements to upload")
        }
    }

    private func syncVerifiedTransaction(
        _ transaction: Transaction,
        signedTransactionInfo: String
    ) async throws {
        let transactionID = String(transaction.id)
        guard !transactionID.isEmpty else {
            throw AppError.unknown(message: "Missing transaction id")
        }
        let signedTransaction = signedTransactionInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        logStoreKitSyncAttempt(
            transactionID: transactionID,
            productID: transaction.productID,
            environment: transaction.environment,
            signedJWSBytes: signedTransaction.utf8.count
        )
        if let blockMessage = Self.serverSyncBlockMessage(for: transaction.environment) {
            throw AppError.unknown(message: blockMessage)
        }
        if let existing = inFlightSync[transactionID] {
            try await existing.value
            return
        }
        let syncClient = self.syncClient
        let task = Task {
            _ = try await syncClient.sync(
                transactionID: transactionID,
                signedTransactionInfo: signedTransaction
            )
        }
        inFlightSync[transactionID] = task
        defer { inFlightSync[transactionID] = nil }
        try await task.value
    }

    /// Offer-code redemptions and purchases both arrive on ``Transaction.updates``; sync then finish only after server verification.
    private func handle(_ update: VerificationResult<Transaction>) async {
        do {
            let transaction = try Self.checkVerified(update)
            try await syncVerifiedTransaction(
                transaction,
                signedTransactionInfo: update.jwsRepresentation
            )
            await transaction.finish()
        } catch {
            AppLog.application.error(
                "StoreKit transaction update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw AppError.unknown(message: "Unverified App Store transaction")
        }
    }

    private static func makeProduct(_ product: Product) async -> StoreKitTraxProProduct {
        let periodLabel = product.subscription.map { subscriptionPeriodLabel($0.subscriptionPeriod) } ?? "Subscription"
        let offer = product.subscription?.introductoryOffer
        let eligible: Bool
        if let subscription = product.subscription, subscription.introductoryOffer != nil {
            eligible = await subscription.isEligibleForIntroOffer
        } else {
            eligible = false
        }
        let summary: String? = {
            guard eligible, let offer else { return nil }
            return IntroductoryOfferCopy.summary(
                paymentMode: introPaymentMode(offer.paymentMode),
                periodValue: offer.period.value,
                periodUnit: introPeriodUnit(offer.period.unit),
                displayPrice: offer.displayPrice
            )
        }()
        return StoreKitTraxProProduct(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            subscriptionPeriodLabel: periodLabel,
            billingInterval: TraxProProductConfiguration.billingInterval(for: product.id),
            hasEligibleIntroductoryOffer: eligible,
            introductoryOfferSummary: summary
        )
    }

    nonisolated private static func introPaymentMode(
        _ mode: Product.SubscriptionOffer.PaymentMode
    ) -> IntroductoryOfferCopy.PaymentMode {
        switch mode {
        case .freeTrial:
            return .freeTrial
        case .payAsYouGo:
            return .payAsYouGo
        case .payUpFront:
            return .payUpFront
        default:
            return .payAsYouGo
        }
    }

    nonisolated private static func introPeriodUnit(
        _ unit: Product.SubscriptionPeriod.Unit
    ) -> IntroductoryOfferCopy.PeriodUnit {
        switch unit {
        case .day:
            return .day
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        @unknown default:
            return .day
        }
    }

    nonisolated private static func subscriptionPeriodLabel(_ period: Product.SubscriptionPeriod) -> String {
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

    private func logStoreKitSyncAttempt(
        transactionID: String,
        productID: String,
        environment: AppStore.Environment,
        signedJWSBytes: Int
    ) {
        AppLog.application.info(
            """
            StoreKit server sync attempt \
            id=\(transactionID, privacy: .public) \
            product=\(productID, privacy: .public) \
            environment=\(String(describing: environment), privacy: .public) \
            signedJWSBytes=\(signedJWSBytes, privacy: .public)
            """
        )
    }

    /// Xcode StoreKit Configuration purchases are not Apple-signed for production verification.
    nonisolated private static func serverSyncBlockMessage(for environment: AppStore.Environment) -> String? {
        switch environment {
        case .xcode:
            return """
            This purchase came from Xcode StoreKit Testing, which cannot unlock TraxPro on the server. \
            Remove the StoreKit Configuration from your Run scheme (or disable StoreKit Testing) and purchase with a Sandbox Apple ID on device, or use TestFlight.
            """
        default:
            return nil
        }
    }

    private func logStoreKitProducts(requested: [String], loaded: [String], loadError: String) {
        #if DEBUG
        print(
            """
            [StoreKit]
            requestedProducts=\(requested)
            loadedProducts=\(loaded)
            loadError=\(loadError)
            """
        )
        #endif
    }

    nonisolated private static func sortOrder(for productID: String) -> Int {
        switch TraxProProductConfiguration.billingInterval(for: productID) {
        case .monthly: return 0
        case .sixMonth: return 1
        case .yearly: return 2
        case .none: return 99
        }
    }
}

@MainActor
enum StoreKitSubscriptionWindowScene {
    static func foreground() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
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
