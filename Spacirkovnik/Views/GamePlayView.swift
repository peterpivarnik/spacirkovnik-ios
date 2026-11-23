import SwiftUI

/// Hranie jednej špacírky — postupné obrazovky podľa typu. Ekvivalent android `GamePlayScreen`:
/// tmavý gradient odvodený od farby špacírky, tenký ukazovateľ postupu, ikonka ukončenia
/// vpravo hore a obsah v krémovej karte. Po dohraní záverečná obrazovka s pohárom.
struct GamePlayView: View {
    let info: GameInfo
    var locationManager: LocationManager

    @State private var viewModel = GameDataViewModel()
    @State private var showExitDialog = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColor.gameGradient(colorHex: info.colorHex).ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                exitButton
                content.frame(maxHeight: .infinity)
            }
        }
        // Hore je vlastný pruh postupu a ikonka ukončenia, systémová lišta by ich len zdvojila.
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadGame(info: info) }
        .alert("Ukončiť špacírku", isPresented: $showExitDialog) {
            Button("Ukončiť a uložiť") { dismiss() }
            Button("Ukončiť a vymazať postup", role: .destructive) {
                viewModel.clearProgress()
                dismiss()
            }
            Button("Zrušiť", role: .cancel) {}
        } message: {
            Text("Chceš si uložiť postup a pokračovať neskôr, alebo začať odznova?\n\nPri vymazaní postupu budete musieť prejsť špacírku odznova!")
        }
    }

    /// Tenký pruh cez celú šírku — plní sa s každou prejdenou obrazovkou.
    @ViewBuilder private var progressBar: some View {
        if !viewModel.isLoading, viewModel.errorMessage == nil, viewModel.finished == nil,
           viewModel.currentScreen != nil {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    AppColor.textOnDark.opacity(0.25)
                    AppColor.amber.frame(width: geo.size.width * viewModel.progress)
                }
            }
            .frame(height: 4)
            .animation(.easeInOut, value: viewModel.progress)
        }
    }

    /// Na záverečnej obrazovke už nie je čo ukončovať ani ukladať.
    private var exitButton: some View {
        HStack {
            Spacer()
            if viewModel.finished == nil {
                Button { showExitDialog = true } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColor.textOnDark)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ukončiť špacírku")
            }
        }
        .frame(minHeight: 40)
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isLoading {
            ProgressView().tint(AppColor.amber).frame(maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(AppColor.textOnDark)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxHeight: .infinity)
        } else if let summary = viewModel.finished {
            FinishView(summary: summary, onDone: { dismiss() })
        } else if viewModel.gender == nil, viewModel.currentScreen != nil {
            // Rod sa pýtame na začiatku každej špacírky — bez neho sa texty nedajú skloňovať.
            GenderSelectionView(colorHex: info.colorHex) { viewModel.setGender($0) }
        } else if let screen = viewModel.currentScreen {
            ScreenContentView(
                screen: screen,
                screenIndex: viewModel.currentIndex,
                text: viewModel.currentText,
                locationManager: locationManager,
                canGoBack: viewModel.currentIndex > 0,
                isLastScreen: viewModel.isLastScreen,
                onNext: { viewModel.next() },
                onBack: { viewModel.back() },
                onFinish: { viewModel.finishGame() }
            )
            // Každá obrazovka má vlastný stav (odpovede, trasa) — aj keď majú dve za sebou rovnaký obsah.
            .id(viewModel.currentIndex)
        }
    }
}

/// Vykreslí obsah jednej obrazovky podľa jej typu — kartu s obrázkom a textom, pod ňou akcie.
private struct ScreenContentView: View {
    let screen: GameScreen
    let screenIndex: Int
    let text: String?
    var locationManager: LocationManager
    let canGoBack: Bool
    let isLastScreen: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onFinish: () -> Void

    private var fontSize: CGFloat { CGFloat(screen.fontSize ?? 18) }

