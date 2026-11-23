import Foundation
import Observation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

/// Prihlásenie (Firebase Auth) a čítanie aktivácií, testovacích hier, súhlasov a súhlasu
/// s novinkami z Realtime Database. Ekvivalent android `AuthViewModel`. Rovnaký Firebase projekt
/// ako Android verzia — stačí pridať `GoogleService-Info.plist` (iOS app `sk.spacirkovnik`).
///
/// TODO (na Macu): Google Sign-In cez `GoogleSignIn` SPM balík + linkovanie účtov
/// (email ↔ Google), rovnako ako na Androide.
@MainActor
@Observable
final class AuthViewModel {
    var user: User?
    var isAuthenticating = false
    var errorMessage: String?
    /// Kladná hláška (napr. „poslali sme ti e-mail na obnovu hesla").
    var infoMessage: String?

    /// Aktivácie a súhlasy sa ešte sťahujú — dovtedy nevieme, ktoré špacírky hráč vlastní,
    /// a ukázali by sme mu ich ako zamknuté. Ekvivalent android `AuthState.loading`.
    var isLoadingAccount = false

    /// ID hier aktivovaných pre prihláseného používateľa (`activations/{uid}/{gameId}`).
    private(set) var activatedGameIds: Set<String> = []

    /// Testovacie špacírky (`testGames/{uid}/{gameId} == true`) — vidí aj skryté a má ich odomknuté.
    private(set) var testGameIds: Set<String> = []

    /// Najvyššia prijatá verzia súhlasu pre danú špacírku (`consents/{uid}/{gameId}/version`).
    private(set) var consents: [String: Int] = [:]

    /// Súhlas s novinkami e-mailom (`marketingConsent/{uid}`).
    private(set) var marketingConsent = false
    private(set) var marketingConsentTimestamp: Date?
    private(set) var marketingConsentLoaded = false

    private var dbRef: DatabaseReference { Database.database().reference() }

    /// Firebase je nakonfigurované, len ak je v buildu `GoogleService-Info.plist`. Bez neho
    /// (CI build, čerstvý klon) sa Auth ani databázy nesmieme dotknúť — appka by spadla.
    private var isFirebaseReady: Bool { FirebaseApp.app() != nil }

    init() {
        guard isFirebaseReady else { return }
        user = Auth.auth().currentUser
        if user != nil {
            // Obnovená relácia — dotiahni aktivácie ešte pred prvým vykreslením zoznamu.
            isLoadingAccount = true
            Task { await refreshAccount() }
        }
    }

    var isLoggedIn: Bool { user != nil }

    /// Meno do hlavičky zoznamu — displayName, inak časť e-mailu pred zavináčom.
    var displayName: String? {
        guard let user else { return nil }
        if let name = user.displayName, !name.isEmpty { return name }
        return user.email?.components(separatedBy: "@").first
    }

    var firstName: String? {
        displayName?.components(separatedBy: " ").first
    }

    func clearError() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - E-mail / heslo

    func signIn(email: String, password: String) async {
        guard prepare(email: email, password: password) else { return }
        do {
            let result = try await Auth.auth().signIn(withEmail: email.trimmed, password: password)
            await finishSignIn(result.user)
        } catch {
            errorMessage = Self.message(for: error)
        }
        isAuthenticating = false
    }

    func signUp(email: String, password: String, marketingOptIn: Bool) async {
        guard prepare(email: email, password: password) else { return }
        do {
            let result = try await Auth.auth().createUser(withEmail: email.trimmed, password: password)
            try? await result.user.sendEmailVerification()
            // Rozhodnutie o novinkách (áno/nie) zapíšeme s časom — hráča, ktorý už pri registrácii
            // rozhodol, sa potom nepýtame znova.
            dbRef.child("marketingConsent").child(result.user.uid)
                .setValue(["granted": marketingOptIn, "timestamp": ServerValue.timestamp()] as [String: Any]) { _, _ in }
            await finishSignIn(result.user)
        } catch {
            errorMessage = Self.message(for: error)
        }
        isAuthenticating = false
    }

