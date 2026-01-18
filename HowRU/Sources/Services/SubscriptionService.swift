import Foundation
import StoreKit

/// Subscription tier for HowRU (matches backend PLAN_LIMITS)
enum SubscriptionTier: String, Codable {
    case free = "free"
    case plus = "plus"
    case family = "family"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "HowRU Plus"
        case .family: return "HowRU Family"
        }
    }

    var maxSupporters: Int {
        switch self {
        case .free: return 2
        case .plus: return 5
        case .family: return 15
        }
    }

    var hasSMSAlerts: Bool {
        self != .free
    }

    var hasAdvancedTrends: Bool {
        self != .free
    }

    var hasNoAds: Bool {
        self != .free
    }

    var hasPrioritySupport: Bool {
        self == .family
    }
}

/// Product identifiers for StoreKit (matches backend OFFERINGS)
enum ProductID: String, CaseIterable {
    case monthlyPlus = "com.howru.plus.monthly"
    case yearlyPlus = "com.howru.plus.yearly"
    case monthlyFamily = "com.howru.family.monthly"
    case yearlyFamily = "com.howru.family.yearly"

    var tier: SubscriptionTier {
        switch self {
        case .monthlyPlus, .yearlyPlus:
            return .plus
        case .monthlyFamily, .yearlyFamily:
            return .family
        }
    }

    var isYearly: Bool {
        switch self {
        case .yearlyPlus, .yearlyFamily:
            return true
        case .monthlyPlus, .monthlyFamily:
            return false
        }
    }
}

/// Service for managing subscriptions via StoreKit 2
@MainActor
@Observable
final class SubscriptionService {
    // MARK: - Properties

    static let shared = SubscriptionService()

    private(set) var currentTier: SubscriptionTier = .free
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false
    var purchaseError: String?

