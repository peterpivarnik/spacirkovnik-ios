import Foundation
import Observation

/// Stav stiahnutia špacírky v telefóne. Ekvivalent android `DownloadStatus`.
enum DownloadStatus {
    case notDownloaded, downloading, downloaded, updateAvailable
}

/// Špacírka z katalógu spolu so stavom jej stiahnutia.
struct GameWithStatus: Identifiable {
    let info: GameInfo
    var status: DownloadStatus
    var id: String { info.id }
}

/// Načítava katalóg hier a sťahuje hry do telefónu. Ekvivalent android `GameListViewModel`.
///
/// Katalóg sa po každom úspešnom načítaní uloží; bez pripojenia sa ukáže uložený katalóg
/// (offline režim) a stiahnuté špacírky sa dajú hrať ďalej.
@MainActor
@Observable
final class GameListViewModel {
    private(set) var games: [GameWithStatus] = []
    private(set) var isLoading = true
    /// Zoznam sa ukazuje z uloženej kópie, lebo sieť nie je dostupná.
    private(set) var isOffline = false
    /// Zoznam sa nenačítal vôbec — obrazovka ukáže len túto hlášku.
    private(set) var errorMessage: String?
    /// Nepodarilo sa stiahnuť jednu špacírku — krátka hláška nad zoznamom, zoznam ostáva.
    var downloadError: String?

    private var rawCatalog: [GameInfo] = []
    /// Testovacie špacírky prihláseného hráča (`testGames/{uid}`) — vidí aj skryté a má ich odomknuté.
    private var testGames: Set<String> = []
    private let cache = GameCacheManager.shared

    func loadGames() async {
        // Verzie stiahnutých hier treba mať skôr, než sa zostaví zoznam.
        let versions = await cache.loadVersions()
        do {
            let catalog = try await ApiService.shared.getGameIndex()
            await cache.saveCatalog(catalog)
            rawCatalog = catalog
            games = buildGameList(catalog, versions: versions)
            isOffline = false
            errorMessage = nil
            isLoading = false
            // Nová verzia už stiahnutej hry: stiahni ju na pozadí, stará sa dá hrať medzitým.
            for game in games where game.status == .updateAvailable {
                Task { await downloadGame(id: game.id) }
            }
        } catch {
            if let cached = await cache.loadCatalog() {
                rawCatalog = cached
                games = buildGameList(cached, versions: versions)
                isOffline = true
                errorMessage = nil
            } else if games.isEmpty {
                errorMessage = Self.isNetworkError(error)
                    ? "Nie je dostupné internetové pripojenie."
                    : "Nepodarilo sa načítať zoznam špacírok."
            }
            isLoading = false
        }
    }

    func setTestGames(_ ids: Set<String>) {
        guard ids != testGames else { return }
        testGames = ids
        guard !rawCatalog.isEmpty else { return }
        Task {
            let versions = await cache.loadVersions()
            games = buildGameList(rawCatalog, versions: versions)
        }
    }

    func isTestGame(_ gameId: String) -> Bool {
        testGames.contains(gameId)
    }

    /// Stiahne definíciu špacírky (malý JSON) a na pozadí aj jej obrázky.
    func downloadGame(id gameId: String) async {
        guard let previous = games.first(where: { $0.id == gameId })?.status,
              previous != .downloading else { return }
        updateStatus(gameId, .downloading)
        do {
            let game = try await ApiService.shared.getGame(id: gameId)
            await cache.saveGame(game)
            updateStatus(gameId, .downloaded)
            // Obrázky na pozadí, kým je hráč ešte doma na Wi-Fi; hrať sa dá hneď.
            ImagePrefetcher.prefetch(game)
        } catch {
            if previous == .updateAvailable {
                // Nepodarila sa len aktualizácia — stará verzia ostáva v telefóne a dá sa hrať.
                updateStatus(gameId, .updateAvailable)
            } else {
                // Karta ukáže „Skúsiť znova"; zoznam ostáva, chyba ide len do krátkej hlášky.
                updateStatus(gameId, .notDownloaded)
                downloadError = "Špacírku sa nepodarilo stiahnuť. Skontroluj pripojenie a skús to znova."
            }
        }
    }

    /// Product ID-čka špacírok na kúpu — pre `PurchaseManager.loadProducts`.
    var purchasableProductIds: [String] {
        games.map(\.info).filter { $0.status == .purchasable }.map { $0.googlePlayProductId ?? $0.id }
    }

    /// Sú v katalógu špacírky, ktoré sa dajú získať (kúpou alebo prihlásením)?
    var hasUnlockableGames: Bool {
        games.contains { $0.info.status == .purchasable || $0.info.status == .freeWithLogin }
    }

    // MARK: - Interné

    private func buildGameList(_ catalog: [GameInfo], versions: [String: Int]) -> [GameWithStatus] {
        catalog
            .filter { $0.status != .hidden || testGames.contains($0.id) }
            .map { info in
                let status: DownloadStatus
                if let cached = versions[info.id] {
                    status = cached < info.version ? .updateAvailable : .downloaded
                } else {
                    status = .notDownloaded
                }
                // Prebiehajúce sťahovanie nechceme obnovením zoznamu zahodiť.
                if games.first(where: { $0.id == info.id })?.status == .downloading {
                    return GameWithStatus(info: info, status: .downloading)
                }
                return GameWithStatus(info: info, status: status)
            }
    }

    private func updateStatus(_ gameId: String, _ status: DownloadStatus) {
        guard let index = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[index].status = status
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
