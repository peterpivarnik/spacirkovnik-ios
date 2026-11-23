import SwiftUI
import FirebaseCore

@main
struct SpacirkovnikApp: App {
    init() {
        // Väčšia disková cache pre obrázky špacírok — sťahujú sa vopred, aby sa na trase
        // načítali aj bez signálu (ImagePrefetcher + CachedImage).
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )
        // Vyžaduje GoogleService-Info.plist v projekte (rovnaký Firebase projekt ako Android).
        // Ak súbor chýba, configure() preskočíme, aby appka nespadla počas vývoja UI.
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
