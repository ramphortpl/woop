import Foundation
import Combine
import CoreLocation

/// Live figures of an activity started with "Commencer l'activité": heart-rate based effort,
/// calories, zones and the GPS route ("Suivi d'itinéraire"). The activity is rescored from the
/// strap's full recording afterwards; these numbers are what is shown while it runs.
@MainActor
final class LiveWorkout: NSObject, ObservableObject {
    static let shared = LiveWorkout()

    @Published private(set) var strain: Double = 0
    @Published private(set) var dayStrain: Double?
    @Published private(set) var calories: Double = 0
    @Published private(set) var avgHR: Double?
    @Published private(set) var maxHR: Int?
    @Published private(set) var zone: Int = 0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var distanceM: Double = 0
    @Published private(set) var location: CLLocationCoordinate2D?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var points: [RoutePoint] = []
    private var lastFix: CLLocation?
    private var hrSub: AnyCancellable?
    private var acc: Strain.Accumulator?
    private var restHR = 60.0
    private var maxHRUsed = 190.0
    private var profile = UserProfile()
    private var dayNetAtStart = 0.0
    private var lastBeat: Date?
    private var hrSum = 0.0
    private var hrWeight = 0.0
    private var recording = false
    private var tracking = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 4
        authorization = manager.authorizationStatus
    }

    // MARK: Location

    /// Map preview before the start: ask for "when in use" access and follow the position.
    func preview(routeTracking: Bool) {
        guard routeTracking else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if canLocate { manager.startUpdatingLocation() }
    }

    func stopPreview() {
        if !recording { manager.stopUpdatingLocation() }
    }

    private var canLocate: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    // MARK: Session

    /// Start (or resume after a relaunch) the live figures of `session`.
    func begin(_ session: LiveSession, day: DayMetrics?, profile: UserProfile, routeTracking: Bool) {
        guard !recording else { return }
        recording = true
        self.profile = profile
        restHR = day?.restingHRUsed ?? day?.rhr ?? 60
        maxHRUsed = day?.maxHRUsed ?? Double(profile.maxHROverride ?? Int(profile.tanakaMaxHR))
        acc = Strain.Accumulator(rest: restHR, maxHR: maxHRUsed, quietHRR: day?.quietHRR ?? Strain.defaultQuietHRR,
                                 female: profile.sex == .female)
        dayNetAtStart = Strain.netTrimp(forStrain: day?.strain ?? 0)
        dayStrain = day?.strain
        strain = 0
        calories = 0
        avgHR = nil
        maxHR = nil
        hrSum = 0
        hrWeight = 0
        lastBeat = nil
        points = []
        route = []
        distanceM = 0
        lastFix = nil
        hrSub = StrapManager.shared.live.$bpm
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bpm in
                guard let bpm else { return }
                let now = Date()
                Task { @MainActor in self?.absorb(bpm: bpm, at: now) }
            }
        tracking = routeTracking
        if routeTracking {
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            startTracking()
        }
    }

    /// Stop and hand back the route (nil when none was recorded).
    func finish() -> (route: [RoutePoint]?, distanceKm: Double?) {
        recording = false
        hrSub = nil
        acc = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        let r = points.count >= 2 ? points : nil
        return (r, r == nil ? nil : distanceM / 1000)
    }

    private func startTracking() {
        guard canLocate else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    private func absorb(bpm: Int, at now: Date) {
        guard recording, var a = acc else { return }
        // Weight each beat value by the time it covers (≈ 1 s), capped after a gap.
        let dt = min(5, lastBeat.map { now.timeIntervalSince($0) } ?? 1)
        lastBeat = now
        let hr = Double(bpm)
        a.add(hr, weight: dt / 60)
        acc = a
        strain = Strain.fromNetTrimp(a.net)
        dayStrain = Strain.fromNetTrimp(dayNetAtStart + a.net)
        calories += Strain.kcalForMinute(hr: hr, asleep: false, rest: restHR, maxHR: maxHRUsed, profile: profile).total * dt / 60
        hrSum += hr * dt
        hrWeight += dt
        avgHR = hrSum / max(1, hrWeight)
        maxHR = max(maxHR ?? 0, bpm)
        zone = Strain.zone(hr, maxHR: maxHRUsed)
    }

    var maxHRForZones: Double { maxHRUsed }
}

extension LiveWorkout: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.recording && self.tracking { self.startTracking() } else { manager.startUpdatingLocation() }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.absorb(loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func absorb(_ loc: CLLocation) {
        location = loc.coordinate
        guard recording, tracking, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 35 else { return }
        if let last = lastFix {
            let d = loc.distance(from: last)
            guard d >= 3 else { return }
            // Ignore GPS jumps faster than 25 m/s (90 km/h).
            let dt = max(1, loc.timestamp.timeIntervalSince(last.timestamp))
            if d / dt > 25 { return }
            distanceM += d
        }
        lastFix = loc
        points.append(RoutePoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, ts: Int(loc.timestamp.timeIntervalSince1970)))
        route.append(loc.coordinate)
    }
}
