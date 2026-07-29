import Foundation
import Observation

/// Načítava katalóg hier a rieši sťahovanie/aktiváciu.
/// Ekvivalent android `GameListViewModel`.
@MainActor
@Observable
final class GameListViewModel {
    var games: [GameInfo] = []
    var isLoading = false
    var errorMessage: String?

    /// ID hier, ktoré sú pre používateľa odomknuté (zadarmo, kúpené alebo aktivované).
    /// Naplní sa z `AuthViewModel`/`PurchaseManager` po prihlásení.
    var unlockedGameIds: Set<String> = []

    /// Hry viditeľné v zozname — skryté (`hidden`) sa nezobrazujú, pokiaľ nie sú odomknuté.
    var visibleGames: [GameInfo] {
        games.filter { $0.status != .hidden || unlockedGameIds.contains($0.id) }
    }

    func loadGames() async {
        isLoading = true
        errorMessage = nil
        do {
            games = try await ApiService.shared.getGameIndex()
        } catch {
            errorMessage = "Nepodarilo sa načítať hry: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Product ID-čka špacírok na kúpu — pre `PurchaseManager.loadProducts`.
    var purchasableProductIds: [String] {
        games.filter { $0.status == .purchasable }.map { $0.googlePlayProductId ?? $0.id }
    }

    /// Sú v katalógu špacírky, ktoré sa dajú získať (kúpou alebo prihlásením)?
    var hasUnlockableGames: Bool {
        games.contains { $0.status == .purchasable || $0.status == .freeWithLogin }
    }

    /// Zloží odomknuté špacírky z aktivácií vo Firebase a z nákupov v App Store.
    func syncUnlocked(activatedGameIds: Set<String>, purchasedProductIds: Set<String>) {
        var ids = activatedGameIds
        for game in games where purchasedProductIds.contains(game.googlePlayProductId ?? game.id) {
            ids.insert(game.id)
        }
        unlockedGameIds = ids
    }

    func isUnlocked(_ game: GameInfo) -> Bool {
        switch game.status {
        case .active:
            return true
        case .purchasable, .freeWithLogin, .hidden:
            return unlockedGameIds.contains(game.id)
        case .comingSoon, .unknown, .none:
            return false
        }
    }
}
