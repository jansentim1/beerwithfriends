import BeerKit
import CoreLocation
import Foundation
import MapKit
import SwiftUI

// COMPILE-PARKED (Task 12): no Xcode on this machine — written against the
// iOS 17 SDK (SwiftUI Map, Annotation, mapControls) under Swift 6 concurrency,
// not yet compiled.

/// The Map tab: where your mates are drinking right now.
///
/// Consumes ONLY BeerKit (`BeerServicing`, models) plus the shared
/// `LocationPlaceProvider` for a read-only permission check. Pins are the
/// *places* mates logged from (`BeerLog.placeCoordinate`, already rounded to
/// ~100 m by `Coordinate`) — never a device fix, and only for beers whose owner
/// opted in. Nothing here asks for a permission: the blue dot appears only if
/// when-in-use was already granted, and the system's own user-location button
/// handles the rest.
struct MapView: View {
    private let profile: UserProfile
    private let beerService: any BeerServicing
    /// Read-only here; the feed is what starts a drink's two hours.
    private let seenStore: any SeenStoring = DefaultsSeenStore()
    /// The same switch as Settings → Privacy; the empty state can flip it.
    @AppStorage(LocationPlaceProvider.sharePlaceKey) private var sharePlace = false

    /// The tab keeps its own small feed copy rather than a second HomeViewModel:
    /// the map needs the snapshot and nothing else (no cheers, no photo state).
    @State private var beers: [BeerLog] = []
    /// Opens on the Netherlands rather than a whole-globe `.automatic` view: with
    /// no pins and no blue dot, `.automatic` has nothing to frame and lands on a
    /// view of the planet. Replaced by a region around the pins the moment there
    /// are any — see `frameFirstPins()`.
    @State private var position: MapCameraPosition = MapView.defaultPosition
    /// Set once, the first time pins arrive, so re-framing never yanks a camera
    /// the user has since panned.
    @State private var hasFramedPins = false
    @State private var selection: ClusterSelection?
    @State private var showsUserLocation = false
    /// Flipped by onAppear/onDisappear. `.task(id:)` keys off it, so exactly one
    /// feed subscription is alive while the tab is on screen and none behind it —
    /// a Firestore listener is not free, and TabView keeps this view alive.
    @State private var isOnScreen = false

    init(profile: UserProfile, beerService: any BeerServicing) {
        self.profile = profile
        self.beerService = beerService
    }

