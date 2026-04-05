import Foundation
import CoreLocation
import CoreMotion
import UserNotifications

class ParkingDetector: NSObject, ObservableObject, CLLocationManagerDelegate {

```
static let shared = ParkingDetector()

private let locationManager = CLLocationManager()
private let motionManager   = CMMotionActivityManager()
private let defaults        = UserDefaults.standard
private var wasInCar        = false

private let kLat    = "parksafe_lat"
private let kLon    = "parksafe_lon"
private let kStreet = "parksafe_street"
private let kTime   = "parksafe_time"

@Published var parkedCoordinate: CLLocationCoordinate2D?
@Published var parkedStreetName: String = "Not detected yet"
@Published var parkedAt: Date?
@Published var isParked: Bool = false
@Published var debugLog: [String] = []

override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    loadSaved()
    log("ParkingDetector initialized")
}

// MARK: - Logging
func log(_ msg: String) {
    let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let entry = "[\(time)] \(msg)"
    print("ParkSafe: \(entry)")
    DispatchQueue.main.async {
        self.debugLog.insert(entry, at: 0)
        if self.debugLog.count > 50 { self.debugLog.removeLast() }
    }
}

// MARK: - Public

func requestPermissions() {
    log("Requesting location permissions...")
    locationManager.requestWhenInUseAuthorization()
}

func startMonitoring() {
    log("Starting monitoring (CLVisit + CoreMotion)...")
    locationManager.startMonitoringVisits()
    guard CMMotionActivityManager.isActivityAvailable() else {
        log("CoreMotion not available on this device")
        return
    }
    motionManager.startActivityUpdates(to: .main) { [weak self] activity in
        guard let self = self, let activity = activity else { return }
        self.handleMotionActivity(activity)
    }
    log("Monitoring started!")
}

func stopMonitoring() {
    locationManager.stopMonitoringVisits()
    motionManager.stopActivityUpdates()
    log("Monitoring stopped")
}

/// TEST: Manually set current location as parked (for testing without driving)
func testParkHere() {
    log("TEST: Requesting current location to simulate parking...")
    locationManager.requestLocation()
}

/// TEST: Fire a test notification in 10 seconds
func testNotificationIn10Seconds() {
    log("TEST: Scheduling test notification in 10 seconds...")
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    let content = UNMutableNotificationContent()
    content.title = "🧪 ParkSafe Test Alert"
    content.body  = "Notifications are working! Street cleaning starts in 1 hour."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
    let request = UNNotificationRequest(identifier: "ps_test", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { [weak self] error in
        if let error = error {
            self?.log("TEST ERROR: \(error.localizedDescription)")
        } else {
            self?.log("TEST: Notification scheduled! Lock your screen and wait 10 seconds.")
        }
    }
}

/// Clear parked location
func clearParked() {
    defaults.removeObject(forKey: kLat)
    defaults.removeObject(forKey: kLon)
    defaults.removeObject(forKey: kStreet)
    defaults.removeObject(forKey: kTime)
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    DispatchQueue.main.async {
        self.parkedCoordinate = nil
        self.parkedStreetName = "Not detected yet"
        self.parkedAt = nil
        self.isParked = false
    }
    log("Parked location cleared, all alerts cancelled")
}

// MARK: - CoreMotion

private func handleMotionActivity(_ activity: CMMotionActivity) {
    let inCar = activity.automotive && activity.confidence != .low
    if wasInCar && !inCar && activity.stationary {
        log("CoreMotion: Detected parking! Requesting location...")
        locationManager.requestLocation()
    }
    wasInCar = inCar
}

// MARK: - CLLocationManagerDelegate

func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let isArrival = visit.departureDate == Date.distantFuture
    log("CLVisit: \(isArrival ? "Arrived" : "Departed") at \(visit.coordinate.latitude), \(visit.coordinate.longitude)")
    guard isArrival else { return }
    saveParked(coordinate: visit.coordinate)
    scheduleAlertsIfNeeded(for: visit.coordinate)
}

func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else { return }
    log("Location update: \(loc.coordinate.latitude), \(loc.coordinate.longitude) accuracy: \(Int(loc.horizontalAccuracy))m")
    saveParked(coordinate: loc.coordinate)
    scheduleAlertsIfNeeded(for: loc.coordinate)
}

func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    log("Location ERROR: \(error.localizedDescription)")
}

func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    switch status {
    case .authorizedWhenInUse: log("Permission: When In Use ✅")
    case .authorizedAlways:    log("Permission: Always ✅")
    case .denied:              log("Permission: DENIED ❌")
    case .restricted:          log("Permission: Restricted ❌")
    case .notDetermined:       log("Permission: Not determined yet")
    @unknown default:          log("Permission: Unknown")
    }
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
    log("Saved parked location: \(coordinate.latitude), \(coordinate.longitude)")
    CLGeocoder().reverseGeocodeLocation(
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    ) { [weak self] placemarks, error in
        guard let self = self else { return }
        if let error = error {
            self.log("Geocoding error: \(error.localizedDescription)")
            return
        }
        let street = placemarks?.first?.thoroughfare ?? "Unknown Street"
        self.defaults.set(street, forKey: self.kStreet)
        DispatchQueue.main.async { self.parkedStreetName = street }
        self.log("Street identified: \(street)")
    }
}

private func loadSaved() {
    let lat = defaults.double(forKey: kLat)
    let lon = defaults.double(forKey: kLon)
    guard lat != 0, lon != 0 else {
        log("No saved parking location found")
        return
    }
    parkedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    parkedStreetName = defaults.string(forKey: kStreet) ?? "Unknown Street"
    parkedAt         = defaults.object(forKey: kTime) as? Date
    isParked         = true
    log("Loaded saved location: \(parkedStreetName)")
}

// MARK: - Schedule & Alerts

private func scheduleAlertsIfNeeded(for coordinate: CLLocationCoordinate2D) {
    log("Checking schedule for parked location...")
    guard let url = Bundle.main.url(forResource: "san_francisco", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let streets = json["streets"] as? [[String: Any]] else {
        log("ERROR: Could not load san_francisco.json")
        return
    }

    let parkedLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let weekday   = Calendar.current.component(.weekday, from: Date())
    log("Today weekday: \(weekday), checking \(streets.count) streets...")

    var matchFound = false
    for street in streets {
        guard let lat      = street["lat"] as? Double,
              let lon      = street["lon"] as? Double,
              let name     = street["name"] as? String,
              let schedule = street["schedule"] as? [[String: Any]] else { continue }

        let distance = parkedLoc.distance(from: CLLocation(latitude: lat, longitude: lon))
        if distance < 80 {
            log("Match! Parked near: \(name) (\(Int(distance))m away)")
            matchFound = true
            for entry in schedule {
                guard let days      = entry["days"] as? [Int],
                      let startHour = entry["startHour"] as? Int,
                      days.contains(weekday) else { continue }
                log("Cleaning today at \(startHour):00 — scheduling alerts!")
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                fireAlert(id: "ps_2h",  title: "🚗 Move Your Car Soon",
                          body: "\(name) street cleaning starts in 2 hours.", hour: startHour - 2, minute: 0)
                fireAlert(id: "ps_1h",  title: "⚠️ Move Your Car",
                          body: "\(name) street cleaning starts in 1 hour!", hour: startHour - 1, minute: 0)
                fireAlert(id: "ps_30m", title: "🚨 Move Now!",
                          body: "\(name) street cleaning starts in 30 minutes!", hour: startHour, minute: -30)
            }
            break
        }
    }
    if !matchFound {
        log("No tracked street within 80m — no alerts scheduled")
    }
}

private func fireAlert(id: String, title: String, body: String, hour: Int, minute: Int) {
    var h = hour, m = minute
    if m < 0 { h -= 1; m += 60 }
    var components    = DateComponents()
    components.hour   = h
    components.minute = m
    guard let fireDate = Calendar.current.date(from: components),
          fireDate > Date() else {
        log("Alert \(id) skipped — time already passed")
        return
    }
    let content   = UNMutableNotificationContent()
    content.title = title
    content.body  = body
    content.sound = .default
    let trigger   = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    ) { [weak self] error in
        if let error = error {
            self?.log("Alert \(id) ERROR: \(error.localizedDescription)")
        } else {
            self?.log("Alert \(id) scheduled for \(h):\(String(format: "%02d", m)) ✅")
        }
    }
}
```

}