    /// Server-side feature limits (fetched from /billing/entitlements)
    private(set) var serverLimits: APIFeatureLimits?

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load products
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    /// Load available products from App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let productIDs = ProductID.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIDs)

            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Loaded \(products.count) products")
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Failed to load products: \(error)")
            }
            purchaseError = "Failed to load products"
        }
    }

    // MARK: - Purchase

    /// Purchase a subscription product
    /// - Parameter productID: The product to purchase
    /// - Returns: True if purchase was successful
    func purchase(_ productID: ProductID) async -> Bool {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            purchaseError = "Product not found"
            return false
        }

        return await purchase(product)
    }

    /// Purchase a product
    /// - Parameter product: The StoreKit Product to purchase
    /// - Returns: True if purchase was successful
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Check if the transaction is verified
                let transaction = try checkVerified(verification)

                // Update subscription status
                await updateSubscriptionStatus()

                // Sync with server
                await syncSubscriptionToServer()

                // Finish the transaction
                await transaction.finish()

                if AppConfig.shared.isLoggingEnabled {
                    print("[Subscription] Purchase successful: \(product.id)")
                }

                return true

            case .userCancelled:
                if AppConfig.shared.isLoggingEnabled {
                    print("[Subscription] User cancelled purchase")
                }
                return false

            case .pending:
                if AppConfig.shared.isLoggingEnabled {
                    print("[Subscription] Purchase pending")
                }
                purchaseError = "Purchase is pending approval"
                return false

            @unknown default:
                return false
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Purchase failed: \(error)")
            }
            purchaseError = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            await syncSubscriptionToServer()

            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Purchases restored")
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Failed to restore purchases: \(error)")
            }
            purchaseError = "Failed to restore purchases"
        }
    }

    // MARK: - Subscription Status

    /// Update the current subscription status
    func updateSubscriptionStatus() async {
        var newPurchasedIDs: Set<String> = []

        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // Check if it's still valid
                if transaction.revocationDate == nil {
                    newPurchasedIDs.insert(transaction.productID)
                }
            } catch {
                if AppConfig.shared.isLoggingEnabled {
                    print("[Subscription] Failed to verify transaction: \(error)")
                }
            }
        }

        purchasedProductIDs = newPurchasedIDs

        // Determine current tier
        if purchasedProductIDs.contains(ProductID.monthlyFamily.rawValue) ||
           purchasedProductIDs.contains(ProductID.yearlyFamily.rawValue) {
            currentTier = .family
        } else if purchasedProductIDs.contains(ProductID.monthlyPlus.rawValue) ||
                  purchasedProductIDs.contains(ProductID.yearlyPlus.rawValue) {
            currentTier = .plus
        } else {
            currentTier = .free
        }

        if AppConfig.shared.isLoggingEnabled {
            print("[Subscription] Current tier: \(currentTier.displayName)")
        }
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    // Update subscription status on main actor
                    await MainActor.run {
                        Task {
                            await self.updateSubscriptionStatus()
                            await self.syncSubscriptionToServer()
                        }
                    }

                    await transaction.finish()
                } catch {
                    if AppConfig.shared.isLoggingEnabled {
                        print("[Subscription] Transaction update verification failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Server Sync

    /// Fetch entitlements from the server (source of truth)
    /// This should be called after authentication and periodically to ensure tier is accurate
    func fetchEntitlements() async {
        guard AuthManager.shared.isAuthenticated else { return }

        do {
            let response: EntitlementsResponse = try await APIClient.shared.get("/billing/entitlements")

            // Update current tier based on server response
            switch response.plan {
            case "plus":
                currentTier = .plus
            case "family":
                currentTier = .family
            default:
                currentTier = .free
            }

            // Update server-side limits
            serverLimits = response.limits

            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Fetched entitlements from server: \(response.plan)")
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("[Subscription] Failed to fetch entitlements: \(error)")
            }
            // Fall back to local StoreKit verification
        }
    }

    /// Sync subscription status to server
    /// Note: Server-side receipt validation should be handled by RevenueCat or similar service.
    private func syncSubscriptionToServer() async {
        guard AuthManager.shared.isAuthenticated else { return }

        // StoreKit 2 handles on-device verification via App Store server.
        // After a purchase, RevenueCat webhook updates the backend.
        // We fetch entitlements to confirm the subscription is active.
        await fetchEntitlements()

        if AppConfig.shared.isLoggingEnabled {
            print("[Subscription] Subscription tier synced: \(currentTier.rawValue)")
        }
    }

    // MARK: - Helpers

    /// Verify a transaction
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Product Helpers

    /// Get product for a specific product ID
    func product(for productID: ProductID) -> Product? {
        products.first { $0.id == productID.rawValue }
    }

    /// Get monthly price for Plus tier
    var monthlyPlusPrice: String {
        product(for: .monthlyPlus)?.displayPrice ?? "$1.99"
    }

    /// Get yearly price for Plus tier
    var yearlyPlusPrice: String {
        product(for: .yearlyPlus)?.displayPrice ?? "$14.99"
    }

    /// Get monthly price for Family tier
    var monthlyFamilyPrice: String {
        product(for: .monthlyFamily)?.displayPrice ?? "$4.99"
    }

    /// Get yearly price for Family tier
    var yearlyFamilyPrice: String {
        product(for: .yearlyFamily)?.displayPrice ?? "$39.99"
    }

    /// Calculate yearly savings percentage for a given tier
    func yearlySavingsPercent(for tier: SubscriptionTier) -> Int {
        let monthlyProduct: ProductID
        let yearlyProduct: ProductID

        switch tier {
        case .plus:
            monthlyProduct = .monthlyPlus
            yearlyProduct = .yearlyPlus
        case .family:
            monthlyProduct = .monthlyFamily
            yearlyProduct = .yearlyFamily
        case .free:
            return 0
        }

        guard let monthly = product(for: monthlyProduct),
              let yearly = product(for: yearlyProduct) else {
            return tier == .plus ? 37 : 33 // Default savings estimates
        }

        let monthlyAnnual = monthly.price * 12
        let savings = (monthlyAnnual - yearly.price) / monthlyAnnual * 100
        return Int(Double(truncating: savings as NSNumber).rounded())
    }

    /// Calculate yearly savings percentage (defaults to Plus tier for backwards compatibility)
    var yearlySavingsPercent: Int {
        yearlySavingsPercent(for: .plus)
    }

    /// Check if user has a specific feature
    func hasFeature(_ feature: SubscriptionFeature) -> Bool {
        switch feature {
        case .smsAlerts:
            return currentTier.hasSMSAlerts
        case .advancedTrends:
            return currentTier.hasAdvancedTrends
        case .unlimitedSupporters:
            return currentTier == .family
        case .noAds:
            return currentTier.hasNoAds
        case .prioritySupport:
            return currentTier.hasPrioritySupport
        }
    }

    /// Check if user can add more supporters
    func canAddSupporter(currentCount: Int) -> Bool {
        return currentCount < currentTier.maxSupporters
    }
}

// MARK: - Subscription Error

enum SubscriptionError: Error, LocalizedError {
    case failedVerification
    case productNotFound
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed"
        case .productNotFound:
            return "Product not found"
        case .purchaseFailed:
            return "Purchase failed"
        }
    }
}

// MARK: - Subscription Feature

enum SubscriptionFeature {
    case smsAlerts
    case advancedTrends
    case unlimitedSupporters
    case noAds
    case prioritySupport
}
