import SwiftUI

/// Hranie jednej hry — postupné obrazovky podľa typu. Ekvivalent android `GamePlayScreen`.
struct GamePlayView: View {
    let info: GameInfo
    var locationManager: LocationManager

    @State private var viewModel = GameDataViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer(); ProgressView("Načítavam hru…"); Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                ContentUnavailableView("Chyba", systemImage: "exclamationmark.triangle", description: Text(error))
                Spacer()
            } else if let screen = viewModel.currentScreen {
                ProgressView(value: viewModel.progress)
                    .tint(Color(hex: info.colorHex) ?? .accentColor)
                ScreenContentView(
                    screen: screen,
                    text: viewModel.currentText,
                    accentColor: Color(hex: info.colorHex) ?? .accentColor,
                    locationManager: locationManager,
                    onNext: { viewModel.next() }
                )
            }
        }
        .navigationTitle(info.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadGame(info: info) }
    }
}

/// Vykreslí obsah jednej obrazovky podľa jej typu.
private struct ScreenContentView: View {
    let screen: GameScreen
    let text: String?
    let accentColor: Color
    var locationManager: LocationManager
    let onNext: () -> Void

    @State private var selectedAnswer: GameAnswer?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let urlString = screen.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if let text {
                    Text(text)
                        .font(.system(size: CGFloat(screen.fontSize ?? 18)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                content
            }
            .padding()
        }
    }

    @ViewBuilder private var content: some View {
        switch screen.type {
        case .question:
            questionView
        case .navigation:
            NavigationTargetView(
                screen: screen,
                accentColor: accentColor,
                locationManager: locationManager,
                onArrived: onNext
            )
        case .continue, .browse, .unknown, .none:
            Button(action: onNext) {
                Text(screen.buttonText ?? "Ďalej")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
        }
    }

    private var questionView: some View {
        VStack(spacing: 12) {
            ForEach(screen.answers ?? [], id: \.self) { answer in
                Button {
                    selectedAnswer = answer
                    if answer.correct {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onNext() }
                    }
                } label: {
                    Text(answer.text).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: answer))
            }
            if let selected = selectedAnswer, !selected.correct {
                Text("Skús to znova 🙂").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func tint(for answer: GameAnswer) -> Color {
        guard let selected = selectedAnswer, selected == answer else { return accentColor }
        return answer.correct ? .green : .red
    }
}
