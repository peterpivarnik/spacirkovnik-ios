import SwiftUI

/// Žiadosť o súhlas pred špacírkou a čo urobiť, keď ho hráč dá.
private struct ConsentRequest: Identifiable {
    enum Action {
        /// Spustiť špacírku (`fresh` = od začiatku, so zmazaným postupom).
        case start(fresh: Bool)
        /// Nič nespúšťať — hráč sa len prihlasoval z karty.
        case signInOnly
    }

    let game: GameInfo
    let action: Action
    var id: String { game.id }
}

/// Zoznam dostupných špacírok z katalógu. Ekvivalent android `GameListScreen` — vrátane
/// vzhľadu: béžové pozadie, vlastná hlavička s logom a krémové karty s rozbaľovaním.
///
/// Zamknutá karta povie, čo treba na jej odomknutie (prihlásenie alebo kúpa). Odomknuté
/// špacírky sa samé stiahnu do telefónu, aby sa dali hrať aj bez signálu; bez pripojenia
/// sa ukáže uložený zoznam (offline režim).
struct GameListView: View {
    var viewModel: GameListViewModel
    var auth: AuthViewModel
    var purchases: PurchaseManager
    @Binding var path: [GameInfo]

    private let progressStore = GameProgressStore.shared

    @State private var expandedGameId: String?
    @State private var showAuthSheet = false
    @State private var showAccountSheet = false
    /// Špacírka, ktorú chcel hráč odomknúť prihlásením — po prihlásení jej kartu rozbalíme,
    /// nech sa k nej nemusí preklikávať späť (android `pendingUnlockGameId`).
    @State private var pendingUnlockGameId: String?
    /// Špacírka so súhlasom, kvôli ktorej sa hráč práve prihlasuje: hárok ukáže aj podmienky
    /// a po prihlásení súhlas zapíšeme — prihlásenie a súhlas sú pre hráča jeden krok.
    @State private var signInConsent: ConsentRequest?
    @State private var consentRequest: ConsentRequest?
    @State private var isSavingConsent = false
    @State private var consentError: String?
    @State private var marketingPromptDismissed = false
    @State private var toast: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.mainBackground.ignoresSafeArea()
            content.padding(16)
            if let toast { toastView(toast) }
        }
        // Hlavičku si kreslíme sami (logo + podtitul + účet), systémový title by ju zdvojil.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAuthSheet, onDismiss: {
            // Zavreté bez prihlásenia — nemáme na čo nadväzovať.
            if !auth.isLoggedIn {
                pendingUnlockGameId = nil
                signInConsent = nil
            }
        }) {
            AuthSheet(auth: auth, consent: signInConsent?.game.consent, onSignedIn: { showAuthSheet = false })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountSheet(auth: auth)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $consentRequest) { request in
            if let consent = request.game.consent {
                GameConsentSheet(
                    consent: consent,
                    isSaving: isSavingConsent,
                    errorMessage: consentError,
                    onAccept: { accept(consent, for: request) },
                    onDecline: { decline(consent, for: request) }
                )
                .presentationDetents([.medium, .large])
            }
        }
        // Na novinky sa pýtame až hráča, ktorý už dohral špacírku — vtedy otázka dáva zmysel;
        // hneď po prihlásení by len prekážala ceste k hre.
        .alert("Novinky a akcie", isPresented: marketingPromptBinding) {
            Button("Áno, chcem") {
                auth.setMarketingConsent(true)
                marketingPromptDismissed = true
            }
            Button("Nie, ďakujem", role: .cancel) {
                auth.setMarketingConsent(false)
                marketingPromptDismissed = true
            }
        } message: {
            Text("Chceš dostávať e-maily o nových špacírkach a akciách? Súhlas môžeš kedykoľvek odvolať v nastaveniach účtu.")
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            // Po prihlásení/odhlásení sa zoznam obnoví (iné hry, iné odomknutia).
            Task { await viewModel.loadGames() }
            guard loggedIn else { return }
            showAuthSheet = false
            recordSignInConsent()
        }
        .onChange(of: auth.testGameIds, initial: true) { _, ids in
            viewModel.setTestGames(ids)
        }
        // Po prihlásení sa vráť k špacírke, kvôli ktorej hráč prihlásenie otvoril. Čakáme
        // na dotiahnuté aktivácie, inak by sa karta rozbalila ešte v zamknutom stave.
        .onChange(of: accountReady) { _, ready in
            guard ready, let gameId = pendingUnlockGameId,
                  viewModel.games.contains(where: { $0.id == gameId }) else { return }
            pendingUnlockGameId = nil
            expandedGameId = gameId
        }
        .onChange(of: viewModel.downloadError) { _, error in
            guard let error else { return }
            viewModel.downloadError = nil
            showToast(error)
        }
        .onChange(of: purchases.errorMessage) { _, error in
            guard let error else { return }
            purchases.errorMessage = nil
            showToast(error)
        }
    }

    // MARK: - Obsah

    @ViewBuilder private var content: some View {
        VStack(spacing: 8) {
            header
            if viewModel.isLoading || (auth.isLoggedIn && auth.isLoadingAccount) {
                Spacer()
                ProgressView().tint(AppColor.amber)
                Spacer()
            } else if let error = viewModel.errorMessage, viewModel.games.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(AppColor.textOnBeigeSecondary)
                        .multilineTextAlignment(.center)
                    Button("Skúsiť znova") { Task { await viewModel.loadGames() } }
                        .fontWeight(.semibold)
                        .tint(AppColor.primaryButton)
                }
                Spacer()
            } else {
                if viewModel.isOffline { offlineBanner }
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

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 12))
            Text("Offline režim — zobrazujú sa uložené špacírky")
                .font(.system(size: 12))
            Spacer()
        }
        .foregroundStyle(AppColor.textOnBeigeSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColor.textMedium.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Bez prihlásenia nie je z ničoho zrejmé, že ostatné špacírky sa dajú získať —
    /// pruh to povie skôr, než hráč začne klikať po kartách.
    private var signInBanner: some View {
        Button {
            openSignIn()
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
                ForEach(viewModel.games) { item in
                    let game = item.info
                    GameCard(
                        item: item,
                        access: access(for: game),
                        isExpanded: expandedGameId == game.id,
                        price: purchases.price(for: productId(of: game)),
                        isPurchasing: purchases.purchasingProductId == productId(of: game),
                        hasSavedProgress: progressStore.hasProgress(gameId: game.id),
                        isCompleted: progressStore.isCompleted(gameId: game.id),
                        onToggle: { toggle(game) },
                        onPlay: { gatedStart(game, fresh: false) },
                        onPlayFresh: { gatedStart(game, fresh: true) },
                        onDownload: { Task { await viewModel.downloadGame(id: game.id) } },
                        onSignIn: {
                            pendingUnlockGameId = game.id
                            signInConsent = needsRequiredConsent(game) ? ConsentRequest(game: game, action: .signInOnly) : nil
                            openSignIn(keepConsent: true)
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
            .accessibilityLabel("Účet")
        } else {
            Button {
                openSignIn()
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

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { withAnimation { toast = nil } }
    }

    // MARK: - Logika

    private var accountReady: Bool { auth.isLoggedIn && !auth.isLoadingAccount }

    private var marketingPromptBinding: Binding<Bool> {
        Binding(
            get: {
                auth.isLoggedIn
                    && auth.shouldAskMarketingConsent
                    && !marketingPromptDismissed
                    && !showAuthSheet && !showAccountSheet && consentRequest == nil
                    && viewModel.games.contains { progressStore.isCompleted(gameId: $0.id) }
            },
            set: { if !$0 { marketingPromptDismissed = true } }
        )
    }

    private func access(for game: GameInfo) -> GameAccess {
        GameAccess.resolve(
            status: game.status,
            isSignedIn: auth.isLoggedIn,
            isActivated: auth.activatedGameIds.contains(game.id)
                || purchases.purchasedProductIds.contains(productId(of: game)),
            isTestGame: viewModel.isTestGame(game.id)
        )
    }

    private func productId(of game: GameInfo) -> String {
        game.googlePlayProductId ?? game.id
    }

    private func toggle(_ game: GameInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedGameId = expandedGameId == game.id ? nil : game.id
        }
    }

    private func openSignIn(keepConsent: Bool = false) {
        if !keepConsent { signInConsent = nil }
        auth.clearError()
        showAuthSheet = true
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    /// Treba sa hráča pred špacírkou opýtať na súhlas? Nie, ak ho už dal (vo Firebase alebo
    /// na tomto zariadení), alebo ak je súhlas nepovinný a hráč ho tu už odmietol.
    private func needsConsent(_ game: GameInfo) -> Bool {
        guard let consent = game.consent else { return false }
        let accepted = auth.hasConsent(gameId: game.id, version: consent.version)
            || ConsentStore.shared.acceptedVersion(gameId: game.id) >= consent.version
        if accepted { return false }
        if !consent.required && ConsentStore.shared.declinedVersion(gameId: game.id) >= consent.version {
            return false
        }
        return true
    }

    private func needsRequiredConsent(_ game: GameInfo) -> Bool {
        needsConsent(game) && game.consent?.required == true
    }

    /// Spustí špacírku — ak treba, najprv cez súhlas (a pri povinnom súhlase aj prihlásenie).
    private func gatedStart(_ game: GameInfo, fresh: Bool) {
        let request = ConsentRequest(game: game, action: .start(fresh: fresh))
        guard needsConsent(game), let consent = game.consent else {
            perform(request)
            return
        }
        guard auth.isLoggedIn else {
            if consent.required {
                // Prihlásenie aj súhlas v jednom hárku; po nich sa špacírka spustí.
                signInConsent = request
                openSignIn(keepConsent: true)
            } else {
                // Nepovinný súhlas bez účtu nemáme kam zapísať — hrá sa bez neho.
                perform(request)
            }
            return
        }
        consentError = nil
        consentRequest = request
    }

    private func perform(_ request: ConsentRequest) {
        guard case .start(let fresh) = request.action else { return }
        if fresh {
            progressStore.clearProgress(gameId: request.game.id)
            progressStore.clearCompleted(gameId: request.game.id)
        }
        path.append(request.game)
    }

    /// Súhlas zaškrtnutý v prihlasovacom hárku zapíšeme až teraz, keď poznáme účet.
    /// Ak sa zápis nepodarí, súhlas sa hráča opýta znova pri štarte špacírky.
    private func recordSignInConsent() {
        guard let request = signInConsent, let consent = request.game.consent else { return }
        signInConsent = nil
        Task {
            if await auth.recordConsent(gameId: request.game.id, version: consent.version) {
                ConsentStore.shared.setAccepted(gameId: request.game.id, version: consent.version)
                perform(request)
            }
        }
    }

    private func accept(_ consent: GameConsent, for request: ConsentRequest) {
        isSavingConsent = true
        consentError = nil
        Task {
            let saved = await auth.recordConsent(gameId: request.game.id, version: consent.version)
            isSavingConsent = false
            if saved {
                ConsentStore.shared.setAccepted(gameId: request.game.id, version: consent.version)
                consentRequest = nil
                perform(request)
            } else {
                // Hárok necháme otvorený, nech to hráč vie skúsiť znova.
                consentError = "Súhlas sa nepodarilo uložiť. Skontroluj pripojenie a skús to znova."
            }
        }
    }

    private func decline(_ consent: GameConsent, for request: ConsentRequest) {
        consentRequest = nil
        // Nepovinný súhlas: odmietnutie si zapamätáme a špacírka sa spustí aj tak.
        guard !consent.required else { return }
        ConsentStore.shared.setDeclined(gameId: request.game.id, version: consent.version)
        perform(request)
    }
}

/// Karta jednej špacírky — zbalený riadok (obrázok, názov, stav) a po ťuknutí detail
/// s popisom, parametrami trasy a akciou. Čo ukáže, určuje `access` — sama o odomknutí
/// nerozhoduje. Ekvivalent android `GameCard`.
private struct GameCard: View {
    let item: GameWithStatus
    let access: GameAccess
    let isExpanded: Bool
    let price: String?
    let isPurchasing: Bool
    let hasSavedProgress: Bool
    let isCompleted: Bool
    let onToggle: () -> Void
    let onPlay: () -> Void
    let onPlayFresh: () -> Void
    let onDownload: () -> Void
    let onSignIn: () -> Void
    let onPurchase: () -> Void

    /// Odomknuté špacírky sa sťahujú samé; keď to zlyhá (offline), karta ponúkne „Skúsiť znova".
    @State private var autoDownloadTried = false

    private var game: GameInfo { item.info }

    /// Stmavenie je hlavný signál „túto špacírku ešte nemáš" — drží sa obsahu karty
    /// (obrázok, názov, popis). Prvky, ktoré nesú ponuku (cena, košík, štítok ZADARMO,
    /// tlačidlá), ostávajú v plnej sýtosti, nech je vidieť, čo sa s tým dá spraviť.
    private var dim: Double { access.isUnlocked ? 1 : 0.5 }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) { collapsedRow }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gameCard")

            if isExpanded { expandedDetail }
        }
        .background(AppColor.cardBg.opacity(access.isUnlocked ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if !access.isUnlocked {
                // „Ide sa získať hneď" — kúpou alebo prihlásením; podčiarkne to jantárový rám.
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        access.isOffer ? AppColor.amber.opacity(0.45) : AppColor.textMedium.opacity(0.2),
                        lineWidth: 1
                    )
            }
        }
        .task(id: access.isUnlocked) {
            // Stiahnutie je len malý JSON (obrázky idú na pozadí), takže hráč vidí rovno „Prejsť".
            guard access.isUnlocked, item.status == .notDownloaded, !autoDownloadTried else { return }
            autoDownloadTried = true
            onDownload()
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
        CachedImage(urlString: game.imageUrl) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            thumbnailPlaceholder
        } failure: {
            thumbnailPlaceholder
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            AppColor.amber.opacity(0.2)
            Image(systemName: "figure.walk")
                .foregroundStyle(AppColor.amber)
        }
    }

    /// Zbalený riadok má sám povedať, čo by odomknutie špacírky stálo: cena + košík pri kúpe,
    /// štítok ZADARMO po prihlásení, hodiny pri pripravovanej, inak zámok. Odomknutá špacírka
    /// ukazuje šípku rozbalenia.
    @ViewBuilder private var statusIndicator: some View {
        switch access {
        case .buy, .signInToBuy:
            HStack(spacing: 6) {
                // Ceny sa sťahujú až po prihlásení, takže pri signInToBuy cena nie je.
                if access == .buy, let price {
                    Text(price).font(.system(size: 13, weight: .semibold))
                }
                Image(systemName: "cart").font(.system(size: 16))
            }
            .foregroundStyle(AppColor.amber)
        case .freeAfterSignIn:
            Text("ZADARMO")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColor.purchaseButton)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppColor.purchaseButton.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        case .comingSoon:
            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.textMedium)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.textMedium)
        case .unlocked:
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
                    CachedImage(urlString: urlString) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        AppColor.amber.opacity(0.15)
                    } failure: {
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
        switch access {
        case .freeAfterSignIn, .signInToBuy:
            // Bez tohto bloku bola rozbalená karta pre neprihláseného prázdna — nedozvedel
            // sa, že špacírku odomkne prihlásenie.
            let isFree = access == .freeAfterSignIn
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
        case .buy:
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
        case .comingSoon, .locked:
            Text("Čoskoro k dispozícii")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.textMedium.opacity(0.7))
                .frame(maxWidth: .infinity)
        case .unlocked:
            playActions
        }
    }

    @ViewBuilder private var playActions: some View {
        switch item.status {
        case .notDownloaded where autoDownloadTried:
            // Automatické stiahnutie zlyhalo (napr. offline) — nech to hráč skúsi znova.
            filledButton("Skúsiť znova", color: AppColor.primaryButton, action: onDownload)
        case .notDownloaded, .downloading:
            HStack(spacing: 8) {
                ProgressView().tint(AppColor.textMedium)
                Text("Sťahujem...")
            }
            .font(.system(size: 16))
            .foregroundStyle(AppColor.textMedium)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppColor.textMedium.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        case .downloaded where isCompleted:
            filledButton("Prejsť znova", color: AppColor.primaryButton, action: onPlayFresh)
                .accessibilityIdentifier("playButton")
        case .downloaded where hasSavedProgress:
            VStack(spacing: 8) {
                filledButton("Pokračovať", color: AppColor.primaryButton, action: onPlay)
                    .accessibilityIdentifier("playButton")
                Button(action: onPlayFresh) {
                    Text("Prejsť od začiatku")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.secondaryOutlineButton)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColor.secondaryOutlineButton, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playFreshButton")
            }
        case .downloaded, .updateAvailable:
            // Pri dostupnej aktualizácii sa hrá stará verzia, kým sa nová stiahne na pozadí.
            filledButton("Prejsť", color: AppColor.primaryButton, action: onPlay)
                .accessibilityIdentifier("playButton")
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
