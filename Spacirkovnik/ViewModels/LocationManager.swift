import Foundation
import CoreLocation
import Observation

/// Sleduje GPS polohu zariadenia. Ekvivalent android `LocationViewModel`
/// (Play Services Location → Core Location).
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Vzdialenosť (v metroch) z aktuálnej polohy do cieľa, alebo nil ak poloha nie je známa.
    func distance(to target: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        let dest = CLLocation(latitude: target.latitude, longitude: target.longitude)
        return current.distance(from: dest)
    }

    /// Je hráč v okruhu `radius` metrov od cieľa? (default 25 m ako na Androide)
    func isWithin(radius: CLLocationDistance = 25, of target: CLLocationCoordinate2D) -> Bool {
        guard let d = distance(to: target) else { return false }
        return d <= radius
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Tichý fail — UI sa zariadi podľa toho, že currentLocation ostáva nil.
    }
}
