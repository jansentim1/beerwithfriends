import BeerKit
import CoreLocation
import Foundation
import MapKit

// COMPILE-PARKED (Task 11): no Xcode on this machine — written against the
// iOS 17 SDK (CoreLocation + MapKit) under Swift 6 concurrency, not yet compiled.

/// Opt-in place naming for a logged beer: one coarse fix, turned into a short
/// human name ("Café De Zon", "Amsterdam") plus that PLACE's coordinate, with
/// the fix itself thrown away.
///
/// Contract (see `PlaceProviding` in BeerKit): never longer than a few seconds,
/// never a reason a beer fails to log, `nil` whenever the switch is off, the
/// permission is missing, or nothing sensible was found in time. Coordinates
/// live only inside a single `currentPlace()` call — they are never stored on
/// the instance, written to defaults, or logged (not even inside error text,
/// which is why failures are swallowed silently). The only coordinate that ever
/// leaves is the bar's or the city's, rounded to ~100 m by `Coordinate`.
///
/// Threading: every `CLLocationManager` touch happens on the main actor (the
/// manager is created there, so its delegate callbacks arrive there too), while
/// the waiting side can be any background task. The two meet through
/// lock-guarded continuation lists, so the class is safe to call repeatedly,
/// concurrently, and from anywhere.
final class LocationPlaceProvider: NSObject, PlaceProviding, CLLocationManagerDelegate, @unchecked Sendable {
    /// One instance: Settings triggers the prompt on it, HomeViewModel asks it
    /// for a name. A second manager would mean a second system prompt.
    static let shared = LocationPlaceProvider()

    /// Mirrors `@AppStorage("sharePlace")` in SettingsView — the master switch.
    static let sharePlaceKey = "sharePlace"

    /// Whole-lookup budget. The beer row is already on screen; this is the most
    /// we are willing to delay the write behind it.
    private static let overallTimeout: Double = 3
    /// Watchdogs, both inside the budget above, so a callback that never comes
    /// still releases the waiter instead of leaking a suspended task.
    private static let fixTimeout: Double = 2.2
    private static let authorizationTimeout: Double = 2.5
    /// A bar 120 m away is plausibly the bar you are in; 500 m is a guess.
    private static let poiRadius: CLLocationDistance = 120

    private let lock = NSLock()
    /// Main-actor only (created and read there).
    private var _manager: CLLocationManager?
    /// Everything below is lock-guarded.
    private var locationWaiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    /// True while one `requestLocation()` is outstanding: concurrent callers
    /// share that single fix rather than cancelling each other's.
    private var isRequestingFix = false

    // MARK: - PlaceProviding

    func currentPlace() async -> PlaceResult? {
        guard UserDefaults.standard.bool(forKey: Self.sharePlaceKey) else { return nil }
        // Timeout.run returns nil on timeout, and the operation itself returns an
        // optional result — hence the double optional, flattened here.
        let resolved: PlaceResult?? = await BeerKit.Timeout.run(seconds: Self.overallTimeout) { [self] in
            await resolvePlace()
        }
        return resolved ?? nil
    }

