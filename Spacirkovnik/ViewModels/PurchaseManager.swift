import Foundation
import Observation
import StoreKit

/// In-app nákupy cez StoreKit 2 (iOS ekvivalent android Google Play Billing).
/// Ekvivalent android `PurchaseViewModel`.
///
/// Product ID-čka zodpovedajú `googlePlayProductId` z katalógu (napr. `tajomstvo_janka_krala`).
/// V App Store Connect treba vytvoriť Non-Consumable produkty s rovnakými ID.
///
/// TODO (na Macu): po úspešnom nákupe zapísať aktiváciu do Firebase
/// (`activations/{uid}/{gameId} = true`), aby sa hra odomkla aj na Androide — rovnaká logika.
@MainActor
@Observable
final class PurchaseManager {
    var products: [Product] = []
    var purchasedProductIds: Set<String> = []
    var isLoading = false
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Načíta produkty z App Store podľa product ID-čiek z katalógu.
    func loadProducts(ids: [String]) async {
        guard !ids.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            products = try await Product.products(for: ids)
            await refreshPurchased()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    purchasedProductIds.insert(transaction.productID)
                    await transaction.finish()
                    // TODO: zapísať aktiváciu do Firebase Realtime Database.
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshPurchased()
    }

    private func refreshPurchased() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIds = ids
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshPurchased()
                }
            }
        }
    }
}
