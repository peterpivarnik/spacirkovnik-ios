import SwiftUI

/// Koreňová obrazovka — zoznam hier s navigáciou do hrania.
struct RootView: View {
    @State private var listVM = GameListViewModel()
    @State private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            GameListView(viewModel: listVM)
                .navigationTitle("Špacírkovník")
                .navigationDestination(for: GameInfo.self) { info in
                    GamePlayView(info: info, locationManager: locationManager)
                }
        }
        .task {
            locationManager.requestPermission()
            await listVM.loadGames()
        }
    }
}

#Preview {
    RootView()
}
