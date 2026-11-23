import SwiftUI

/// Prihlásenie, registrácia a obnova hesla e-mailom. Ekvivalent android `AuthBottomSheet`
/// (Google Sign-In pribudne s balíkom `GoogleSignIn` — viď README).
///
/// Keď je zadaný `consent` (špacírka so súhlasom, napr. súťaž), hárok ukáže aj podmienky
/// s políčkom na súhlas — prihlásenie a súhlas sú tak pre hráča jeden krok. Prihlásiť sa dá
/// až po zaškrtnutí; súhlas zapíše volajúci po úspešnom prihlásení.
struct AuthSheet: View {
    var auth: AuthViewModel
    var consent: GameConsent?
    let onSignedIn: () -> Void

    private enum Mode { case login, register, reset }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var marketingOptIn = false
    @State private var consentChecked = false
    @State private var localError: String?

    private var title: String {
        switch mode {
        case .register: return "Registrácia"
        case .reset: return "Obnova hesla"
        case .login: return consent.map { $0.title ?? "Podmienky účasti" } ?? "Prihlásenie"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.textOnBeige)
                    .multilineTextAlignment(.center)

                if let consent, mode != .reset {
                    consentBlock(consent)
                }

                if mode == .reset {
                    Text("Zadaj svoj email a pošleme ti odkaz na nastavenie nového hesla.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textOnBeigeSecondary)
                        .multilineTextAlignment(.center)
                } else if consent == nil {
                    Text("Prihlásením sa ti odomknú zakúpené špacírky aj na ďalšom zariadení.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textOnBeigeSecondary)
                        .multilineTextAlignment(.center)
                }

                form
                messages
                primaryButton
                modeLinks
                legalNotice.padding(.top, 8)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColor.cardBg)
        // Bez toho by pozadie prišlo zo systémovej témy (tmavý režim) a tmavé texty by zmizli.
        .environment(\.colorScheme, .light)
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if loggedIn { onSignedIn() }
        }
    }

    // MARK: - Časti

