import Foundation
import Observation

/// Uložený postup v špacírkach — kde hráč skončil, kedy začal a ktoré už dohral.
/// Ekvivalent android `GameProgressManager`. Je `@Observable`, aby karta v zozname hneď
/// ukázala „Pokračovať" / „Prejsť znova", keď sa hráč vráti z hry.
@MainActor
@Observable
final class GameProgressStore {
    static let shared = GameProgressStore()

    private let defaults = UserDefaults.standard
    private static let progressKey = "game_progress.index"
    private static let startedKey = "game_progress.started"
    private static let completedKey = "game_progress.completed"

    private var progress: [String: Int]
    private var startedAt: [String: Double]
    private var completed: Set<String>

    private init() {
        progress = defaults.dictionary(forKey: Self.progressKey) as? [String: Int] ?? [:]
        startedAt = defaults.dictionary(forKey: Self.startedKey) as? [String: Double] ?? [:]
        completed = Set(defaults.stringArray(forKey: Self.completedKey) ?? [])
    }

    func saveProgress(gameId: String, screenIndex: Int) {
        progress[gameId] = screenIndex
        persist()
    }

    func progress(gameId: String) -> Int {
        progress[gameId] ?? 0
    }

    func hasProgress(gameId: String) -> Bool {
        (progress[gameId] ?? 0) > 0
    }

    /// Vymaže postup aj čas začatia — špacírka sa ďalej hrá od začiatku.
    func clearProgress(gameId: String) {
        progress.removeValue(forKey: gameId)
        startedAt.removeValue(forKey: gameId)
        persist()
    }

    /// Zapamätá si, kedy hráč špacírku začal — ak ešte nie je zapísané. Pre čas na konci hry.
    func markStartedIfNeeded(gameId: String, now: Date = Date()) {
        guard startedAt[gameId] == nil else { return }
        startedAt[gameId] = now.timeIntervalSince1970
        persist()
    }

    func startedAt(gameId: String) -> Date? {
        startedAt[gameId].map { Date(timeIntervalSince1970: $0) }
    }

    func markCompleted(gameId: String) {
        completed.insert(gameId)
        persist()
    }

    func isCompleted(gameId: String) -> Bool {
        completed.contains(gameId)
    }

    func clearCompleted(gameId: String) {
        completed.remove(gameId)
        persist()
    }

    private func persist() {
        defaults.set(progress, forKey: Self.progressKey)
        defaults.set(startedAt, forKey: Self.startedKey)
        defaults.set(Array(completed), forKey: Self.completedKey)
    }
}
