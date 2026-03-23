import Foundation
import CoreLocation
import Combine

// MARK: - CityStore
// Manages which city is currently active and loads its street data.
// All views read from CityStore — swapping cities is a single assignment.

class CityStore: ObservableObject {
@Published var activeCity: City {
didSet {
UserDefaults.standard.set(activeCity.id, forKey: activeCityKey)
Task { await loadStreets(for: activeCity) }
}
}
@Published var streets: [StreetSegment] = []
@Published var isLoading = false
@Published var loadError: String?

```
private let activeCityKey = "activeCityId"
private let savedIdsKeyPrefix = "savedStreetIds_"

init() {
    // Restore last selected city, default to San Francisco
    let savedId = UserDefaults.standard.string(forKey: "activeCityId") ?? "san_francisco"
    self.activeCity = CityRegistry.city(id: savedId) ?? CityRegistry.available[0]
    Task { await loadStreets(for: activeCity) }
}

// MARK: - Auto-detect city from location

func autoDetectCity(from location: CLLocation) {
    guard let nearest = CityRegistry.nearest(to: location),
          nearest.id != activeCity.id else { return }
    DispatchQueue.main.async { self.activeCity = nearest }
}

// MARK: - Load streets for a city

@MainActor
func loadStreets(for city: City) async {
    isLoading = true
    loadError  = nil

    // 1. Try bundled JSON first (fast, works offline)
    if let bundled = loadBundledStreets(cityId: city.id) {
        streets = applyUserSavedState(bundled)
    }

    // 2. If city has a live API, try refreshing in background
    if city.dataSourceType == .openData || city.dataSourceType == .hybrid {
        if let live = await SFOpenDataService.shared.fetchSchedules(for: city) {
            streets = applyUserSavedState(live)
        }
    }

    isLoading = false
}

// MARK: - Saved streets (persisted per city)

func toggleSave(_ street: StreetSegment) {
    guard let idx = streets.firstIndex(where: { $0.id == street.id }) else { return }
    streets[idx].isSaved.toggle()
    persistSaved()
}

var savedStreets: [StreetSegment] { streets.filter { $0.isSaved } }

private func persistSaved() {
    let key = savedIdsKeyPrefix + activeCity.id
    let ids = streets.filter { $0.isSaved }.map { $0.id }
    UserDefaults.standard.set(ids, forKey: key)
}

private func applyUserSavedState(_ input: [StreetSegment]) -> [StreetSegment] {
    let key    = savedIdsKeyPrefix + activeCity.id
    let saved  = (UserDefaults.standard.array(forKey: key) as? [Int]) ?? defaultSavedIds()
    return input.map { s in
        var m = s; m.isSaved = saved.contains(s.id); return m
    }
}

private func defaultSavedIds() -> [Int] {
    // First 3 streets pre-saved for first launch experience
    Array(streets.prefix(3).map { $0.id })
}

// MARK: - Bundled JSON loader

private func loadBundledStreets(cityId: String) -> [StreetSegment]? {
    guard let url = Bundle.main.url(forResource: cityId, withExtension: "json",
                                    subdirectory: "CityData"),
          let data = try? Data(contentsOf: url),
          let streets = try? JSONDecoder().decode([StreetSegment].self, from: data)
    else { return ScheduleStore.fallbackStreets(cityId: cityId) }
    return streets
}
```

}

// MARK: - ScheduleStore (legacy compatibility shim + hardcoded fallbacks)

