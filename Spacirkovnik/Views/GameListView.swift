import SwiftUI

/// Zoznam dostupných špacírok z katalógu. Ekvivalent android `GameListScreen`.
///
/// Zamknutá špacírka sa dá rozkliknúť a rozbalená karta povie, čo treba na jej odomknutie
/// (prihlásenie alebo kúpa) — bez toho hráč nemal z čoho vedieť, že sa vôbec dá získať.
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
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { accountControl }
            }
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
        if viewModel.isLoading && viewModel.games.isEmpty {
            ProgressView("Načítavam špacírky…")
        } else if let error = viewModel.errorMessage, viewModel.games.isEmpty {
            ContentUnavailableView("Chyba", systemImage: "wifi.slash", description: Text(error))
        } else {
            VStack(spacing: 0) {
                if !auth.isLoggedIn && viewModel.hasUnlockableGames { signInBanner }
                list
            }
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
                Text("Prihlás sa a odomkni ďalšie špacírky")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(AppColor.textOnBeige)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColor.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var list: some View {
        List {
            ForEach(viewModel.visibleGames) { game in
                VStack(alignment: .leading, spacing: 12) {
                    Button { tapped(game) } label: {
                        GameRow(
                            game: game,
                            unlocked: viewModel.isUnlocked(game),
                            isSignedIn: auth.isLoggedIn,
                            price: price(for: game)
                        )
                    }
                    .buttonStyle(.plain)

                    // Ak sa špacírka medzitým odomkla (napr. práve dobehnutou aktiváciou),
                    // rozbalená karta už nemá čo ponúkať — riadok sa rovno dá hrať.
                    if expandedGameId == game.id, !viewModel.isUnlocked(game) {
                        lockedDetail(for: game)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.loadGames() }
    }

    /// Pre neprihláseného je prihlásenie hlavná akcia — nie zašedená ikonka bez popisu,
    /// ale viditeľné tlačidlo.
    @ViewBuilder private var accountControl: some View {
        if auth.isLoadingAccount {
            ProgressView().tint(AppColor.amber)
        } else if auth.isLoggedIn {
            Button { showAccountSheet = true } label: {
                Label(auth.firstName ?? "Účet", systemImage: "person.crop.circle.fill")
            }
            .tint(AppColor.amber)
        } else {
            Button("Prihlásiť") {
                auth.clearError()
                showAuthSheet = true
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(AppColor.primaryButton)
        }
    }

    /// Rozbalená zamknutá karta — čo treba na odomknutie špacírky.
    @ViewBuilder private func lockedDetail(for game: GameInfo) -> some View {
        let productId = game.googlePlayProductId ?? game.id
        VStack(spacing: 8) {
            if game.status == .comingSoon {
                Text("Táto špacírka sa pripravuje, čoskoro ju tu nájdeš.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if !auth.isLoggedIn {
                // Bez tohto bloku bola rozbalená karta pre neprihláseného prázdna — nedozvedel
                // sa, že špacírku odomkne prihlásenie.
                Button {
                    pendingUnlockGameId = game.id
                    auth.clearError()
                    showAuthSheet = true
                } label: {
                    Text(game.status == .freeWithLogin ? "Prihlásiť sa a hrať zadarmo" : "Prihlásiť sa")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primaryButton)

                // Bez prihlásenia nevieme, či špacírku hráč náhodou už nekúpil (nový telefón,
                // reinštalácia), takže tlačidlo nič netvrdí o kúpe a text pokrýva oba prípady.
                Text(game.status == .freeWithLogin
                     ? "Táto špacírka je zadarmo — stačí sa prihlásiť."
                     : "Zakúpené špacírky sa ti po prihlásení odomknú. Ak ju ešte nemáš, budeš si ju môcť kúpiť.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if game.status == .purchasable {
                Button {
                    Task { await purchases.purchase(productId: productId) }
                } label: {
                    Group {
                        if purchases.purchasingProductId == productId {
                            ProgressView().tint(AppColor.primaryButtonText)
                        } else if let price = purchases.price(for: productId) {
                            Text("Kúpiť špacírku · \(price)").fontWeight(.bold)
                        } else {
                            Text("Kúpiť špacírku").fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.purchaseButton)
                .disabled(purchases.purchasingProductId != nil)
            } else {
                Text("Táto špacírka zatiaľ nie je dostupná.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var accountReady: Bool { auth.isLoggedIn && !auth.isLoadingAccount }

    private func price(for game: GameInfo) -> String? {
        purchases.price(for: game.googlePlayProductId ?? game.id)
    }

    private func tapped(_ game: GameInfo) {
        if viewModel.isUnlocked(game) {
            startGame(game)
        } else {
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

private struct GameRow: View {
    let game: GameInfo
    let unlocked: Bool
    let isSignedIn: Bool
    let price: String?

    /// Stmavenie je hlavný signál „túto špacírku ešte nemáš" — drží sa obsahu karty
    /// (obrázok, názov, popis). Prvky, ktoré nesú ponuku (cena, košík, štítok ZADARMO),
    /// ostávajú v plnej sýtosti, nech je vidieť, čo sa s tým dá spraviť.
    private var dim: Double { unlocked ? 1 : 0.5 }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: game.imageUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color(hex: game.colorHex) ?? .gray.opacity(0.3))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(dim)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title).font(.headline)
                Text(game.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let region = game.region {
                        Label(region, systemImage: "mappin.and.ellipse")
                    }
                    if let mins = game.estimatedDurationMinutes {
                        Label("\(mins) min", systemImage: "clock")
                    }
                    if let km = game.distanceKm {
                        Label(String(format: "%.1f km", km), systemImage: "figure.walk")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .opacity(dim)

            Spacer()
            statusBadge
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Zbalený riadok má sám povedať, čo by odomknutie špacírky stálo: cena + košík pri kúpe,
    /// štítok ZADARMO po prihlásení, hodiny pri pripravovanej, inak zámok.
    @ViewBuilder private var statusBadge: some View {
        if unlocked {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            switch game.status {
            case .purchasable:
                HStack(spacing: 6) {
                    // Ceny ukazujeme až prihlásenému hráčovi — dovtedy ich ani nesťahujeme.
                    if isSignedIn, let price {
                        Text(price).font(.caption.weight(.semibold))
                    }
                    Image(systemName: "cart")
                }
                .foregroundStyle(AppColor.amber)
            case .freeWithLogin:
                Text("ZADARMO")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColor.purchaseButton)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        AppColor.purchaseButton.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            case .comingSoon:
                Image(systemName: "clock").foregroundStyle(.secondary)
            default:
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }
}
