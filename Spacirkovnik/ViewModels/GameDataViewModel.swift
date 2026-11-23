import Foundation
import Observation

/// Riadi stav jednej hry počas hrania — aktuálnu obrazovku, uložený postup a koniec hry.
/// Ekvivalent android `GameDataViewModel`.
@MainActor
@Observable
final class GameDataViewModel {
    private(set) var game: GameDefinition?
    private(set) var currentIndex: Int = 0
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    /// Zhrnutie pre záverečnú obrazovku — nastaví sa po dohraní špacírky.
    private(set) var finished: FinishSummary?

    /// Rod hráča pre rodovo citlivé texty (`{mužský|ženský}`). Kým nie je zvolený, hra sa
    /// nezačne — pýtame sa na začiatku každej špacírky, rovnako ako na Androide.
    private(set) var gender: Gender?

    private var gameId: String?
    private let progressStore = GameProgressStore.shared

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

    /// Otvorí špacírku z telefónu (stiahol ju zoznam) a pokračuje tam, kde hráč skončil.
    /// Ak v telefóne nie je alebo je poškodená, skúsi ju stiahnuť znova.
    func loadGame(info: GameInfo) async {
        if gameId == info.id, game != nil { return }
        gameId = info.id
        isLoading = true
        errorMessage = nil
        finished = nil

        let cache = GameCacheManager.shared
        var loaded = await cache.loadGame(id: info.id)
        if loaded == nil || loaded?.screens.isEmpty == true {
            await cache.forgetGame(id: info.id)
            if let fresh = try? await ApiService.shared.getGame(id: info.id), !fresh.screens.isEmpty {
                await cache.saveGame(fresh)
                loaded = fresh
            } else {
                loaded = nil
            }
        }
        // Hráč medzitým otvoril inú hru — tento výsledok už nepatrí na obrazovku.
        guard gameId == info.id else { return }

        if let loaded, !loaded.screens.isEmpty {
            // Hry stiahnuté pred touto verziou appky obrázky vopred nemajú — doplníme ich teraz.
            ImagePrefetcher.prefetch(loaded)
            progressStore.markStartedIfNeeded(gameId: info.id)
            currentIndex = min(progressStore.progress(gameId: info.id), loaded.screens.count - 1)
            game = loaded
        } else {
            errorMessage = "Špacírku sa nepodarilo otvoriť. Skontroluj pripojenie a skús to znova."
        }
        isLoading = false
    }

    func next() {
        guard let game, currentIndex < game.screens.count - 1 else { return }
        currentIndex += 1
        saveProgress()
    }

    func back() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        saveProgress()
    }

    /// Hráč dohral špacírku: zapíše dokončenie, vymaže postup a pripraví zhrnutie pre záverečnú
    /// obrazovku (zastávky, úlohy, čas).
    func finishGame() {
        guard let gameId, let game else { return }
        let startedAt = progressStore.startedAt(gameId: gameId)
        GameCompletionRecorder.recordCompletion(gameId: gameId)
        progressStore.markCompleted(gameId: gameId)
        progressStore.clearProgress(gameId: gameId)
        finished = FinishSummary(title: game.title, screens: game.screens, startedAt: startedAt)
    }

    /// „Ukončiť a vymazať postup" — špacírka sa nabudúce začne odznova.
    func clearProgress() {
        guard let gameId else { return }
        progressStore.clearProgress(gameId: gameId)
    }

    private func saveProgress() {
        guard let gameId else { return }
        progressStore.saveProgress(gameId: gameId, screenIndex: currentIndex)
    }
}
