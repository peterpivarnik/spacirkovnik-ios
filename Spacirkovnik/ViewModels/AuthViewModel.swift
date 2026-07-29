import Foundation
import Observation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

/// Prihlásenie (Firebase Auth) a čítanie aktivácií/súhlasov z Realtime Database.
/// Ekvivalent android `AuthViewModel`. Rovnaký Firebase projekt ako Android verzia
/// — stačí pridať `GoogleService-Info.plist` (z Firebase konzoly, iOS app `sk.spacirkovnik`).
///
/// TODO (na Macu): Google Sign-In cez `GoogleSignIn` SPM balík + linkovanie účtov
/// (email ↔ Google), rovnako ako na Androide.
@MainActor
@Observable
final class AuthViewModel {
    var user: User?
    var isAuthenticating = false
    var errorMessage: String?

    /// Aktivácie a súhlasy sa ešte sťahujú — dovtedy nevieme, ktoré špacírky hráč vlastní,
    /// a ukázali by sme mu ich ako zamknuté. Ekvivalent android `AuthState.loading`.
    var isLoadingAccount = false

    /// ID hier aktivovaných pre prihláseného používateľa (`activations/{uid}/{gameId} == true`).
    var activatedGameIds: Set<String> = []

    /// Najvyššia prijatá verzia súhlasu pre danú špacírku (`consents/{uid}/{gameId}/version`).
    private(set) var consents: [String: Int] = [:]

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
    }

    func signIn(email: String, password: String) async {
        guard isFirebaseReady else {
            errorMessage = "Prihlásenie zatiaľ nie je nastavené (chýba GoogleService-Info.plist)."
            return
        }
        isAuthenticating = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            user = result.user
            await refreshAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    func signUp(email: String, password: String) async {
        guard isFirebaseReady else {
            errorMessage = "Registrácia zatiaľ nie je nastavená (chýba GoogleService-Info.plist)."
            return
        }
        isAuthenticating = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            user = result.user
            await refreshAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    func signOut() {
        if isFirebaseReady { try? Auth.auth().signOut() }
        user = nil
        activatedGameIds = []
        consents = [:]
        isLoadingAccount = false
    }

    /// Dotiahne všetko, čo o účte potrebuje zoznam špacírok.
    private func refreshAccount() async {
        isLoadingAccount = true
        await loadActivations()
        await loadConsents()
        isLoadingAccount = false
    }

    /// Načíta `activations/{uid}` z Realtime Database.
    func loadActivations() async {
        guard let uid = user?.uid else { return }
        do {
            let snapshot = try await dbRef.child("activations").child(uid).getData()
            var ids: Set<String> = []
            for case let child as DataSnapshot in snapshot.children {
                if let active = child.value as? Bool, active {
                    ids.insert(child.key)
                }
            }
            activatedGameIds = ids
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Načíta `consents/{uid}` — prijaté verzie per-game súhlasu.
    func loadConsents() async {
        guard let uid = user?.uid else { return }
        do {
            let snapshot = try await dbRef.child("consents").child(uid).getData()
            var accepted: [String: Int] = [:]
            for case let child as DataSnapshot in snapshot.children {
                if let version = child.childSnapshot(forPath: "version").value as? Int {
                    accepted[child.key] = version
                }
            }
            consents = accepted
        } catch {
            // Súhlasy ostanú prázdne — lokálna cache (ConsentStore) stále platí.
        }
    }

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
}
