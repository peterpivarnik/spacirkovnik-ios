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
