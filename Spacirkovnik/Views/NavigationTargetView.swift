import SwiftUI
import MapKit
import UIKit

/// NAVIGATION obrazovka — upozornenie na okolie, mapa s cieľom a kompasom, vzdialenosť
/// a tlačidlo, ktoré sa odomkne až pri cieli. Ekvivalent android `NavigationDisplay`.
///
/// Používa natívny MapKit (bez API kľúča) — `MKDirections` s `.walking` je iOS náhrada
/// za Mapbox Directions z android verzie. Predvolene sa kreslí skutočná pešia trasa po
/// chodníkoch a vzdialenosť podľa nej. Ak má obrazovka `directRoute: true` (alebo sa trasu
/// nepodarí načítať — offline, cieľ mimo chodníkov), kreslí sa priamka a vzdušná vzdialenosť.
///
/// GPS beží len kým je táto obrazovka na displeji a appka je v popredí; dovtedy telefón ani nezhasne.
struct NavigationTargetView: View {
    let screen: GameScreen
    var locationManager: LocationManager
    let onArrived: () -> Void

    /// Ako blízko k cieľu musí hráč prísť, aby mohol pokračovať (rovnako ako na Androide).
    static let arrivalRadius: CLLocationDistance = 10
    /// Novú trasu pýtame, až keď hráč prejde aspoň toľko metrov — inak by sme
    /// prepočítavali pri každom tiknutí GPS (rovnaký prah ako na Androide).
    private let rerouteThresholdMeters: CLLocationDistance = 15

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var route: MKRoute?
    @State private var lastRouteFetch: CLLocation?
    @State private var arrivalAnnounced = false
    @State private var isFullscreen = false

