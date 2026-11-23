import Foundation

/// Katalóg a stiahnuté hry uložené v telefóne, aby sa dalo hrať aj bez pripojenia.
/// Ekvivalent android `GameCacheManager` + `GameVersionIndex`.
///
/// Súbory sú v Application Support (nie v Caches) — systém ich pri nedostatku miesta nezmaže,
/// takže stiahnutá špacírka ostane hrateľná aj offline v teréne.
///
/// Verzie stiahnutých hier sú v malom súbore (`{"rybar-z-drazdiaka": 3, …}`), aby zoznam hier
/// nemusel kvôli jednému číslu čítať a rozoberať celé súbory hier. Kto má hry stiahnuté zo
/// staršej verzie appky, ten súbor ešte nemá — pri prvom načítaní sa vytvorí zo stiahnutých hier.
actor GameCacheManager {
    static let shared = GameCacheManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var versions: [String: Int]?

    private let baseDir: URL
    private let gamesDir: URL
    private let catalogFile: URL
    private let versionsFile: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("spacirkovnik", isDirectory: true)
        gamesDir = baseDir.appendingPathComponent("games", isDirectory: true)
        catalogFile = baseDir.appendingPathComponent("catalog.json")
        versionsFile = baseDir.appendingPathComponent("game-versions.json")
        try? FileManager.default.createDirectory(at: gamesDir, withIntermediateDirectories: true)
        Self.migrateLegacyCache(to: gamesDir)
    }

    // MARK: - Katalóg

    func saveCatalog(_ catalog: [GameInfo]) {
        guard let data = try? encoder.encode(catalog) else { return }
        try? data.write(to: catalogFile, options: .atomic)
    }

    func loadCatalog() -> [GameInfo]? {
        guard let data = try? Data(contentsOf: catalogFile) else { return nil }
        return try? decoder.decode([GameInfo].self, from: data)
    }

    // MARK: - Hry

    func saveGame(_ game: GameDefinition) {
        guard let data = try? encoder.encode(game) else { return }
        try? data.write(to: fileURL(for: game.id), options: .atomic)
        var map = loadVersions()
        map[game.id] = game.version
        versions = map
        writeVersions(map)
    }

    func loadGame(id gameId: String) -> GameDefinition? {
        guard let data = try? Data(contentsOf: fileURL(for: gameId)) else { return nil }
        return try? decoder.decode(GameDefinition.self, from: data)
    }

    /// Zabudne stiahnutú hru — zmaže jej súbor aj záznam o verzii. Zoznam ju potom ukáže ako
    /// nestiahnutú a stiahne ju znova.
    func forgetGame(id gameId: String) {
        var map = loadVersions()
        if map.removeValue(forKey: gameId) != nil {
            versions = map
            writeVersions(map)
        }
        try? fileManager.removeItem(at: fileURL(for: gameId))
    }

    /// Verzie stiahnutých hier (id → verzia). Prvé volanie siahne na disk, ďalšie idú z pamäte.
    @discardableResult
    func loadVersions() -> [String: Int] {
        if let versions { return versions }
        let map = readVersions() ?? rebuildVersions()
        versions = map
        writeVersions(map)
        return map
    }

    // MARK: - Interné

    private func fileURL(for gameId: String) -> URL {
        gamesDir.appendingPathComponent("\(gameId).json")
    }

    private func readVersions() -> [String: Int]? {
        guard let data = try? Data(contentsOf: versionsFile) else { return nil }
        return try? decoder.decode([String: Int].self, from: data)
    }

    private func rebuildVersions() -> [String: Int] {
        var map: [String: Int] = [:]
        let files = (try? fileManager.contentsOfDirectory(at: gamesDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            // Poškodený súbor berieme ako nestiahnutý — hra sa stiahne znova.
            if let data = try? Data(contentsOf: file),
               let game = try? decoder.decode(GameDefinition.self, from: data) {
                map[file.deletingPathExtension().lastPathComponent] = game.version
            }
        }
        return map
    }

    private func writeVersions(_ map: [String: Int]) {
        // Nevadí, ak zápis zlyhá: index ostane v pamäti a nabudúce sa vytvorí znova zo stiahnutých hier.
        guard let data = try? encoder.encode(map) else { return }
        try? data.write(to: versionsFile, options: .atomic)
    }

    /// Staršie verzie appky ukladali hry do Caches/games — presunieme ich, nech sa nesťahujú znova.
    private static func migrateLegacyCache(to gamesDir: URL) {
        let fm = FileManager.default
        let legacy = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("games", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let target = gamesDir.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try? fm.moveItem(at: file, to: target)
            }
        }
        try? fm.removeItem(at: legacy)
    }
}
