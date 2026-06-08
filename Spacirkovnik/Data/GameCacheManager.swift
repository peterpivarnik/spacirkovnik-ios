import Foundation

/// Lokálna cache stiahnutých definícií hier pre offline hranie.
/// Ekvivalent android `GameCacheManager` — verzia hry sa porovnáva s katalógom,
/// aby sa zistilo, či treba znova stiahnuť.
final class GameCacheManager {
    static let shared = GameCacheManager()

    private let fileManager = FileManager.default
    private lazy var cacheDir: URL = {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("games", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func fileURL(for gameId: String) -> URL {
        cacheDir.appendingPathComponent("\(gameId).json")
    }

    func cachedGame(id gameId: String) -> GameDefinition? {
        let url = fileURL(for: gameId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameDefinition.self, from: data)
    }

    func store(_ game: GameDefinition) {
        guard let data = try? JSONEncoder().encode(game) else { return }
        try? data.write(to: fileURL(for: game.id))
    }

    /// Vráti hru z cache ak je verzia aktuálna, inak ju stiahne a uloží.
    func loadGame(id gameId: String, expectedVersion: Int?) async throws -> GameDefinition {
        if let cached = cachedGame(id: gameId),
           expectedVersion == nil || cached.version >= (expectedVersion ?? 0) {
            return cached
        }
        let fresh = try await ApiService.shared.getGame(id: gameId)
        store(fresh)
        return fresh
    }
}
