import SwiftUI
import MapKit

/// NAVIGATION obrazovka — mapa s cieľom, vzdialenosť a gating na priblíženie sa.
/// Používa natívny MapKit (bez API kľúča). Mapbox iOS SDK sa dá nasadiť neskôr pre
/// parity s Androidom, ak budú treba pešie trasy (MKDirections .walking je tu zatiaľ
/// pripravený ako jednoduchá alternatíva).
struct NavigationTargetView: View {
    let screen: GameScreen
    let accentColor: Color
    var locationManager: LocationManager
    let onArrived: () -> Void

    private let arrivalRadius: CLLocationDistance = 25

    var body: some View {
        VStack(spacing: 16) {
            if let target = screen.targetCoordinate {
                Map {
                    Annotation("Cieľ", coordinate: target) {
                        Image(systemName: "flag.checkered.circle.fill")
                            .font(.title)
                            .foregroundStyle(accentColor)
                    }
                    UserAnnotation()
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                distanceLabel(to: target)

                if locationManager.isWithin(radius: arrivalRadius, of: target) {
                    Button(action: onArrived) {
                        Text(screen.nextButtonText ?? "Som na mieste!")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                } else {
                    Text("Choď na vyznačené miesto na mape, tlačidlo sa potom odomkne.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Chýba cieľová poloha pre túto obrazovku.")
                    .foregroundStyle(.secondary)
                Button("Ďalej", action: onArrived)
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
            }
        }
    }

    @ViewBuilder private func distanceLabel(to target: CLLocationCoordinate2D) -> some View {
        if let d = locationManager.distance(to: target) {
            Label(d < 1000 ? "\(Int(d)) m od cieľa" : String(format: "%.1f km od cieľa", d / 1000),
                  systemImage: "location.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Label("Hľadám tvoju polohu…", systemImage: "location.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
