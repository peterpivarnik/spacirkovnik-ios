import Foundation
import Observation

/// Riadi stav jednej hry počas hrania — aktuálnu obrazovku a postup.
/// Ekvivalent android `GameDataViewModel`.
@MainActor
@Observable
final class GameDataViewModel {
    private(set) var game: GameDefinition?
    var currentIndex: Int = 0
    var isLoading = false
    var errorMessage: String?

    /// Rod hráča pre rodovo citlivé texty (`{mužský|ženský}`). Kým nie je zvolený, hra sa
    /// nezačne — pýtame sa na začiatku každej špacírky, rovnako ako na Androide.
    private(set) var gender: Gender?

    var currentScreen: GameScreen? {
        guard let game, game.screens.indices.contains(currentIndex) else { return nil }
        return game.screens[currentIndex]
    }

    var isLastScreen: Bool {
        guard let game else { return true }
        return currentIndex >= game.screens.count - 1
    }

    /// Podiel prejdených obrazoviek — na poslednej je pruh plný (ako na Androide).
    var progress: Double {
        guard let game, !game.screens.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(game.screens.count)
    }

    /// Text aktuálnej obrazovky s aplikovaným rodom.
    var currentText: String? {
        guard let text = currentScreen?.text else { return nil }
        guard let gender else { return text }
        return text.applyGender(gender)
    }

    func setGender(_ gender: Gender) {
        self.gender = gender
    }

    func loadGame(info: GameInfo) async {
        isLoading = true
        errorMessage = nil
        currentIndex = 0
        do {
            game = try await GameCacheManager.shared.loadGame(id: info.id, expectedVersion: info.version)
        } catch {
            errorMessage = "Hru sa nepodarilo načítať: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func next() {
        guard let game, currentIndex < game.screens.count - 1 else { return }
        currentIndex += 1
    }

    func back() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
}
