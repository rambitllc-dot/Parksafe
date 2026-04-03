import Foundation
import CoreLocation
import CoreMotion
import UserNotifications

/// ParkingDetector — automatically detects when you park using CoreMotion + CLVisit.
/// Works regardless of which maps app you use (Apple Maps, Google Maps, Waze, etc.)
/// because it detects the physical act of parking, not app data.
///
/// Flow:
///   driving → car stops → CoreMotion detects stationary → GPS saved → alerts scheduled
///
class ParkingDetector: NSObject, ObservableObject, CLLocationManagerDelegate {

```
static let shared = ParkingDetector()

private let locationManager = CLLocationManager()
private let motionManager   = CMMotionActivityManager()
private let defaults        = UserDefaults.standard
private var wasInCar        = false

// UserDefaults keys
private let kLat    = "parksafe_lat"
private let kLon    = "parksafe_lon"
private let kStreet = "parksafe_street"
private let kTime   = "parksafe_time"

@Published var parkedCoordinate: CLLocationCoordinate2D?
@Published var parkedStreetName: String?
@Published var parkedAt: Date?
@Published var isParked: Bool = false

override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    loadSaved()
}

// MARK: - Public

func requestPermissions() {
    locationManager.requestWhenInUseAuthorization()
}

/// Start both CLVisit monitoring and CoreMotion activity tracking
func startMonitoring() {
    locationManager.startMonitoringVisits()
    guard CMMotionActivityManager.isActivityAvailable() else { return }
    motionManager.startActivityUpdates(to: .main) { [weak self] activity in
        guard let self = self, let activity = activity else { return }
        self.handleMotionActivity(activity)
    }
}

func stopMonitoring() {
    locationManager.stopMonitoringVisits()
    motionManager.stopActivityUpdates()
}

/// User manually taps "I parked here" button in the app
func setManualParkLocation(coordinate: CLLocationCoordinate2D) {
    saveParked(coordinate: coordinate)
    scheduleAlertsIfNeeded(for: coordinate)
}

/// User taps "I moved my car" — clears everything
func clearParked() {
    defaults.removeObject(forKey: kLat)
    defaults.removeObject(forKey: kLon)
    defaults.removeObject(forKey: kStreet)
    defaults.removeObject(forKey: kTime)
    UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: ["ps_2h", "ps_1h", "ps_30m"]
    )
    DispatchQueue.main.async {
        self.parkedCoordinate = nil
        self.parkedStreetName = nil
        self.parkedAt = nil
        self.isParked = false
    }
}

// MARK: - CoreMotion Handler

private func handleMotionActivity(_ activity: CMMotionActivity) {
    let inCar = activity.automotive && activity.confidence != .low
    // Transition: was driving → now stationary = just parked
    if wasInCar && !inCar && activity.stationary {
        locationManager.requestLocation()
    }
    wasInCar = inCar
}

// MARK: - CLLocationManagerDelegate

/// CLVisit: iOS detected you arrived somewhere
func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let isArrival = visit.departureDate == Date.distantFuture
    guard isArrival else { return }
    saveParked(coordinate: visit.coordinate)
    scheduleAlertsIfNeeded(for: visit.coordinate)
}

/// Called after requestLocation() from CoreMotion handler
func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else { return }
    guard abs(loc.timestamp.timeIntervalSinceNow) < 10 else { return }
    saveParked(coordinate: loc.coordinate)
    scheduleAlertsIfNeeded(for: loc.coordinate)
}

func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("ParkingDetector error: \(error.localizedDescription)")
}

func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if status == .authorizedWhenInUse || status == .authorizedAlways {
        startMonitoring()
    }
}

// MARK: - Save / Load

private func saveParked(coordinate: CLLocationCoordinate2D) {
    defaults.set(coordinate.latitude,  forKey: kLat)
    defaults.set(coordinate.longitude, forKey: kLon)
    defaults.set(Date(),               forKey: kTime)
    DispatchQueue.main.async {
        self.parkedCoordinate = coordinate
        self.parkedAt = Date()
        self.isParked = true
    }
    // Reverse geocode to get street name
    CLGeocoder().reverseGeocodeLocation(
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    ) { [weak self] placemarks, _ in
        guard let self = self else { return }
        let street = placemarks?.first?.thoroughfare ?? "Unknown Street"
        self.defaults.set(street, forKey: self.kStreet)
        DispatchQueue.main.async { self.parkedStreetName = street }
    }
}

private func loadSaved() {
    let lat = defaults.double(forKey: kLat)
    let lon = defaults.double(forKey: kLon)
    guard lat != 0, lon != 0 else { return }
    parkedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    parkedStreetName = defaults.string(forKey: kStreet)
    parkedAt         = defaults.object(forKey: kTime) as? Date
    isParked         = true
}

// MARK: - Schedule Matching & Alerts

private func scheduleAlertsIfNeeded(for coordinate: CLLocationCoordinate2D) {
    guard let url = Bundle.main.url(forResource: "san_francisco", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let streets = json["streets"] as? [[String: Any]] else { return }

    let parkedLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let weekday   = Calendar.current.component(.weekday, from: Date())

    for street in streets {
        guard let lat      = street["lat"] as? Double,
              let lon      = street["lon"] as? Double,
              let name     = street["name"] as? String,
              let schedule = street["schedule"] as? [[String: Any]] else { continue }

        guard parkedLoc.distance(from: CLLocation(latitude: lat, longitude: lon)) < 80 else { continue }

        for entry in schedule {
            guard let days      = entry["days"] as? [Int],
                  let startHour = entry["startHour"] as? Int,
                  days.contains(weekday) else { continue }

            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["ps_2h", "ps_1h", "ps_30m"]
            )
            fireAlert(id: "ps_2h",  title: "🚗 Move Your Car Soon",
                      body: "\(name) street cleaning starts in 2 hours.",
                      hour: startHour - 2, minute: 0)
            fireAlert(id: "ps_1h",  title: "⚠️ Move Your Car",
                      body: "\(name) street cleaning starts in 1 hour!",
                      hour: startHour - 1, minute: 0)
            fireAlert(id: "ps_30m", title: "🚨 Move Now!",
                      body: "\(name) street cleaning starts in 30 minutes!",
                      hour: startHour, minute: -30)
        }
        break
    }
}

private func fireAlert(id: String, title: String, body: String, hour: Int, minute: Int) {
    var h = hour, m = minute
    if m < 0 { h -= 1; m += 60 }
    var components   = DateComponents()
    components.hour  = h
    components.minute = m
    guard let fireDate = Calendar.current.date(from: components),
          fireDate > Date() else { return }
    let content   = UNMutableNotificationContent()
    content.title = title
    content.body  = body
    content.sound = .default
    let trigger   = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    )
}
```

}
