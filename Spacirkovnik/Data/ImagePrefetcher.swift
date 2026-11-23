import Foundation

/// Stiahne obrázky špacírky vopred do diskovej cache (`URLCache.shared`), aby sa na trase
/// načítali hneď aj pri slabom signáli alebo bez neho. Beží na pozadí a nič neblokuje; čo sa
/// nestiahne, appka načíta až pri zobrazení. Obrázky, ktoré už v cache sú, sa znova nesťahujú.
/// Ekvivalent android `ImagePrefetcher`. Obrázky potom zobrazuje `CachedImage`.
enum ImagePrefetcher {
    static func prefetch(_ game: GameDefinition) {
        let urls = imageUrls(game)
        guard !urls.isEmpty else { return }
        Task.detached(priority: .background) {
            for url in urls {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    static func imageUrls(_ game: GameDefinition) -> [URL] {
        var seen = Set<String>()
        return game.screens.compactMap { screen in
            guard let s = screen.imageUrl?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
                  seen.insert(s).inserted else { return nil }
            return URL(string: s)
        }
    }
}