    /// Read-only: is when-in-use already granted? The Map tab shows the blue
    /// user dot only when it is, and asks nothing when it isn't. Goes through the
    /// one shared manager on purpose — a second CLLocationManager would be a
    /// second system prompt waiting to happen.
    @MainActor
    var isLocationAuthorized: Bool {
        switch sharedManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Asks for when-in-use permission, but only when the user has never been
    /// asked. Called the moment the Settings switch goes on, so the system
    /// prompt lands next to the explanation instead of on the log button.
    func requestPermissionIfNeeded() {
        Task { @MainActor [self] in
            let manager = sharedManager()
            guard manager.authorizationStatus == .notDetermined else { return }
            manager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Resolution

    private func resolvePlace() async -> PlaceResult? {
        // Documented as slow on the main thread; we are on a background task.
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        var status = await currentAuthorizationStatus()
        guard status != .denied, status != .restricted else { return nil }
        if status == .notDetermined {
            status = await requestAuthorizationAndWait()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        guard let coordinate = await awaitLocationFix() else { return nil }
        // The coordinate that leaves this class is ALWAYS the place's, never the
        // device fix above: the POI's own coordinate, or the one the reverse
        // geocoder gives for the city. `Coordinate` rounds it to ~100 m again.
        if let poi = await nearbyPointOfInterest(near: coordinate) {
            guard let name = shortened(poi.name) else { return nil }
            return PlaceResult(name: name, coordinate: poi.coordinate)
        }
        guard let city = await cityPlace(near: coordinate), let name = shortened(city.name) else {
            return nil
        }
        return PlaceResult(name: name, coordinate: city.coordinate)
    }

    /// The bar itself, when there is one within `poiRadius` — filtered to places
    /// you would actually be drinking in, so a dentist next door never wins.
    private func nearbyPointOfInterest(
        near coordinate: CLLocationCoordinate2D
    ) async -> (name: String, coordinate: Coordinate)? {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: Self.poiRadius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .brewery, .cafe, .restaurant, .nightlife, .winery, .bakery, .foodMarket
        ])
        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearest = response.mapItems.min { lhs, rhs in
                distance(from: origin, to: lhs) < distance(from: origin, to: rhs)
            }
            // Nameless (or no) match: fall through to the city, exactly as before.
            guard let nearest, let name = nearest.name else { return nil }
            let spot = nearest.placemark.coordinate
            return (name, Coordinate(latitude: spot.latitude, longitude: spot.longitude))
        } catch {
            // Silent by design: MapKit errors can echo the query location.
            return nil
        }
    }

    private func distance(from origin: CLLocation, to item: MKMapItem) -> CLLocationDistance {
        item.placemark.location?.distance(from: origin) ?? .greatestFiniteMagnitude
    }

    /// Fallback when no drinking spot is nearby: just the city.
    private func cityPlace(
        near coordinate: CLLocationCoordinate2D
    ) async -> (name: String, coordinate: Coordinate?)? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            guard let name = placemark.locality ?? placemark.subLocality ?? placemark.administrativeArea
            else { return nil }
            // The city's own centre as the geocoder reports it — nil rather than
            // the device fix when it has none.
            let centre = placemark.location?.coordinate
            return (name, centre.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) })
        } catch {
            return nil
        }
    }

    /// Trimmed, length-capped, and nil rather than blank — the feed row prints
    /// this straight after a pin glyph.
    private func shortened(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(BeerLog.placeMaxLength))
    }

    // MARK: - Authorization

    @MainActor
    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        sharedManager().authorizationStatus
    }

    /// Prompts and waits for the user's answer. Runs entirely on the main actor
    /// so the waiter is installed before `requestWhenInUseAuthorization()` can
    /// call back — the delegate arrives on this same actor, so no answer is
    /// missed. Bounded: the watchdog reports the status as it stands.
    @MainActor
    private func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        let manager = sharedManager()
        guard manager.authorizationStatus == .notDetermined else { return manager.authorizationStatus }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLAuthorizationStatus, Never>) in
            lock.lock()
            authorizationWaiters.append(continuation)
            lock.unlock()
            scheduleWatchdog(seconds: Self.authorizationTimeout) { [self] in
                finishAuthorization(with: .notDetermined)
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    private func finishAuthorization(with status: CLAuthorizationStatus) {
        lock.lock()
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        lock.unlock()
        for waiter in waiters { waiter.resume(returning: status) }
    }

    // MARK: - One location fix

    private func awaitLocationFix() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            lock.lock()
            locationWaiters.append(continuation)
            let needsStart = !isRequestingFix
            isRequestingFix = true
            lock.unlock()

            // Always armed. Core Location calls back exactly once per
            // requestLocation() — but if it ever didn't, an un-resumed
            // continuation would hang the beer's place lookup forever.
            scheduleWatchdog(seconds: Self.fixTimeout) { [self] in finishFix(with: nil) }
            if needsStart {
                Task { @MainActor [self] in startFix() }
            }
        }
    }

    @MainActor
    private func startFix() {
        let manager = sharedManager()
        // Naming a bar or a city needs a block, not a doorway: coarse accuracy is
        // both enough and cheaper on the battery.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()
    }

    private func finishFix(with coordinate: CLLocationCoordinate2D?) {
        lock.lock()
        let waiters = locationWaiters
        locationWaiters.removeAll()
        // Cleared on the watchdog path too: a stuck flag would stop every later
        // lookup from ever starting a fix. The cost is that a late callback can
        // hand its result to the next caller — a fix a few seconds stale.
        isRequestingFix = false
        lock.unlock()
        for waiter in waiters { waiter.resume(returning: coordinate) }
    }

    /// Unstructured on purpose: it must fire even when the caller's task was
    /// cancelled (that is precisely when a waiter would otherwise be stranded).
    private func scheduleWatchdog(seconds: Double, _ finish: @escaping @Sendable () -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            finish()
        }
    }

    // MARK: - Manager

    /// Created lazily on the main actor: the delegate callbacks are then
    /// delivered on the main run loop, which is what makes the
    /// install-then-prompt ordering above race-free.
    @MainActor
    private func sharedManager() -> CLLocationManager {
        if let existing = _manager { return existing }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        _manager = manager
        return manager
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Only the coordinate crosses over, and only for this one lookup.
        finishFix(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Not logged: Core Location errors can carry the region being resolved.
        finishFix(with: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        finishAuthorization(with: manager.authorizationStatus)
    }
}
