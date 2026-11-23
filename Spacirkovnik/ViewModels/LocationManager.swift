import Foundation
import CoreLocation
import Observation

/// Sleduje GPS polohu a smer zariadenia. Ekvivalent android `LocationViewModel` +
/// `TrackLocationWhileVisible` / `rememberDeviceAzimuth` (Play Services Location → Core Location).
///
/// GPS beží len vtedy, keď ju niekto naozaj potrebuje — navigačná obrazovka ju zapne cez
/// `startTracking()` a pri odchode (otázka, koniec hry, ukončenie) aj pri prechode appky do
/// pozadia ju vypne cez `stopTracking()`. V zozname hier sa batéria nemíňa.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var currentLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Smer, kam je otočený vrch telefónu, v stupňoch od severu (0–360), alebo nil, kým ho nepoznáme.
    private(set) var heading: CLLocationDirection?
    /// Poloha je nastavená ručne (len vývojový build — „Presunúť sa do cieľa").
    private(set) var isDebugMode = false

    private let manager = CLLocationManager()
    private var isTracking = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 3
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Zapne GPS a kompas. Pri prvom volaní si vypýta povolenie, ak ho appka ešte nemá.
    func startTracking() {
        isTracking = true
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return // zapne sa v locationManagerDidChangeAuthorization
        }
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    /// Vypne GPS aj kompas.
    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Ručne nastavená poloha na skúšanie trás bez chodenia (len vývojový build).
    func setDebugLocation(_ coordinate: CLLocationCoordinate2D) {
        isDebugMode = true
        currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Vzdialenosť (v metroch) z aktuálnej polohy do cieľa, alebo nil ak poloha nie je známa.
    func distance(to target: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        let dest = CLLocation(latitude: target.latitude, longitude: target.longitude)
        return current.distance(from: dest)
    }

    /// Azimut z aktuálnej polohy k cieľu v stupňoch od severu (0–360), alebo nil.
    func bearing(to target: CLLocationCoordinate2D) -> Double? {
        guard let from = currentLocation?.coordinate else { return nil }
        let lat1 = from.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let dLon = (target.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            guard !self.isDebugMode else { return }
            self.currentLocation = last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // Povolenie prišlo, kým bola navigácia otvorená — zapni GPS. Inak nič nespúšťame.
            if self.isTracking, self.isAuthorized {
                self.startTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Tichý fail — UI sa zariadi podľa toho, že currentLocation ostáva nil.
    }
}
