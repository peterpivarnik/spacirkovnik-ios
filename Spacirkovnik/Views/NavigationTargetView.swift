import SwiftUI
import MapKit

/// NAVIGATION obrazovka — mapa s cieľom, vzdialenosť a gating na priblíženie sa.
/// Používa natívny MapKit (bez API kľúča) — `MKDirections` s `.walking` je iOS náhrada
/// za Mapbox Directions z android verzie.
///
/// Predvolene sa kreslí skutočná pešia trasa po chodníkoch a vzdialenosť podľa nej.
/// Ak má obrazovka `directRoute: true` (alebo sa trasu nepodarí načítať — offline, cieľ
/// mimo chodníkov), kreslí sa priamka od hráča k cieľu a vzdušná vzdialenosť.
struct NavigationTargetView: View {
    let screen: GameScreen
    let accentColor: Color
    var locationManager: LocationManager
    let onArrived: () -> Void

    private let arrivalRadius: CLLocationDistance = 25
    /// Novú trasu pýtame, až keď hráč prejde aspoň toľko metrov — inak by sme
    /// prepočítavali pri každom tiknutí GPS (rovnaký prah ako na Androide).
    private let rerouteThresholdMeters: CLLocationDistance = 15

    @State private var route: MKRoute?
    @State private var lastRouteFetch: CLLocation?
    /// Cieľ, ku ktorému patrí načítaná trasa — každú navigačnú obrazovku kreslí ten istý
    /// view, takže bez toho by si ďalšia obrazovka odniesla trasu z predchádzajúcej.
    @State private var routeTargetKey: String?

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
                    routeOverlay(to: target)
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .task(id: routeTaskID) { await refreshRoute(to: target) }

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

    /// Trasa po chodníkoch, ak je načítaná; inak prerušovaná priamka k cieľu.
    @MapContentBuilder private func routeOverlay(to target: CLLocationCoordinate2D) -> some MapContent {
        if let route {
            MapPolyline(route.polyline)
                .stroke(accentColor, lineWidth: 5)
        } else if let user = locationManager.currentLocation?.coordinate {
            MapPolyline(coordinates: [user, target])
                .stroke(accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
        }
    }

    @ViewBuilder private func distanceLabel(to target: CLLocationCoordinate2D) -> some View {
        // Vzdialenosť, ktorú vidí hráč: dĺžka pešej trasy, ak ju máme, inak vzdušná čiara.
        if let d = route?.distance ?? locationManager.distance(to: target) {
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

    /// Kľúč pre `.task` — mení sa pri zmene cieľa, režimu trasy a po posune hráča
    /// (štvrté desatinné miesto ≈ 10 m), takže sa trasa neprepočítava zbytočne často.
    private var routeTaskID: String {
        let target = screen.targetCoordinate
        let user = locationManager.currentLocation?.coordinate
        return String(
            format: "%.6f,%.6f|%.4f,%.4f|%@",
            target?.latitude ?? 0, target?.longitude ?? 0,
            user?.latitude ?? 0, user?.longitude ?? 0,
            screen.directRoute ? "direct" : "walk"
        )
    }

    private func refreshRoute(to target: CLLocationCoordinate2D) async {
        let targetKey = String(format: "%.6f,%.6f", target.latitude, target.longitude)
        if routeTargetKey != targetKey {
            routeTargetKey = targetKey
            route = nil
            lastRouteFetch = nil
        }

        guard !screen.directRoute else {
            route = nil
            return
        }
        guard let user = locationManager.currentLocation else { return }
        if let last = lastRouteFetch, route != nil,
           last.distance(from: user) <= rerouteThresholdMeters { return }
        lastRouteFetch = user

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: user.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
        } catch {
            // Offline alebo sa pešia trasa nenašla — ostane priamka.
            route = nil
        }
    }
}