    var body: some View {
        NavigationStack {
            mapSurface
                .navigationTitle("Map")
                .navigationBarTitleDisplayMode(.large)
        }
        // Cancels on the way out (isOnScreen false) and resubscribes on the way
        // back in — which also re-snapshots the friend list, exactly as Home's
        // scene-phase restart does.
        .task(id: isOnScreen) {
            guard isOnScreen else { return }
            syncLocationAuthorization()
            await observeFeed()
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .sheet(item: $selection) { selection in
            calloutSheet(for: selection)
        }
    }

    // MARK: - Map

    private var mapSurface: some View {
        let clusters = self.clusters
        return Map(position: $position) {
            if showsUserLocation {
                UserAnnotation()
            }
            ForEach(clusters) { cluster in
                Annotation(cluster.title, coordinate: cluster.clCoordinate, anchor: .center) {
                    marker(for: cluster)
                }
            }
        }
        // Flat standard: the system swaps to the dark map in dark mode by itself.
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay {
            if clusters.isEmpty {
                emptyState
            }
        }
    }

    /// One pin: the drawn glass of whoever poured last, on a 48 pt amber wash
    /// over a surface disc (a wash on a card, per the No-Shadow Rule), plus a
    /// count when several mates share the spot. No initials badge — at 20 pt the
    /// letters are 8 pt and unreadable, and the callout names everyone here.
    ///
    /// 48 and not 36: testers could not find the pin on a map zoomed out past a
    /// city ("embleempje mag wat groter", 2026-10-03). The proportions are the
    /// old ones scaled, so the glass still reads as the feed's glass.
    private func marker(for cluster: DrinkCluster) -> some View {
        let newest = cluster.newest
        return Button {
            Haptics.light()
            selection = ClusterSelection(id: cluster.id)
        } label: {
            Circle()
                .fill(Theme.surface)
                .frame(width: 60, height: 60)
                .overlay {
                    Circle().fill(Theme.accentSoft)
                }
                .overlay {
                    // The glass drains with the beer, exactly as in the feed.
                    DrinkGlassView(kind: newest.drink, level: newest.fillLevel(now: Date()), size: 38)
                }
                .overlay(alignment: .topTrailing) {
                    if cluster.beers.count > 1 {
                        Text("\(cluster.beers.count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 22, height: 22)
                            .background(Theme.accent, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                // 60 pt: a pin has to carry a drawn glass and read at a glance on
                // a map, which 36 and then 48 still did not (Tim, twice). Paint
                // and target are the one circle; the badge overhangs it.
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cluster.accessibilityLabel(myUid: profile.id))
        .accessibilityHint("Shows who is drinking here")
    }

    /// The map is empty far more often than it should be, because the setting
    /// that fills it is off by default and lives three taps away in Settings
    /// (Tim, 2026-09-21). So the card turns it on where you are standing.
    private var emptyState: some View {
        VStack(spacing: 10) {
            // The words let pans and pinches through to the map; only the
            // button below catches a touch.
            Text("No mates on the map yet")
                .font(Theme.displayTitle2)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
            Text(sharePlace
                 ? "You'll show up here when you log a drink. Mates need their own switch on to appear."
                 : "Only drinks logged with ‘Share where I’m drinking’ on show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)

            if !sharePlace {
                Button {
                    Haptics.light()
                    sharePlace = true
                    // Exactly what the Settings switch does: ask here, where the
                    // sentence above is the explanation.
                    LocationPlaceProvider.shared.requestPermissionIfNeeded()
                } label: {
                    Text("Put me on the map")
                }
                .buttonStyle(PillButtonStyle(emphasis: .tinted))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("map.sharePlace")
                .accessibilityHint("Turns on sharing the bar you're drinking at")
                .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: 340)
        // Material, not a surface card: this one floats over the map, and the
        // blur is what keeps the streets underneath from fighting the words.
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
                .allowsHitTesting(false)
        }
        .padding(24)
        .animation(Theme.quick, value: sharePlace)
    }

    // MARK: - Callout

    /// The tapped pin's story. Looked up live by id rather than captured, so a
    /// fresh snapshot (a new mate arriving, a beer expiring) keeps it honest.
    @ViewBuilder
    private func calloutSheet(for selection: ClusterSelection) -> some View {
        let cluster = clusters.first { $0.id == selection.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let cluster {
                    Text(cluster.title)
                        .font(Theme.displayTitle2)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(cluster.beers.enumerated()), id: \.element.id) { index, beer in
                        if index > 0 { Divider() }
                        calloutRow(beer)
                    }
                } else {
                    // The last beer here expired while the sheet was open.
                    Text("That round has finished.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A single mate fits the small detent; a busy bar can be dragged up.
        .presentationDetents([.fraction(0.25), .medium])
        .presentationDragIndicator(.visible)
    }

    private func calloutRow(_ beer: BeerLog) -> some View {
        let isMine = beer.ownerUid == profile.id
        let name = isMine ? "You" : beer.ownerName
        return HStack(alignment: .center, spacing: 12) {
            AvatarView(name: displayName(for: beer), size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(beer.drink.label)
                    .font(.subheadline)
                if let place = beer.place, !place.isEmpty {
                    Text("📍 \(place)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                // `style: .relative` spells this out as "5 hrs, 50 min"; the feed
                // says "5 h". Same formatter, so the two can never drift.
                Text(HomeView.relativeLabel(beer.createdAt, now: Date()))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            glass(for: beer)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calloutAccessibilityLabel(for: beer, name: name))
    }

    /// How much is left in the glass: it drains over the drink's first 15 minutes. The
    /// drawn glass, not an abstract bar — the same object the feed shows.
    private func glass(for beer: BeerLog) -> some View {
        let level = beer.fillLevel(now: Date())
        return DrinkGlassView(kind: beer.drink, level: level, size: 32)
            .accessibilityHidden(true)
    }

    private func calloutAccessibilityLabel(for beer: BeerLog, name: String) -> String {
        var parts = [name, beer.drink.label]
        if let place = beer.place, !place.isEmpty { parts.append("at \(place)") }
        parts.append(beer.createdAt.formatted(.relative(presentation: .named)))
        parts.append("glass \(Int((beer.fillLevel(now: Date()) * 100).rounded())) percent full")
        return parts.joined(separator: ", ")
    }

    private func displayName(for beer: BeerLog) -> String {
        beer.ownerUid == profile.id ? profile.displayName : beer.ownerName
    }

    // MARK: - Feed

    @MainActor
    private func syncLocationAuthorization() {
        // Read-only: asking here would put a system prompt on a tab switch.
        showsUserLocation = LocationPlaceProvider.shared.isLocationAuthorized
    }

    /// One subscription for as long as the tab is on screen. Errors are silent on
    /// purpose: Home owns the "lost your feed" message, and coming back to this
    /// tab resubscribes anyway.
    @MainActor
    private func observeFeed() async {
        do {
            for try await logs in beerService.observeFeed() {
                beers = logs
                frameFirstPins()
            }
        } catch {
            // Nothing to say here; the pins simply stop updating.
        }
    }

    // MARK: - Camera

    /// Where the map opens with nothing to show: the Netherlands, whole.
    /// Computed rather than a `static let`, so nothing here depends on
    /// `MapCameraPosition` being `Sendable` under Swift 6.
    private static var defaultPosition: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 52.2, longitude: 5.3),
                span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.5)
            )
        )
    }

    /// Zoom bounds for the first framing, in degrees of latitude/longitude.
    ///
    /// `.automatic` used to do this job and opened Ireland-to-Tunisia for a
    /// single drink in Noord-Holland (tester screenshot, 2026-10-03): with one
    /// coordinate and no blue dot it has no extent to fit, so it falls back to a
    /// continent. A lone pin belongs at a street you could walk, hence the floor;
    /// the ceiling keeps mates two countries apart on one screen instead of
    /// framing them so wide that every pin is a speck again.
    private static let minimumFramingSpan = 0.03
    private static let maximumFramingSpan = 6.0
    /// Extra breathing room around the pins, as a fraction of their extent, so no
    /// pin is painted half off the edge it defines.
    private static let framingMargin = 0.4

    /// The box every pin fits in, padded and clamped. `nil` with no pins, which
    /// is what keeps `defaultPosition` on screen until there is something to frame.
    private static func framingRegion(for coordinates: [Coordinate]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: clampedSpan(maxLatitude - minLatitude),
                longitudeDelta: clampedSpan(maxLongitude - minLongitude)
            )
        )
    }

    private static func clampedSpan(_ extent: Double) -> Double {
        min(maximumFramingSpan, max(minimumFramingSpan, extent * (1 + framingMargin)))
    }

    /// The first snapshot that has pins frames them. Once only: after that the
    /// camera belongs to whoever is panning it.
    @MainActor
    private func frameFirstPins() {
        guard !hasFramedPins,
              let region = Self.framingRegion(for: clusters.map(\.coordinate)) else { return }
        hasFramedPins = true
        withAnimation(Theme.spring) { position = .region(region) }
    }

    // MARK: - Clustering

    /// Each mate's newest live drink, the located ones grouped by place, newest
    /// group first. `Coordinate` is already rounded to ~100 m, so two mates in
    /// the same bar land on one pin.
    private var clusters: [DrinkCluster] {
        // The same clock the feed reads against, so a drink that has faded from
        // the feed is not still pinned here. The map only READS it: seeing a pin
        // must not burn the two hours on a drink you never opened the feed for.
        let ids = beers.map(\.id)
        let located = BeerLog.latestPerOwner(beers, now: Date(), seenAt: seenStore.seenAt(ids: ids))
            .filter { $0.placeCoordinate != nil }
        var order: [String] = []
        var grouped: [String: [BeerLog]] = [:]
        for beer in located {
            guard let coordinate = beer.placeCoordinate else { continue }
            let key = Self.key(for: coordinate)
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(beer)
        }
        return order.compactMap { key in
            guard let beers = grouped[key], let coordinate = beers.first?.placeCoordinate else { return nil }
            return DrinkCluster(id: key, coordinate: coordinate, beers: beers)
        }
    }

    /// `Coordinate` rounds to three decimals, so the thousandths are whole
    /// numbers: an integer key, no formatter and no locale in the way.
    private static func key(for coordinate: Coordinate) -> String {
        let lat = Int((coordinate.latitude * 1000).rounded())
        let lon = Int((coordinate.longitude * 1000).rounded())
        return "\(lat)_\(lon)"
    }

    // MARK: - Types

    /// One pin: every active beer logged at the same place, newest first.
    private struct DrinkCluster: Identifiable {
        let id: String
        let coordinate: Coordinate
        let beers: [BeerLog]

        var newest: BeerLog { beers[0] }
        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        /// The pin's caption: the shared place name, or the drinker when a beer
        /// somehow carries a coordinate without one.
        var title: String {
            if let place = newest.place, !place.isEmpty { return place }
            return newest.ownerName
        }

        func accessibilityLabel(myUid: String) -> String {
            let names = beers.map { $0.ownerUid == myUid ? "You" : $0.ownerName }
            let who: String
            switch names.count {
            case 1: who = names[0]
            case 2: who = "\(names[0]) and \(names[1])"
            default: who = "\(names[0]) and \(names.count - 1) more"
            }
            if let place = newest.place, !place.isEmpty {
                return "\(who), \(newest.drink.label) at \(place)"
            }
            return "\(who), \(newest.drink.label)"
        }
    }

    /// The sheet binds to an id, not a snapshot: the cluster itself is re-read
    /// from the live feed every time the sheet's body runs.
    private struct ClusterSelection: Identifiable { let id: String }
}