class ScheduleStore: ObservableObject {
// Kept for backwards compatibility. New code uses CityStore.
@Published var streets: [StreetSegment] = []
@Published var alerts: [AlertItem] = []

```
var savedStreets: [StreetSegment] { streets.filter { $0.isSaved } }

init() {
    streets = Self.fallbackStreets(cityId: "san_francisco") ?? []
    loadAlerts()
}

func toggleSave(_ street: StreetSegment) {
    guard let idx = streets.firstIndex(where: { $0.id == street.id }) else { return }
    streets[idx].isSaved.toggle()
}

// Hardcoded fallback data — used when JSON file is missing (dev builds)
static func fallbackStreets(cityId: String) -> [StreetSegment]? {
    guard cityId == "san_francisco" else { return nil }
    return sanFranciscoStreets
}

private func loadAlerts() {
    alerts = [
        AlertItem(type: .danger,  title: String(localized: "alert.mission.title"),
                  body: String(localized: "alert.mission.body"), timestamp: Date().addingTimeInterval(-600)),
        AlertItem(type: .danger,  title: String(localized: "alert.dolores.title"),
                  body: String(localized: "alert.dolores.body"), timestamp: Date().addingTimeInterval(-7200)),
        AlertItem(type: .safe,    title: String(localized: "alert.valencia.title"),
                  body: String(localized: "alert.valencia.body"), timestamp: Date().addingTimeInterval(-86400)),
        AlertItem(type: .warning, title: String(localized: "alert.castro.title"),
                  body: String(localized: "alert.castro.body"), timestamp: Date().addingTimeInterval(-172800)),
        AlertItem(type: .info,    title: String(localized: "alert.update.title"),
                  body: String(localized: "alert.update.body"), timestamp: Date().addingTimeInterval(-259200)),
    ]
}

// MARK: - San Francisco street data (25 streets)
static let sanFranciscoStreets: [StreetSegment] = [
    StreetSegment(id:1,  cityId:"san_francisco", name:"Mission St",     fromCross:"22nd St",      toCross:"25th St",       neighborhood:"Mission District",      latitude:37.7558, longitude:-122.4183, cleaningDays:[CleaningSchedule(weekday:3,startHour:8,endHour:10),CleaningSchedule(weekday:6,startHour:8,endHour:10)]),
    StreetSegment(id:2,  cityId:"san_francisco", name:"Valencia St",    fromCross:"16th St",      toCross:"24th St",       neighborhood:"Mission District",      latitude:37.7598, longitude:-122.4213, cleaningDays:[CleaningSchedule(weekday:2,startHour:9,endHour:11),CleaningSchedule(weekday:5,startHour:9,endHour:11)]),
    StreetSegment(id:3,  cityId:"san_francisco", name:"Guerrero St",    fromCross:"16th St",      toCross:"23rd St",       neighborhood:"Mission District",      latitude:37.7612, longitude:-122.4239, cleaningDays:[CleaningSchedule(weekday:4,startHour:12,endHour:14)]),
    StreetSegment(id:4,  cityId:"san_francisco", name:"Dolores St",     fromCross:"16th St",      toCross:"24th St",       neighborhood:"Mission / Noe Valley",  latitude:37.7601, longitude:-122.4260, cleaningDays:[CleaningSchedule(weekday:3,startHour:10,endHour:12),CleaningSchedule(weekday:6,startHour:10,endHour:12)]),
    StreetSegment(id:5,  cityId:"san_francisco", name:"24th St",        fromCross:"Mission St",   toCross:"Potrero Ave",   neighborhood:"Mission / Potrero",     latitude:37.7522, longitude:-122.4149, cleaningDays:[CleaningSchedule(weekday:4,startHour:9,endHour:11),CleaningSchedule(weekday:7,startHour:9,endHour:11)]),
    StreetSegment(id:6,  cityId:"san_francisco", name:"Castro St",      fromCross:"Market St",    toCross:"19th St",       neighborhood:"Castro",                latitude:37.7620, longitude:-122.4350, cleaningDays:[CleaningSchedule(weekday:2,startHour:8,endHour:10),CleaningSchedule(weekday:5,startHour:8,endHour:10)]),
    StreetSegment(id:7,  cityId:"san_francisco", name:"18th St",        fromCross:"Castro St",    toCross:"Sanchez St",    neighborhood:"Castro",                latitude:37.7603, longitude:-122.4336, cleaningDays:[CleaningSchedule(weekday:3,startHour:9,endHour:11)]),
    StreetSegment(id:8,  cityId:"san_francisco", name:"Noe St",         fromCross:"24th St",      toCross:"30th St",       neighborhood:"Noe Valley",            latitude:37.7491, longitude:-122.4319, cleaningDays:[CleaningSchedule(weekday:4,startHour:10,endHour:12),CleaningSchedule(weekday:7,startHour:10,endHour:12)]),
    StreetSegment(id:9,  cityId:"san_francisco", name:"Church St",      fromCross:"Market St",    toCross:"30th St",       neighborhood:"Noe Valley / Castro",   latitude:37.7567, longitude:-122.4289, cleaningDays:[CleaningSchedule(weekday:2,startHour:8,endHour:10),CleaningSchedule(weekday:5,startHour:8,endHour:10)]),
    StreetSegment(id:10, cityId:"san_francisco", name:"Haight St",      fromCross:"Masonic Ave",  toCross:"Stanyan St",    neighborhood:"Haight-Ashbury",        latitude:37.7692, longitude:-122.4481, cleaningDays:[CleaningSchedule(weekday:3,startHour:9,endHour:11),CleaningSchedule(weekday:6,startHour:9,endHour:11)]),
    StreetSegment(id:11, cityId:"san_francisco", name:"Divisadero St",  fromCross:"Oak St",       toCross:"Fell St",       neighborhood:"NoPa",                  latitude:37.7731, longitude:-122.4376, cleaningDays:[CleaningSchedule(weekday:2,startHour:10,endHour:12)]),
    StreetSegment(id:12, cityId:"san_francisco", name:"Page St",        fromCross:"Divisadero",   toCross:"Clayton St",    neighborhood:"Haight-Ashbury",        latitude:37.7715, longitude:-122.4446, cleaningDays:[CleaningSchedule(weekday:3,startHour:8,endHour:10),CleaningSchedule(weekday:6,startHour:8,endHour:10)]),
    StreetSegment(id:13, cityId:"san_francisco", name:"Panhandle Path", fromCross:"Baker St",     toCross:"Masonic Ave",   neighborhood:"NoPa",                  latitude:37.7717, longitude:-122.4425, cleaningDays:[CleaningSchedule(weekday:4,startHour:7,endHour:9)]),
    StreetSegment(id:14, cityId:"san_francisco", name:"Fillmore St",    fromCross:"Post St",      toCross:"Sutter St",     neighborhood:"Lower Pacific Heights", latitude:37.7855, longitude:-122.4328, cleaningDays:[CleaningSchedule(weekday:2,startHour:11,endHour:13),CleaningSchedule(weekday:4,startHour:11,endHour:13)]),
    StreetSegment(id:15, cityId:"san_francisco", name:"Union St",       fromCross:"Fillmore St",  toCross:"Steiner St",    neighborhood:"Cow Hollow / Marina",   latitude:37.7979, longitude:-122.4348, cleaningDays:[CleaningSchedule(weekday:3,startHour:9,endHour:11),CleaningSchedule(weekday:6,startHour:9,endHour:11)]),
    StreetSegment(id:16, cityId:"san_francisco", name:"Chestnut St",    fromCross:"Scott St",     toCross:"Divisadero",    neighborhood:"Marina District",       latitude:37.8003, longitude:-122.4361, cleaningDays:[CleaningSchedule(weekday:4,startHour:8,endHour:10),CleaningSchedule(weekday:7,startHour:8,endHour:10)]),
    StreetSegment(id:17, cityId:"san_francisco", name:"Lombard St",     fromCross:"Broderick",    toCross:"Divisadero",    neighborhood:"Marina District",       latitude:37.7992, longitude:-122.4378, cleaningDays:[CleaningSchedule(weekday:2,startHour:7,endHour:9)]),
    StreetSegment(id:18, cityId:"san_francisco", name:"Columbus Ave",   fromCross:"Broadway",     toCross:"Vallejo St",    neighborhood:"North Beach",           latitude:37.7986, longitude:-122.4070, cleaningDays:[CleaningSchedule(weekday:3,startHour:7,endHour:9),CleaningSchedule(weekday:6,startHour:7,endHour:9)]),
    StreetSegment(id:19, cityId:"san_francisco", name:"Grant Ave",      fromCross:"Bush St",      toCross:"Sacramento St", neighborhood:"Chinatown",             latitude:37.7918, longitude:-122.4065, cleaningDays:[CleaningSchedule(weekday:2,startHour:6,endHour:8),CleaningSchedule(weekday:5,startHour:6,endHour:8)]),
    StreetSegment(id:20, cityId:"san_francisco", name:"Polk St",        fromCross:"California St",toCross:"Broadway",      neighborhood:"Polk Gulch",            latitude:37.7935, longitude:-122.4197, cleaningDays:[CleaningSchedule(weekday:3,startHour:8,endHour:10),CleaningSchedule(weekday:6,startHour:8,endHour:10)]),
    StreetSegment(id:21, cityId:"san_francisco", name:"Bryant St",      fromCross:"4th St",       toCross:"10th St",       neighborhood:"SoMa",                  latitude:37.7746, longitude:-122.4037, cleaningDays:[CleaningSchedule(weekday:4,startHour:8,endHour:10),CleaningSchedule(weekday:7,startHour:8,endHour:10)]),
    StreetSegment(id:22, cityId:"san_francisco", name:"Folsom St",      fromCross:"4th St",       toCross:"10th St",       neighborhood:"SoMa",                  latitude:37.7760, longitude:-122.4030, cleaningDays:[CleaningSchedule(weekday:3,startHour:9,endHour:11),CleaningSchedule(weekday:5,startHour:9,endHour:11)]),
    StreetSegment(id:23, cityId:"san_francisco", name:"Potrero Ave",    fromCross:"Division St",  toCross:"26th St",       neighborhood:"Potrero Hill",          latitude:37.7623, longitude:-122.4068, cleaningDays:[CleaningSchedule(weekday:2,startHour:10,endHour:12),CleaningSchedule(weekday:5,startHour:10,endHour:12)]),
    StreetSegment(id:24, cityId:"san_francisco", name:"Geary Blvd",    fromCross:"Arguello Blvd",toCross:"10th Ave",       neighborhood:"Inner Richmond",        latitude:37.7807, longitude:-122.4647, cleaningDays:[CleaningSchedule(weekday:4,startHour:9,endHour:11),CleaningSchedule(weekday:7,startHour:9,endHour:11)]),
    StreetSegment(id:25, cityId:"san_francisco", name:"Irving St",      fromCross:"5th Ave",      toCross:"12th Ave",      neighborhood:"Inner Sunset",          latitude:37.7641, longitude:-122.4675, cleaningDays:[CleaningSchedule(weekday:3,startHour:10,endHour:12),CleaningSchedule(weekday:6,startHour:10,endHour:12)]),
]
```

}
