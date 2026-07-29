import SwiftUI

/// Koreňová obrazovka — zoznam špacírok s navigáciou do hrania.
struct RootView: View {
    @State private var listVM = GameListViewModel()
    @State private var locationManager = LocationManager()
    @State private var auth = AuthViewModel()
    @State private var purchases = PurchaseManager()
    /// Cestu drží root, aby zoznam vedel hru spustiť až po prejdení bránok (súhlas).
    @State private var path: [GameInfo] = []

    var body: some View {
        NavigationStack(path: $path) {
            // Zoznam má vlastnú hlavičku s logom (ako android), systémový navigation bar si skrýva.
            GameListView(viewModel: listVM, auth: auth, purchases: purchases, path: $path)
                .navigationDestination(for: GameInfo.self) { info in
                    GamePlayView(info: info, locationManager: locationManager)
                }
        }
        .task {
            locationManager.requestPermission()
            await listVM.loadGames()
        }
        // Ceny ukazujeme až prihlásenému hráčovi, tak ich dovtedy ani nesťahujeme.
        .task(id: priceLoadKey) {
            guard auth.isLoggedIn else { return }
            await purchases.loadProducts(ids: listVM.purchasableProductIds)
        }
        .onChange(of: auth.activatedGameIds) { _, _ in syncUnlocked() }
        .onChange(of: purchases.purchasedProductIds) { _, _ in syncUnlocked() }
        .onChange(of: listVM.games) { _, _ in syncUnlocked() }
    }

    private var priceLoadKey: String {
        "\(auth.isLoggedIn)-\(listVM.games.count)"
    }

    private func syncUnlocked() {
        listVM.syncUnlocked(
            activatedGameIds: auth.activatedGameIds,
            purchasedProductIds: purchases.purchasedProductIds
        )
    }
}

#Preview {
    RootView()
}