    @ViewBuilder private var form: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            if mode != .reset {
                SecureField("Heslo", text: $password)
                    .textContentType(mode == .register ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: password) { _, _ in localError = nil }
            }
            if mode == .register {
                SecureField("Zopakuj heslo", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: confirmPassword) { _, _ in localError = nil }
                Toggle(isOn: $marketingOptIn) {
                    Text("Chcem dostávať novinky a akcie e-mailom (nepovinné)")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textOnBeigeSecondary)
                }
                .toggleStyle(CheckboxToggleStyle())
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var messages: some View {
        if let error = localError ?? auth.errorMessage {
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(Color(rgb: 0xC62828))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        if let info = auth.infoMessage {
            Text(info)
                .font(.system(size: 13))
                .foregroundStyle(Color(rgb: 0x2E7D32))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var primaryButton: some View {
        Button(action: submit) {
            Group {
                if auth.isAuthenticating {
                    ProgressView().tint(AppColor.primaryButtonText)
                } else {
                    Text(primaryTitle).font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(AppColor.primaryButtonText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(AppColor.primaryButton, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(auth.isAuthenticating)
        .padding(.top, 8)
    }

    private var primaryTitle: String {
        switch mode {
        case .login: return "Prihlásiť sa"
        case .register: return "Zaregistrovať sa"
        case .reset: return "Poslať email na obnovu"
        }
    }

    @ViewBuilder private var modeLinks: some View {
        switch mode {
        case .login:
            Button("Zabudnuté heslo?") { switchMode(.reset) }
                .font(.system(size: 14))
                .tint(AppColor.textOnBeigeSecondary)
            Button("Nemáš účet? Zaregistruj sa") { switchMode(.register) }
                .font(.system(size: 14, weight: .semibold))
                .tint(AppColor.amber)
        case .register:
            Button("Máš už účet? Prihlás sa") { switchMode(.login) }
                .font(.system(size: 14, weight: .semibold))
                .tint(AppColor.amber)
        case .reset:
            Button("Späť na prihlásenie") { switchMode(.login) }
                .font(.system(size: 14))
                .tint(AppColor.textOnBeigeSecondary)
        }
    }

    /// Podmienky špacírky: krátke zhrnutie (pri dlhom texte sa posúva), organizátor a políčko
    /// na súhlas s odkazom na celé podmienky.
    @ViewBuilder private func consentBlock(_ consent: GameConsent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = consent.summary {
                ScrollView {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textOnBeige)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            if let organizer = consent.organizer {
                Text("Organizátor: \(organizer)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textOnBeigeSecondary)
            }
            Toggle(isOn: $consentChecked) {
                Text("Súhlasím s podmienkami")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textOnBeige)
            }
            .toggleStyle(CheckboxToggleStyle())
            .onChange(of: consentChecked) { _, _ in localError = nil }
            if let urlString = consent.url, let url = URL(string: urlString) {
                Link("Prečítať celé podmienky", destination: url)
                    .font(.system(size: 13))
                    .underline()
                    .tint(AppColor.amber)
            }
        }
    }

    /// Používaním appky hráč súhlasí s podmienkami — s odkazmi na právne stránky.
    private var legalNotice: some View {
        Text(LocalizedStringKey("Pokračovaním súhlasíš s [Obchodnými podmienkami](https://spacirkovnik.sk/obchodne-podmienky/) a berieš na vedomie [Zásady ochrany osobných údajov](https://spacirkovnik.sk/zasady-ochrany-osobnych-udajov/)."))
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textOnBeigeSecondary)
            .tint(AppColor.amber)
            .multilineTextAlignment(.center)
    }

    // MARK: - Akcie

    private func switchMode(_ target: Mode) {
        mode = target
        confirmPassword = ""
        localError = nil
        auth.clearError()
    }

    private func submit() {
        switch mode {
        case .login:
            guard consentOK() else { return }
            Task { await auth.signIn(email: email, password: password) }
        case .register:
            guard password == confirmPassword else {
                localError = "Heslá sa nezhodujú."
                return
            }
            guard consentOK() else { return }
            Task { await auth.signUp(email: email, password: password, marketingOptIn: marketingOptIn) }
        case .reset:
            Task { await auth.sendPasswordReset(email: email) }
        }
    }

    /// Pri špacírke so súhlasom pustí prihlásenie ďalej, len keď je políčko zaškrtnuté.
    private func consentOK() -> Bool {
        if consent != nil && !consentChecked {
            localError = "Najprv zaškrtni súhlas s podmienkami."
            return false
        }
        return true
    }
}

/// Zaškrtávacie políčko (iOS má predvolene len prepínač).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 22))
                .foregroundStyle(configuration.isOn ? AppColor.primaryButton : AppColor.textOnBeigeSecondary)
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

/// Účet prihláseného hráča — e-mail, súhlas s novinkami, právne odkazy, verzia a odhlásenie.
/// Ekvivalent android `AccountDialog`.
struct AccountSheet: View {
    var auth: AuthViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Účet")
                    .font(.title2.bold())
                    .foregroundStyle(AppColor.textDark)
                if let email = auth.user?.email {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textMedium)
                }

                Toggle(isOn: Binding(
                    get: { auth.marketingConsent },
                    set: { auth.setMarketingConsent($0) }
                )) {
                    Text("Dostávať novinky a akcie e-mailom")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.textDark)
                }
                .tint(AppColor.primaryButton)

                VStack(alignment: .leading, spacing: 8) {
                    Link("Obchodné podmienky", destination: URL(string: "https://spacirkovnik.sk/obchodne-podmienky/")!)
                    Link("Zásady ochrany osobných údajov",
                         destination: URL(string: "https://spacirkovnik.sk/zasady-ochrany-osobnych-udajov/")!)
                }
                .font(.system(size: 13))
                .underline()
                .tint(AppColor.amber)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.versionLabel)
                    Text("Príbehy a ilustrácie vznikajú s pomocou umelej inteligencie, trasy overujeme v teréne.")
                }
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textMedium.opacity(0.7))

                HStack {
                    Button("Zavrieť") { dismiss() }
                        .tint(AppColor.textMedium)
                    Spacer()
                    Button("Odhlásiť sa") {
                        auth.signOut()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(AppColor.primaryButton)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.cardBg)
        .environment(\.colorScheme, .light)
    }

    /// „Verzia 1.0.0 (3)"; vo vývojovom builde s dovetkom „· vývojová".
    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if DEBUG
        return "Verzia \(version) (\(build)) · vývojová"
        #else
        return "Verzia \(version) (\(build))"
        #endif
    }
}