    var body: some View {
        VStack(spacing: 0) {
            safetyNotice

            if let target = screen.targetCoordinate {
                NavigationMapView(
                    target: target,
                    route: route,
                    locationManager: locationManager,
                    isFullscreen: false,
                    onToggleFullscreen: { isFullscreen = true }
                )
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 12)
                .task(id: routeTaskID) { await refreshRoute(to: target) }

                if locationManager.isDenied {
                    locationDeniedNotice.padding(.top, 12)
                } else {
                    distanceLabel(to: target).padding(.top, 12)
                }

                arrivalButton(enabled: isCloseEnough(to: target))
                    .padding(.top, 32)

                #if DEBUG
                // Skúšanie bez chodenia: presunie polohu na cieľ, ďalej sa ide bežným „Pokračovať"
                // (aj s vibráciou pri príchode). Poloha potom ostane tu aj pre ďalšiu zastávku.
                Button { locationManager.setDebugLocation(target) } label: {
                    Text("[DEBUG] Presunúť sa do cieľa")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(rgb: 0x444444), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                #endif
            } else {
                Text("Chýba cieľová poloha pre túto obrazovku.")
                    .foregroundStyle(AppColor.textOnDark)
                    .padding(.top, 12)
                arrivalButton(enabled: true).padding(.top, 32)
            }
        }
        .padding(.bottom, 32)
        .onAppear {
            locationManager.startTracking()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Mapa na celú obrazovku prekryje túto obrazovku — navigácia ale beží ďalej.
            guard !isFullscreen else { return }
            locationManager.stopTracking()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, phase in
            // Appka v pozadí / zhasnutý displej: GPS vypnúť, po návrate znova zapnúť.
            if phase == .active {
                locationManager.startTracking()
                UIApplication.shared.isIdleTimerDisabled = true
            } else if phase == .background {
                locationManager.stopTracking()
            }
        }
        .onChange(of: screen.targetCoordinate.map { isCloseEnough(to: $0) } ?? false, initial: true) { _, close in
            // Hráč došiel k cieľu: zavibruje raz za zastávku — aj keď GPS okolo hranice
            // poskakuje dnu a von, ďalšie vibrácie by len rušili.
            if close && !arrivalAnnounced {
                arrivalAnnounced = true
                Haptics.arrived()
            }
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            if let target = screen.targetCoordinate {
                NavigationMapView(
                    target: target,
                    route: route,
                    locationManager: locationManager,
                    isFullscreen: true,
                    onToggleFullscreen: { isFullscreen = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func isCloseEnough(to target: CLLocationCoordinate2D) -> Bool {
        guard let d = locationManager.distance(to: target) else { return false }
        return d <= Self.arrivalRadius
    }

    private var safetyNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(rgb: 0xC05800))
            Text("Dávaj pozor na okolie! Cestou môžeš naraziť na cesty s autami, vodné plochy alebo iné prekážky.")
                .font(.system(size: 13))
                .foregroundStyle(Color(rgb: 0x7A3500))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(rgb: 0xFFEDD5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func distanceLabel(to target: CLLocationCoordinate2D) -> some View {
        // Vzdialenosť, ktorú vidí hráč: dĺžka pešej trasy, ak ju máme, inak vzdušná čiara.
        if let d = route?.distance ?? locationManager.distance(to: target) {
            Text(d >= 1000 ? String(format: "%.1f km", d / 1000).replacingOccurrences(of: ".", with: ",") : "\(Int(d)) m")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppColor.textOnDark)
        } else {
            Text("Hľadám polohu...")
                .font(.system(size: 18))
                .foregroundStyle(AppColor.textOnDark.opacity(0.7))
        }
    }

    private var locationDeniedNotice: some View {
        VStack(spacing: 8) {
            Text("Bez prístupu k polohe ťa nevieme navigovať k cieľu.")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.textOnDark)
                .multilineTextAlignment(.center)
            Button("Povoliť polohu v Nastaveniach") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.system(size: 15, weight: .semibold))
            .tint(AppColor.amber)
        }
    }

    private func arrivalButton(enabled: Bool) -> some View {
        Button(action: onArrived) {
            Text(enabled ? "Pokračovať" : "Musíš sa priblížiť")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.primaryButtonText.opacity(enabled ? 1 : 0.6))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(enabled ? AppColor.primaryButton : AppColor.disabledButton,
                            in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("arrivalButton")
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

/// Mapa navigácie s kompasom a tlačidlami. Kamera sleduje hráča a cieľ, kým mapou hráč sám
/// nepohne; potom sa dá vrátiť tlačidlom „pohľad na trasu". Ekvivalent android `NavMapContent`.
private struct NavigationMapView: View {
    let target: CLLocationCoordinate2D
    let route: MKRoute?
    var locationManager: LocationManager
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void

    @State private var position: MapCameraPosition = .automatic

    private let routeColor = Color(rgb: 0x1565C0)

    var body: some View {
        ZStack {
            Map(position: $position) {
                if let user = userCoordinate {
                    MapPolyline(coordinates: lineCoordinates(from: user))
                        .stroke(routeColor, style: StrokeStyle(
                            lineWidth: 4,
                            dash: route == nil ? [8, 6] : []
                        ))
                    Annotation("Ty", coordinate: user, anchor: .center) {
                        pin(color: routeColor)
                    }
                }
                Annotation("Cieľ", coordinate: target, anchor: .center) {
                    pin(color: Color(rgb: 0xD50000))
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapScaleView() }

            VStack {
                if isFullscreen { Spacer().frame(height: 50) }
                Spacer()
                HStack(alignment: .bottom) {
                    CompassOverlay(
                        heading: locationManager.heading ?? 0,
                        bearing: locationManager.bearing(to: target)
                    )
                    Spacer()
                    VStack(spacing: 10) {
                        if position.positionedByUser {
                            roundButton(systemImage: "map", label: "Pohľad na trasu") {
                                withAnimation { position = fittedPosition() }
                            }
                        }
                        if userCoordinate != nil {
                            roundButton(systemImage: "location.fill", label: "Moja poloha") {
                                guard let user = userCoordinate else { return }
                                withAnimation {
                                    position = .camera(MapCamera(centerCoordinate: user, distance: 600))
                                }
                            }
                        }
                        roundButton(
                            systemImage: isFullscreen
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right",
                            label: isFullscreen ? "Zmenšiť mapu" : "Zväčšiť mapu",
                            action: onToggleFullscreen
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                // Nad logom a odkazom „Legal" Apple Maps — tie musia ostať viditeľné.
                .padding(.bottom, 30)
                if isFullscreen { Spacer().frame(height: 24) }
            }
        }
        .onAppear { position = fittedPosition() }
        .onChange(of: userCoordinateKey) { _, _ in
            // Kamera ide za hráčom, kým mapou nepohol sám.
            guard !position.positionedByUser else { return }
            withAnimation(.easeInOut(duration: 0.6)) { position = fittedPosition() }
        }
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
    }

    private var userCoordinateKey: String {
        guard let u = userCoordinate else { return "-" }
        return String(format: "%.5f,%.5f", u.latitude, u.longitude)
    }

    /// Trasa po chodníkoch začína a končí na najbližšom chodníku — dopojíme ju rovnými úsekmi,
    /// aby čiara vždy viedla od bodky hráča k bodke cieľa. Bez trasy priamka.
    private func lineCoordinates(from user: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        guard let route, route.polyline.pointCount >= 2 else { return [user, target] }
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: route.polyline.pointCount))
        return [user] + coords + [target]
    }

    /// Kamera, v ktorej je vidieť hráča aj cieľ (bez polohy len cieľ).
    private func fittedPosition() -> MapCameraPosition {
        guard let user = userCoordinate else {
            return .region(MKCoordinateRegion(
                center: target, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
        let center = CLLocationCoordinate2D(
            latitude: (user.latitude + target.latitude) / 2,
            longitude: (user.longitude + target.longitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(abs(user.latitude - target.latitude) * 1.6, 0.0015),
            longitudeDelta: max(abs(user.longitude - target.longitude) * 1.6, 0.0015)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    private func pin(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 2)
    }

    private func roundButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.6), in: Circle())
                .overlay(Circle().stroke(AppColor.textOnDark.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Kompas so svetovými stranami (otáčajú sa podľa natočenia telefónu) a šípkou k cieľu.
/// Ekvivalent android `CompassOverlay`.
private struct CompassOverlay: View {
    /// Kam je otočený vrch telefónu, v stupňoch od severu.
    let heading: Double
    /// Smer k cieľu v stupňoch od severu, alebo nil, kým nepoznáme polohu.
    let bearing: Double?

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.6))
            Circle().stroke(AppColor.textOnDark.opacity(0.5), lineWidth: 1.5)
            Circle().stroke(AppColor.textOnDark.opacity(0.25), lineWidth: 1).padding(6)

            ZStack {
                cardinal("S").offset(y: -23)
                cardinal("J").offset(y: 23)
                cardinal("V").offset(x: 23)
                cardinal("Z").offset(x: -23)
            }
            .rotationEffect(.degrees(-heading))

            if let bearing {
                CompassArrow()
                    .fill(AppColor.amber)
                    .frame(width: 18, height: 44)
                    .rotationEffect(.degrees(bearing - heading))
            }
            Circle().fill(AppColor.textOnDark).frame(width: 5, height: 5)
        }
        .frame(width: 70, height: 70)
        .animation(.easeOut(duration: 0.2), value: heading)
        .accessibilityHidden(true)
    }

    private func cardinal(_ letter: String) -> some View {
        Text(letter)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            // Písmeno ostáva vzpriamené, otáča sa len jeho poloha.
            .rotationEffect(.degrees(heading))
    }
}

private struct CompassArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.1))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.05))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1))
        p.closeSubpath()
        return p
    }
}
