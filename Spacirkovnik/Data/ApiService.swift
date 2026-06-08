import Foundation

/// Rovnaký Firebase Realtime Database REST endpoint ako Android verzia.
let firebaseDatabaseURL = "https://spacirkovnik-app-default-rtdb.europe-west1.firebasedatabase.app/"

enum ApiError: Error {
    case badURL
    case badResponse(Int)
}

/// Sťahuje katalóg a definície hier z Firebase (ekvivalent android `ApiService` + Retrofit).
struct ApiService {
    static let shared = ApiService()

    private let decoder = JSONDecoder()
    private let session = URLSession.shared

    /// `GET catalog/games-info.json` → zoznam hier v katalógu.
    func getGameIndex() async throws -> [GameInfo] {
        try await get(path: "catalog/games-info.json")
    }

    /// `GET games/{gameId}.json` → plná definícia hry.
    func getGame(id gameId: String) async throws -> GameDefinition {
        try await get(path: "games/\(gameId).json")
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: firebaseDatabaseURL + path) else { throw ApiError.badURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ApiError.badResponse(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}
