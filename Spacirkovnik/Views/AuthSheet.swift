import SwiftUI

/// Prihlásenie / registrácia e-mailom. Ekvivalent android `AuthBottomSheet`
/// (Google Sign-In pribudne s balíkom `GoogleSignIn` — viď README).
struct AuthSheet: View {
    var auth: AuthViewModel
    let onSignedIn: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isRegistering ? "Vytvor si účet" : "Prihlás sa")
                .font(.title2.bold())
                .foregroundStyle(AppColor.textDark)
            Text("Prihlásením sa ti odomknú zakúpené špacírky aj na ďalšom zariadení.")
                .font(.footnote)
                .foregroundStyle(AppColor.textMedium)

            TextField("E-mail", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Heslo", text: $password)
                .textContentType(isRegistering ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    if isRegistering {
                        await auth.signUp(email: email, password: password)
                    } else {
                        await auth.signIn(email: email, password: password)
                    }
                    if auth.isLoggedIn { onSignedIn() }
                }
            } label: {
                Group {
                    if auth.isAuthenticating {
                        ProgressView().tint(AppColor.primaryButtonText)
                    } else {
                        Text(isRegistering ? "Zaregistrovať sa" : "Prihlásiť sa").fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.primaryButton)
            .disabled(email.isEmpty || password.isEmpty || auth.isAuthenticating)

            Button(isRegistering ? "Už mám účet — prihlásiť sa" : "Nemám účet — zaregistrovať sa") {
                auth.clearError()
                isRegistering.toggle()
            }
            .font(.footnote)
            .tint(AppColor.primaryButton)

            Button("Zavrieť") { dismiss() }
                .font(.footnote)
                .tint(AppColor.textMedium)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.cardBg)
        // Bez toho by pozadie prišlo zo systémovej témy (tmavý režim) a tmavé texty by zmizli.
        .environment(\.colorScheme, .light)
    }
}

/// Účet prihláseného hráča — e-mail a odhlásenie. Ekvivalent android dialógu „Účet".
struct AccountSheet: View {
    var auth: AuthViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Účet")
                .font(.title2.bold())
                .foregroundStyle(AppColor.textDark)
            if let email = auth.user?.email {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textMedium)
            }

            Button("Odhlásiť sa") {
                auth.signOut()
                dismiss()
            }
            .fontWeight(.semibold)
            .tint(AppColor.primaryButton)

            Button("Zavrieť") { dismiss() }
                .tint(AppColor.textMedium)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.cardBg)
        .environment(\.colorScheme, .light)
    }
}
