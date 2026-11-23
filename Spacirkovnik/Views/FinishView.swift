import SwiftUI

/// Záverečná obrazovka po dohraní špacírky: úvodný obrázok špacírky s pohárom, pochvala, čo všetko
/// hráči zvládli, a malé logo ako podpis (keď si to niekto odfotí a pošle ďalej).
/// Ekvivalent android `FinishScreen`.
struct FinishView: View {
    let summary: FinishSummary
    let onDone: () -> Void

    /// Pohár „vyskočí" — krátka pružná animácia pri otvorení.
    @State private var trophyScale: CGFloat = 0.3

    /// O koľko pohár prečnieva pod obrázok (polovica priemeru krúžku).
    private let trophyOverlap: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 16)
                header
                Spacer().frame(height: 12)
                Text("Dokázali ste to!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColor.textOnDark)
                    .multilineTextAlignment(.center)
                if !summary.title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Špacírka „\(summary.title)“ je za vami.")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColor.textOnDark.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }

                stats.padding(.top, 28)

                Button(action: onDone) {
                    Text("Späť na zoznam špacírok")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.primaryButtonText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(AppColor.primaryButton, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("finishButton")
                .padding(.top, 36)

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .opacity(0.9)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                    .accessibilityLabel("Špacírkovník")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { trophyScale = 1 }
        }
    }

    @ViewBuilder private var header: some View {
        if let urlString = summary.imageUrl {
            // Obrázok špacírky a pohár v krúžku prekrývajúci jeho spodný okraj.
            ZStack(alignment: .bottom) {
                CachedImage(urlString: urlString) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    AppColor.amber.opacity(0.15)
                } failure: {
                    AppColor.amber.opacity(0.15)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, trophyOverlap)

                Text("🏆")
                    .font(.system(size: 52))
                    .frame(width: trophyOverlap * 2, height: trophyOverlap * 2)
                    .background(AppColor.cardBg, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .scaleEffect(trophyScale)
            }
        } else {
            Text("🏆")
                .font(.system(size: 96))
                .scaleEffect(trophyScale)
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            if summary.stops > 0 {
                StatCard(
                    value: "\(summary.stops)",
                    label: slovakPlural(summary.stops, one: "zastávka", few: "zastávky", many: "zastávok")
                )
            }
            if summary.questions > 0 {
                StatCard(
                    value: "\(summary.questions)",
                    label: slovakPlural(
                        summary.questions,
                        one: "vyriešená úloha", few: "vyriešené úlohy", many: "vyriešených úloh"
                    )
                )
            }
            if let minutes = summary.durationMinutes {
                StatCard(value: formatDuration(minutes: minutes), label: "na ceste")
            }
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColor.textDark)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textMedium)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .background(AppColor.cardBg, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }
}
