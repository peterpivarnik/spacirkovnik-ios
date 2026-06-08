import Foundation
import Observation
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

    /// ID hier aktivovaných pre prihláseného používateľa (`activations/{uid}/{gameId} == true`).
    var activatedGameIds: Set<String> = []

    private var dbRef: DatabaseReference { Database.database().reference() }

    init() {
        user = Auth.auth().currentUser
    }

    var isLoggedIn: Bool { user != nil }

    func signIn(email: String, password: String) async {
        isAuthenticating = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            user = result.user
            await loadActivations()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    func signUp(email: String, password: String) async {
        isAuthenticating = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            user = result.user
        } catch {
            errorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    func signOut() {
        try? Auth.auth().signOut()
        user = nil
        activatedGameIds = []
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
}