    var body: some View {
        if screen.type == .navigation {
            ScrollView {
                VStack(spacing: 0) {
                    card.padding(.top, 24)
                    NavigationTargetView(
                        screen: screen,
                        locationManager: locationManager,
                        onArrived: onNext
                    )
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    card.padding(.top, 24)
                }
                .scrollIndicators(.hidden)

                actions
                    .padding(.top, 20)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
    }

    /// Krémová karta s obrázkom navrchu a textom obrazovky pod ním.
    private var card: some View {
        VStack(spacing: 0) {
            if let urlString = screen.imageUrl, !urlString.isEmpty {
                CachedImage(urlString: urlString) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ZStack {
                        AppColor.amber.opacity(0.08)
                        ProgressView().tint(AppColor.amber)
                    }
                    .frame(height: 120)
                } failure: {
                    imageOfflinePlaceholder
                }
                .frame(maxWidth: .infinity)
            }
            if let text, !text.isEmpty {
                Text(text)
                    .font(.system(size: fontSize, weight: fontSize > 20 ? .bold : .regular))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textDark)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            }
        }
        .background(AppColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    /// Obrázok sa nenačítal (offline a nie je v cache) — namiesto prázdneho miesta vysvetlenie.
    private var imageOfflinePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.amber)
            Text("Načítanie obrázka vyžaduje pripojenie na internet")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textMedium)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(AppColor.amber.opacity(0.08))
    }

    @ViewBuilder private var actions: some View {
        switch screen.type {
        case .question:
            QuestionAnswersView(answers: screen.answers ?? [], onCorrect: onNext)
        case .browse:
            HStack(spacing: 12) {
                GameButton(
                    title: screen.backButtonText ?? "Späť",
                    background: AppColor.backButton,
                    enabled: canGoBack,
                    identifier: "backButton",
                    action: onBack
                )
                GameButton(
                    title: screen.nextButtonText ?? "Ďalej",
                    background: AppColor.primaryButton,
                    enabled: !isLastScreen,
                    identifier: "nextButton",
                    action: onNext
                )
            }
        case .navigation:
            EmptyView()
        case .continue, .unknown, .none:
            // Z poslednej obrazovky sa ide na záverečnú obrazovku, nie do zoznamu — preto
            // jednotný text bez ohľadu na údaje špacírky (staršie majú „Späť na zoznam").
            GameButton(
                title: isLastScreen ? "Dokončiť špacírku" : (screen.buttonText ?? "Ďalej"),
                background: AppColor.primaryButton,
                fontSize: 18,
                identifier: "nextButton",
                action: { if isLastScreen { onFinish() } else { onNext() } }
            )
        }
    }
}

/// Odpovede na kvízovú otázku. Zlá odpoveď nevyskakuje v okne, ktoré treba zatvárať: tlačidlo
/// sa zatrasie, ostane označené „✗" a nad odpoveďami sa objaví povzbudenie. Správna na chvíľu
/// zozelenie s „✓", telefón krátko zavibruje a až potom sa ide ďalej — hráč (dieťa) vidí, že trafil.
/// Ekvivalent android `QuestionWithAnswers`.
private struct QuestionAnswersView: View {
    let answers: [GameAnswer]
    let onCorrect: () -> Void

    @State private var correctIndex: Int?
    @State private var wrongIndices: Set<Int> = []
    @State private var shakeTrigger: [Int: Int] = [:]

    /// Ako dlho ostane správna odpoveď zelená, kým sa hra posunie ďalej.
    private let correctPause: Duration = .milliseconds(900)

    var body: some View {
        VStack(spacing: 8) {
            if !wrongIndices.isEmpty && correctIndex == nil {
                Text("Tadiaľto cesta nevedie — skús inú odpoveď!")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.textOnDark)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
            }
            ForEach(Array(answers.enumerated()), id: \.offset) { index, answer in
                answerButton(index: index, answer: answer)
            }
        }
        .task(id: correctIndex) {
            guard correctIndex != nil else { return }
            Haptics.correct()
            try? await Task.sleep(for: correctPause)
            guard !Task.isCancelled else { return }
            onCorrect()
        }
    }

    private func answerButton(index: Int, answer: GameAnswer) -> some View {
        let isCorrect = correctIndex == index
        let isWrong = wrongIndices.contains(index)
        let title = isCorrect ? "✓ Správne! \(answer.text)" : (isWrong ? "✗ \(answer.text)" : answer.text)
        let background: Color = isCorrect
            ? Color(rgb: 0x2E7D32)
            : (isWrong ? Color(rgb: 0xB3261E).opacity(0.8) : AppColor.secondaryButton)
        return Button {
            guard correctIndex == nil else { return } // už ideme ďalej
            if answer.correct {
                correctIndex = index
            } else {
                wrongIndices.insert(index)
                shakeTrigger[index, default: 0] += 1
                Haptics.wrong()
            }
        } label: {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(isWrong ? 0.9 : 1))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 12)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // Zlú odpoveď už znova neťukne; ostane viditeľná, aby bolo jasné, čo už skúšal.
        .disabled(isWrong)
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger[index] ?? 0)))
        .animation(.linear(duration: 0.35), value: shakeTrigger[index] ?? 0)
        .accessibilityIdentifier("answerButton")
    }
}

/// Zatrasenie pri zlej odpovedi — ako „nie" hlavou.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = 12 * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Plné tlačidlo hry na tmavom podklade.
struct GameButton: View {
    let title: String
    let background: Color
    var fontSize: CGFloat = 16
    var enabled: Bool = true
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(AppColor.primaryButtonText.opacity(enabled ? 1 : 0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 12)
                .background(
                    enabled ? background : AppColor.disabledButton,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}
