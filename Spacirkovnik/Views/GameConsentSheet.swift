import SwiftUI

/// Súhlas pred špacírkou, ktorá ho vyžaduje (napr. zdieľanie e-mailu s organizátorom).
/// Ekvivalent android `GameConsentDialog`.
///
/// Text scrolluje, tlačidlá zostávajú dole — pri dlhšom znení sa inak tlačidlá vytlačia
/// mimo obrazovky a hráč nemá ako súhlas potvrdiť.
struct GameConsentSheet: View {
    let consent: GameConsent
    let isSaving: Bool
    let errorMessage: String?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(consent.title ?? "Podmienky účasti")
                        .font(.title3.bold())
                        .foregroundStyle(AppColor.textDark)
                    if let summary = consent.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textDark)
                    }
                    if let organizer = consent.organizer {
                        Text("Organizátor: \(organizer)")
                            .font(.footnote)
                            .foregroundStyle(AppColor.textDark.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            // Akcie držíme pokope v spodnej časti hárku.
            VStack(spacing: 8) {
                if let urlString = consent.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text("Prečítať celé podmienky")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColor.primaryButton)
                }
                Button(action: onAccept) {
                    Group {
                        if isSaving {
                            ProgressView().tint(AppColor.primaryButtonText)
                        } else {
                            Text("Súhlasím a pokračovať").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primaryButton)
                .disabled(isSaving)

                Button("Nesúhlasím", action: onDecline)
                    .tint(AppColor.textDark.opacity(0.7))
                    .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.cardBg)
        // Bez toho by pozadie prišlo zo systémovej témy (tmavý režim) a tmavé texty by zmizli.
        .environment(\.colorScheme, .light)
    }
}
