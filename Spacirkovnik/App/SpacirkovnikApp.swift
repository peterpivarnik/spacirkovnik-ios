import SwiftUI
import FirebaseCore

@main
struct SpacirkovnikApp: App {
    init() {
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
