import SwiftUI
import UIKit

/// Obrázok z internetu, ktorý sa prednostne berie z diskovej cache (`URLCache.shared`) — aj keď
/// je „starý". Obrázky špacírok sťahuje vopred `ImagePrefetcher`, takže na trase sa načítajú aj
/// bez signálu. `AsyncImage` by bez siete zlyhal, lebo Firebase Storage posiela `max-age=0`.
struct CachedImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case success(UIImage)
        case failure
    }

    var body: some View {
        Group {
            switch phase {
            case .loading: placeholder()
            case .success(let image): content(Image(uiImage: image))
            case .failure: failure()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .failure
            return
        }
        if case .success = phase {} else { phase = .loading }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = UIImage(data: data) {
                phase = .success(image)
            } else {
                phase = .failure
            }
        } catch {
            if !Task.isCancelled { phase = .failure }
        }
    }
}

extension CachedImage where Failure == Placeholder {
    /// Pri chybe ukáže to isté, čo počas načítania.
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(url: url, content: content, placeholder: placeholder, failure: placeholder)
    }
}

extension CachedImage {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.init(url: urlString.flatMap { URL(string: $0) }, content: content, placeholder: placeholder, failure: failure)
    }
}
