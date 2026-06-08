import SwiftUI

/// Zoznam dostupných hier z katalógu. Ekvivalent android `GameListScreen`.
struct GameListView: View {
    @Bindable var viewModel: GameListViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.games.isEmpty {
                ProgressView("Načítavam hry…")
            } else if let error = viewModel.errorMessage, viewModel.games.isEmpty {
                ContentUnavailableView("Chyba", systemImage: "wifi.slash", description: Text(error))
            } else {
                List(viewModel.visibleGames) { game in
                    if viewModel.isUnlocked(game) {
                        NavigationLink(value: game) {
                            GameRow(game: game, unlocked: true)
                        }
                    } else {
                        GameRow(game: game, unlocked: false)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await viewModel.loadGames() }
            }
        }
    }
}

private struct GameRow: View {
    let game: GameInfo
    let unlocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: game.imageUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color(hex: game.colorHex) ?? .gray.opacity(0.3))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title).font(.headline)
                Text(game.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let region = game.region {
                        Label(region, systemImage: "mappin.and.ellipse")
                    }
                    if let mins = game.estimatedDurationMinutes {
                        Label("\(mins) min", systemImage: "clock")
                    }
                    if let km = game.distanceKm {
                        Label(String(format: "%.1f km", km), systemImage: "figure.walk")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                statusBadge
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusBadge: some View {
        switch game.status {
        case .comingSoon:
            Text("Už čoskoro").font(.caption2).foregroundStyle(.orange)
        case .purchasable where !unlocked:
            Text("Na kúpu").font(.caption2).foregroundStyle(.blue)
        case .active:
            Text("Zadarmo").font(.caption2).foregroundStyle(.green)
        default:
            EmptyView()
        }
    }
}