    func sendPasswordReset(email: String) async {
        guard isFirebaseReady else {
            errorMessage = "Prihlásenie zatiaľ nie je nastavené (chýba GoogleService-Info.plist)."
            return
        }
        guard !email.trimmed.isEmpty else {
            errorMessage = "Zadaj email pre obnovu hesla."
            return
        }
        isAuthenticating = true
        clearError()
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email.trimmed)
            infoMessage = "Odoslali sme ti email na obnovu hesla. Skontroluj aj spam."
        } catch {
            errorMessage = Self.message(for: error)
        }
        isAuthenticating = false
    }

    func signOut() {
        if isFirebaseReady { try? Auth.auth().signOut() }
        user = nil
        activatedGameIds = []
        testGameIds = []
        consents = [:]
        marketingConsent = false
        marketingConsentTimestamp = nil
        marketingConsentLoaded = false
        isLoadingAccount = false
        clearError()
    }

    private func prepare(email: String, password: String) -> Bool {
        guard isFirebaseReady else {
            errorMessage = "Prihlásenie zatiaľ nie je nastavené (chýba GoogleService-Info.plist)."
            return false
        }
        guard !email.trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Vyplň email aj heslo."
            return false
        }
        isAuthenticating = true
        clearError()
        return true
    }

    private func finishSignIn(_ user: User) async {
        self.user = user
        await refreshAccount()
    }

    // MARK: - Účet

    /// Dotiahne všetko, čo o účte potrebuje zoznam špacírok.
    private func refreshAccount() async {
        isLoadingAccount = true
        async let activations: Void = loadActivations()
        async let testGames: Void = loadTestGames()
        async let consentsLoad: Void = loadConsents()
        _ = await (activations, testGames, consentsLoad)
        isLoadingAccount = false
        await loadMarketingConsent()
    }

    /// Načíta `activations/{uid}` — záznam je `true` alebo `{ active, type, note }`.
    func loadActivations() async {
        guard let uid = user?.uid else { return }
        do {
            let snapshot = try await dbRef.child("activations").child(uid).getData()
            var ids: Set<String> = []
            for case let child as DataSnapshot in snapshot.children where isActivationActive(child.value) {
                ids.insert(child.key)
            }
            activatedGameIds = ids
        } catch {
            // Aktivácie ostanú, aké boli — zoznam sa dá aj tak používať.
        }
    }

    private func loadTestGames() async {
        guard let uid = user?.uid else { return }
        guard let snapshot = try? await dbRef.child("testGames").child(uid).getData() else { return }
        var ids: Set<String> = []
        for case let child as DataSnapshot in snapshot.children where (child.value as? Bool) == true {
            ids.insert(child.key)
        }
        testGameIds = ids
    }

    /// Načíta `consents/{uid}` — prijaté verzie per-game súhlasu.
    private func loadConsents() async {
        guard let uid = user?.uid else { return }
        // Pri chybe ostanú súhlasy prázdne — lokálna cache (ConsentStore) stále platí.
        guard let snapshot = try? await dbRef.child("consents").child(uid).getData() else { return }
        var accepted: [String: Int] = [:]
        for case let child as DataSnapshot in snapshot.children {
            if let version = child.childSnapshot(forPath: "version").value as? Int {
                accepted[child.key] = version
            }
        }
        consents = accepted
    }

    private func loadMarketingConsent() async {
        guard let uid = user?.uid else { return }
        do {
            let snapshot = try await dbRef.child("marketingConsent").child(uid).getData()
            marketingConsent = snapshot.childSnapshot(forPath: "granted").value as? Bool ?? false
            if let ms = snapshot.childSnapshot(forPath: "timestamp").value as? Double {
                marketingConsentTimestamp = Date(timeIntervalSince1970: ms / 1000)
            } else {
                marketingConsentTimestamp = nil
            }
        } catch {
            // Offline a pod.: nepýtať sa — tvárime sa, že sme sa práve pýtali (odklad to potlačí).
            marketingConsentTimestamp = Date()
        }
        marketingConsentLoaded = true
    }

    /// Zapne alebo odvolá súhlas s novinkami e-mailom a uloží ho s časom.
    func setMarketingConsent(_ granted: Bool) {
        guard let uid = user?.uid else { return }
        marketingConsent = granted
        marketingConsentTimestamp = Date()
        marketingConsentLoaded = true
        dbRef.child("marketingConsent").child(uid)
            .setValue(["granted": granted, "timestamp": ServerValue.timestamp()] as [String: Any])
    }

    /// Pýtať sa na novinky? Ak hráč ešte nerozhodol (žiadny záznam) alebo odmietol pred viac
    /// než 30 dňami (druhá šanca bez otravovania). Po „Áno" sa už nepýta.
    /// Ekvivalent android `shouldAskMarketingConsent`.
    var shouldAskMarketingConsent: Bool {
        guard marketingConsentLoaded, !marketingConsent else { return false }
        guard let ts = marketingConsentTimestamp else { return true }
        return Date().timeIntervalSince(ts) > 30 * 24 * 60 * 60
    }

    // MARK: - Súhlasy špacírok

    /// Prijal už hráč súhlas pre `gameId` vo verzii `version` alebo novšej?
    func hasConsent(gameId: String, version: Int) -> Bool {
        (consents[gameId] ?? -1) >= version
    }

    /// Zapíše súhlas do Firebase spolu s e-mailom. Vracia `true` až po úspešnom zápise,
    /// takže hru spúšťame (a lokálne cachujeme) len keď je súhlas naozaj uložený.
    @discardableResult
    func recordConsent(gameId: String, version: Int) async -> Bool {
        guard let user else { return false }
        let record: [String: Any] = [
            "version": version,
            "acceptedAt": Int(Date().timeIntervalSince1970 * 1000),
            "email": user.email ?? ""
        ]
        do {
            try await setValue(record, at: dbRef.child("consents").child(user.uid).child(gameId))
            consents[gameId] = version
            return true
        } catch {
            return false
        }
    }

    private func setValue(_ value: Any, at ref: DatabaseReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.setValue(value) { error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Chybové hlášky

    /// Hláška pre používateľa; technický detail ide len do logu.
    private static func message(for error: Error) -> String {
        let ns = error as NSError
        print("AuthVM: prihlásenie zlyhalo: \(ns.domain) \(ns.code): \(ns.localizedDescription)")
        guard ns.domain == "FIRAuthErrorDomain" else { return genericError }
        // Kódy z FirebaseAuth `AuthErrorCode` (číselne, aby nezáviseli od verzie SDK).
        switch ns.code {
        case 17026: // weakPassword
            return "Heslo musí mať aspoň 6 znakov."
        case 17005: // userDisabled
            return "Tento účet je zablokovaný. Ak ide o omyl, napíš nám na info@spacirkovnik.sk."
        case 17011: // userNotFound
            return "Účet s týmto emailom neexistuje. Zaregistruj sa nižšie."
        case 17009, 17004: // wrongPassword, invalidCredential
            return "Nesprávny email alebo heslo. Ak ešte nemáš účet, zaregistruj sa nižšie."
        case 17008: // invalidEmail
            return "Email nemá správny tvar."
        case 17007: // emailAlreadyInUse
            return "Tento email už je zaregistrovaný."
        case 17020: // networkError
            return "Prihlásenie sa nepodarilo. Skontroluj pripojenie na internet."
        case 17010: // tooManyRequests
            return "Priveľa pokusov. Počkaj chvíľu a skús to znova."
        default:
            return genericError
        }
    }

    private static let genericError = "Prihlásenie sa nepodarilo. Skús to znova."
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
