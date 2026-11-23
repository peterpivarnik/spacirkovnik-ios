import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

/// Zapíše dohranie špacírky do `completions/{uid}/{gameId}/<push id> = čas v ms`.
/// Ekvivalent android `GameCompletionManager`. Bez prihlásenia alebo bez Firebase nerobí nič.
enum GameCompletionRecorder {
    static func recordCompletion(gameId: String) {
        guard FirebaseApp.app() != nil, let uid = Auth.auth().currentUser?.uid else { return }
        Database.database().reference()
            .child("completions").child(uid).child(gameId)
            .childByAutoId()
            .setValue(Int(Date().timeIntervalSince1970 * 1000))
    }
}
