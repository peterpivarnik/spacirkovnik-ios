import SwiftUI

/// Výber rodu na začiatku každej špacírky — texty hry sa podľa neho skloňujú
/// (`{mužský|ženský}`). Ekvivalent android `GenderSelectionScreen`.
struct GenderSelectionView: View {
    let colorHex: String?
    let onSelected: (Gender) -> Void

    var body: some View {
        ZStack {
            AppColor.gameGradient(colorHex: colorHex).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Kto sa vydáva na dobrodružstvo?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.textOnDark)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 32)
                choiceButton(.male, label: "🧒 Chlapec")
                Spacer().frame(height: 16)
                choiceButton(.female, label: "👧 Dievča")
            }
            .padding(.horizontal, 32)
        }
    }

    private func choiceButton(_ gender: Gender, label: String) -> some View {
        Button { onSelected(gender) } label: {
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.primaryButtonText)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(AppColor.primaryButton, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("genderButton")
    }
}
