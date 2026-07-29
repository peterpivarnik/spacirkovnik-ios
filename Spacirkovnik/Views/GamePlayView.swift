import SwiftUI

/// Hranie jednej špacírky — postupné obrazovky podľa typu. Ekvivalent android `GamePlayScreen`:
/// tmavý gradient odvodený od farby špacírky, tenký ukazovateľ postupu, ikonka ukončenia
/// vpravo hore a obsah v krémovej karte.
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
            Button("Ukončiť", role: .destructive) { dismiss() }
            Button("Pokračovať", role: .cancel) {}
        } message: {
            Text("Naozaj chceš špacírku ukončiť a vrátiť sa do zoznamu?")
        }
    }

    /// Tenký pruh cez celú šírku — plní sa s každou prejdenou obrazovkou.
    @ViewBuilder private var progressBar: some View {
        if !viewModel.isLoading, viewModel.errorMessage == nil, viewModel.currentScreen != nil {
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

    private var exitButton: some View {
        HStack {
            Spacer()
            Button { showExitDialog = true } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.textOnDark)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ukončiť špacírku")
        }
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
        } else if viewModel.gender == nil, viewModel.currentScreen != nil {
            // Rod sa pýtame na začiatku každej špacírky — bez neho sa texty nedajú skloňovať.
            GenderSelectionView(colorHex: info.colorHex) { viewModel.setGender($0) }
        } else if let screen = viewModel.currentScreen {
            ScreenContentView(
                screen: screen,
                text: viewModel.currentText,
                accentColor: Color(hex: info.colorHex) ?? AppColor.primaryButton,
                locationManager: locationManager,
                canGoBack: viewModel.currentIndex > 0,
                canGoNext: !viewModel.isLastScreen,
                onNext: { viewModel.next() },
                onBack: { viewModel.back() },
                onFinish: { dismiss() }
            )
        }
    }
}

/// Vykreslí obsah jednej obrazovky podľa jej typu — kartu s obrázkom a textom, pod ňou akcie.
private struct ScreenContentView: View {
    let screen: GameScreen
    let text: String?
    let accentColor: Color
    var locationManager: LocationManager
    let canGoBack: Bool
    let canGoNext: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onFinish: () -> Void

    @State private var showWrongAnswerAlert = false

    private var fontSize: CGFloat { CGFloat(screen.fontSize ?? 18) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    card
                    if screen.type == .navigation {
                        NavigationTargetView(
                            screen: screen,
                            accentColor: accentColor,
                            locationManager: locationManager,
                            onArrived: onNext
                        )
                    }
                }
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)

            actions
                .padding(.top, 20)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 20)
        .alert("Zlá odpoveď", isPresented: $showWrongAnswerAlert) {
            Button("Skúsim znova", role: .cancel) {}
        } message: {
            Text("Skúš to znova, určite to zvládneš!")
        }
    }

    /// Krémová karta s obrázkom navrchu a textom obrazovky pod ním.
    private var card: some View {
        VStack(spacing: 0) {
            if let urlString = screen.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ZStack {
                        AppColor.amber.opacity(0.08)
                        ProgressView().tint(AppColor.amber)
                    }
                    .frame(height: 120)
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

    @ViewBuilder private var actions: some View {
        switch screen.type {
        case .question:
            VStack(spacing: 8) {
                ForEach(screen.answers ?? [], id: \.self) { answer in
                    Button {
                        if answer.correct { onNext() } else { showWrongAnswerAlert = true }
                    } label: {
                        Text(answer.text)
                            .font(.system(size: 16))
                            .foregroundStyle(AppColor.primaryButtonText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.horizontal, 12)
                            .background(AppColor.secondaryButton, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("answerButton")
                }
            }
        case .browse:
            HStack(spacing: 12) {
                gameButton(
                    screen.backButtonText ?? "Späť",
                    background: AppColor.backButton,
                    enabled: canGoBack,
                    identifier: "backButton",
                    action: onBack
                )
                gameButton(
                    screen.nextButtonText ?? "Ďalej",
                    background: AppColor.primaryButton,
                    enabled: canGoNext,
                    identifier: "nextButton",
                    action: onNext
                )
            }
        case .navigation:
            // Tlačidlo „Som na mieste!" si kreslí NavigationTargetView, keď je hráč v cieli.
            EmptyView()
        case .continue, .unknown, .none:
            gameButton(
                screen.buttonText ?? "Ďalej",
                background: AppColor.primaryButton,
                fontSize: 18,
                identifier: "nextButton",
                action: { if canGoNext { onNext() } else { onFinish() } }
            )
        }
    }

    private func gameButton(
        _ title: String,
        background: Color,
        fontSize: CGFloat = 16,
        enabled: Bool = true,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(AppColor.primaryButtonText)
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
