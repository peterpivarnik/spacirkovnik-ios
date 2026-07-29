import SwiftUI

/// Zoznam dostupných špacírok z katalógu. Ekvivalent android `GameListScreen` — vrátane
/// vzhľadu: béžové pozadie, vlastná hlavička s logom a krémové karty s rozbaľovaním.
///
/// Zamknutá karta povie, čo treba na jej odomknutie (prihlásenie alebo kúpa) — bez toho
/// hráč nemal z čoho vedieť, že sa špacírka vôbec dá získať.
struct GameListView: View {
    @Bindable var viewModel: GameListViewModel
    var auth: AuthViewModel
    var purchases: PurchaseManager
    @Binding var path: [GameInfo]

    @State private var expandedGameId: String?
    @State private var showAuthSheet = false
    @State private var showAccountSheet = false
    /// Špacírka, ktorú chcel hráč odomknúť prihlásením — po prihlásení jej kartu rozbalíme,
    /// nech sa k nej nemusí preklikávať späť (android `pendingUnlockGameId`).
    @State private var pendingUnlockGameId: String?
    @State private var consentGame: GameInfo?
    @State private var isSavingConsent = false
    @State private var consentError: String?
    @State private var alertMessage: String?

    var body: some View {
        ZStack {
            AppColor.mainBackground.ignoresSafeArea()
            content.padding(16)
        }
        // Hlavičku si kreslíme sami (logo + podtitul + účet), systémový title by ju zdvojil.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAuthSheet, onDismiss: {
            // Zavreté bez prihlásenia — nemáme na čo nadväzovať.
            if !auth.isLoggedIn { pendingUnlockGameId = nil }
        }) {
            AuthSheet(auth: auth, onSignedIn: { showAuthSheet = false })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountSheet(auth: auth)
                .presentationDetents([.height(240)])
        }
        .sheet(item: $consentGame) { game in
            if let consent = game.consent {
                GameConsentSheet(
                    consent: consent,
                    isSaving: isSavingConsent,
                    errorMessage: consentError,
                    onAccept: { accept(consent, for: game) },
                    onDecline: { consentGame = nil }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .alert(
            "Špacírkovník",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            actions: { Button("Rozumiem", role: .cancel) { alertMessage = nil } },
            message: { Text(alertMessage ?? "") }
        )
        // Po prihlásení sa vráť k špacírke, kvôli ktorej hráč prihlásenie otvoril. Čakáme
        // na dotiahnuté aktivácie, inak by sa karta rozbalila ešte v zamknutom stave.
        .onChange(of: accountReady) { _, ready in
            guard ready, let gameId = pendingUnlockGameId,
                  viewModel.visibleGames.contains(where: { $0.id == gameId }) else { return }
            pendingUnlockGameId = nil
            expandedGameId = gameId
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 8) {
            header
            if viewModel.isLoading && viewModel.games.isEmpty {
                Spacer()
                ProgressView().tint(AppColor.amber)
                Spacer()
            } else if let error = viewModel.errorMessage, viewModel.games.isEmpty {
                Spacer()
                Text(error)
                    .foregroundStyle(AppColor.textOnBeigeSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                if !auth.isLoggedIn && viewModel.hasUnlockableGames { signInBanner }
                cards
            }
        }
    }

    /// Logo, názov s podtitulom a účet — android hlavička zoznamu.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            VStack(spacing: 2) {
                Text("Špacírkovník")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColor.textOnBeige)
                    .lineLimit(1)
                Text("Vyber si dobrodružstvo")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textOnBeigeSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            accountControl
                .frame(minWidth: 56)
        }
    }

    /// Bez prihlásenia nie je z ničoho zrejmé, že ostatné špacírky sa dajú získať —
    /// pruh to povie skôr, než hráč začne klikať po kartách.
    private var signInBanner: some View {
        Button {
            auth.clearError()
            showAuthSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.open")
                    .font(.system(size: 14))
                Text("Prihlás sa a odomkni ďalšie špacírky")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(AppColor.textOnBeige)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColor.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.visibleGames) { game in
                    GameCard(
                        game: game,
                        unlocked: viewModel.isUnlocked(game),
                        isSignedIn: auth.isLoggedIn,
                        isExpanded: expandedGameId == game.id,
                        price: purchases.price(for: productId(of: game)),
                        isPurchasing: purchases.purchasingProductId == productId(of: game),
                        onToggle: { toggle(game) },
                        onPlay: { startGame(game) },
                        onSignIn: {
                            pendingUnlockGameId = game.id
                            auth.clearError()
                            showAuthSheet = true
                        },
                        onPurchase: {
                            Task { await purchases.purchase(productId: productId(of: game)) }
                        }
                    )
                }
            }
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.loadGames() }
    }

    /// Pre neprihláseného je prihlásenie hlavná akcia — nie zašedená ikonka bez popisu,
    /// ale viditeľné tlačidlo.
    @ViewBuilder private var accountControl: some View {
        if auth.isLoadingAccount {
            ProgressView().tint(AppColor.amber)
        } else if auth.isLoggedIn {
            Button { showAccountSheet = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(AppColor.amber)
                    if let firstName = auth.firstName, !firstName.isEmpty {
                        Text(firstName)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.textOnBeigeSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                auth.clearError()
                showAuthSheet = true
            } label: {
                Text("Prihlásiť")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.primaryButtonText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColor.primaryButton, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var accountReady: Bool { auth.isLoggedIn && !auth.isLoadingAccount }

    private func productId(of game: GameInfo) -> String {
        game.googlePlayProductId ?? game.id
    }

    private func toggle(_ game: GameInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedGameId = expandedGameId == game.id ? nil : game.id
        }
    }

    /// Súhlas: ak ho špacírka vyžaduje a hráč aktuálnu verziu ešte neprijal, najprv hárok.
    private func startGame(_ game: GameInfo) {
        guard let consent = game.consent else {
            path.append(game)
            return
        }
        let accepted = auth.hasConsent(gameId: game.id, version: consent.version)
            || ConsentStore.shared.acceptedVersion(gameId: game.id) >= consent.version
        if accepted {
            path.append(game)
            return
        }
        guard auth.isLoggedIn else {
            alertMessage = "Pre túto špacírku sa najprv prihlás – zdieľa sa e-mail s organizátorom."
            return
        }
        consentError = nil
        consentGame = game
    }

    @MainActor private func accept(_ consent: GameConsent, for game: GameInfo) {
        isSavingConsent = true
        consentError = nil
        Task {
            let saved = await auth.recordConsent(gameId: game.id, version: consent.version)
            isSavingConsent = false
            if saved {
                ConsentStore.shared.setAccepted(gameId: game.id, version: consent.version)
                consentGame = nil
                path.append(game)
            } else {
                // Hárok necháme otvorený, nech to hráč vie skúsiť znova.
                consentError = "Súhlas sa nepodarilo uložiť. Skontroluj pripojenie a skús to znova."
            }
        }
    }
}

/// Karta jednej špacírky — zbalený riadok (obrázok, názov, stav) a po ťuknutí detail
/// s popisom, parametrami trasy a akciou. Ekvivalent android `GameCard`.
private struct GameCard: View {
    let game: GameInfo
    let unlocked: Bool
    let isSignedIn: Bool
    let isExpanded: Bool
    let price: String?
    let isPurchasing: Bool
    let onToggle: () -> Void
    let onPlay: () -> Void
    let onSignIn: () -> Void
    let onPurchase: () -> Void

    /// Stmavenie je hlavný signál „túto špacírku ešte nemáš" — drží sa obsahu karty
    /// (obrázok, názov, popis). Prvky, ktoré nesú ponuku (cena, košík, štítok ZADARMO,
    /// tlačidlá), ostávajú v plnej sýtosti, nech je vidieť, čo sa s tým dá spraviť.
    private var dim: Double { unlocked ? 1 : 0.5 }

    /// „Ide sa získať hneď" — kúpou alebo prihlásením; podčiarkne to jantárový rám.
    private var isOffer: Bool {
        !unlocked && (game.status == .purchasable || game.status == .freeWithLogin)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) { collapsedRow }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gameCard")

            if isExpanded { expandedDetail }
        }
        .background(AppColor.cardBg.opacity(unlocked ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if !unlocked {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isOffer ? AppColor.amber.opacity(0.45) : AppColor.textMedium.opacity(0.2),
                        lineWidth: 1
                    )
            }
        }
    }

    private var collapsedRow: some View {
        HStack(spacing: 12) {
            thumbnail.opacity(dim)
            Text(game.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textDark)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 48)
                .opacity(dim)
            statusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        AsyncImage(url: URL(string: game.imageUrl ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                AppColor.amber.opacity(0.2)
                Image(systemName: "figure.walk")
                    .foregroundStyle(AppColor.amber)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Zbalený riadok má sám povedať, čo by odomknutie špacírky stálo: cena + košík pri kúpe,
    /// štítok ZADARMO po prihlásení, hodiny pri pripravovanej, inak zámok. Odomknutá špacírka
    /// ukazuje šípku rozbalenia.
    @ViewBuilder private var statusIndicator: some View {
        if !unlocked, game.status == .purchasable {
            HStack(spacing: 6) {
                // Ceny ukazujeme až prihlásenému hráčovi — dovtedy ich ani nesťahujeme.
                if isSignedIn, let price {
                    Text(price).font(.system(size: 13, weight: .semibold))
                }
                Image(systemName: "cart").font(.system(size: 16))
            }
            .foregroundStyle(AppColor.amber)
        } else if !unlocked, game.status == .freeWithLogin {
            Text("ZADARMO")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColor.purchaseButton)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppColor.purchaseButton.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        } else if !unlocked, game.status == .comingSoon {
            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.textMedium)
        } else if !unlocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.textMedium)
        } else {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textMedium)
        }
    }

    private var expandedDetail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(game.description)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColor.textMedium)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if let urlString = game.imageUrl, !urlString.isEmpty {
                    AsyncImage(url: URL(string: urlString)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        AppColor.amber.opacity(0.15)
                    }
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .opacity(dim)

            Divider()
                .overlay(AppColor.textMedium.opacity(0.2))
                .padding(.vertical, 10)

            VStack(spacing: 4) {
                if let region = game.region {
                    metaRow(icon: "mappin.and.ellipse", text: region)
                }
                if game.estimatedDurationMinutes != nil || game.distanceKm != nil {
                    HStack(spacing: 12) {
                        if let mins = game.estimatedDurationMinutes {
                            metaRow(icon: "clock", text: "\(mins) min")
                        }
                        if game.estimatedDurationMinutes != nil && game.distanceKm != nil {
                            Text("•").font(.system(size: 12)).foregroundStyle(AppColor.textMedium)
                        }
                        if let km = game.distanceKm {
                            metaRow(icon: "figure.walk", text: "\(km) km")
                        }
                    }
                }
                if let startName = game.startName {
                    metaRow(icon: "flag", text: startName)
                }
                if let endName = game.endName {
                    metaRow(icon: "flag.checkered", text: endName)
                }
            }
            .opacity(dim)

            action.padding(.top, 16)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(AppColor.textMedium)
    }

    @ViewBuilder private var action: some View {
        if unlocked {
            filledButton("Prejsť", color: AppColor.primaryButton, action: onPlay)
                .accessibilityIdentifier("playButton")
        } else if !isSignedIn && isOffer {
            // Bez tohto bloku bola rozbalená karta pre neprihláseného prázdna — nedozvedel
            // sa, že špacírku odomkne prihlásenie.
            let isFree = game.status == .freeWithLogin
            VStack(spacing: 8) {
                // Zelená ostáva vyhradená pre skutočnú kúpu, toto tlačidlo len prihlasuje.
                filledButton(
                    isFree ? "Prihlásiť sa a hrať zadarmo" : "Prihlásiť sa",
                    color: AppColor.primaryButton,
                    action: onSignIn
                )
                // Bez prihlásenia nevieme, či špacírku hráč náhodou už nekúpil (nový telefón,
                // reinštalácia), takže tlačidlo nič netvrdí o kúpe a text pokrýva oba prípady.
                Text(isFree
                     ? "Táto špacírka je zadarmo — stačí sa prihlásiť."
                     : "Zakúpené špacírky sa ti po prihlásení odomknú. Ak ju ešte nemáš, budeš si ju môcť kúpiť.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textMedium)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        } else if game.status == .purchasable {
            Button(action: onPurchase) {
                Group {
                    if isPurchasing {
                        ProgressView().tint(AppColor.primaryButtonText)
                    } else if let price {
                        Text("Kúpiť špacírku · \(price)")
                    } else {
                        Text("Kúpiť špacírku")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColor.primaryButtonText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AppColor.purchaseButton, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
        } else {
            Text(game.status == .comingSoon ? "Čoskoro k dispozícii" : "Táto špacírka nie je dostupná.")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.textMedium.opacity(0.7))
                .frame(maxWidth: .infinity)
        }
    }

    private func filledButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColor.primaryButtonText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(color, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
