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

    /// The tab keeps its own small feed copy rather than a second HomeViewModel:
    /// the map needs the snapshot and nothing else (no cheers, no photo state).
    @State private var beers: [BeerLog] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: ClusterSelection?
    @State private var showsUserLocation = false
    /// Flipped by onAppear/onDisappear. `.task(id:)` keys off it, so exactly one
    /// feed subscription is alive while the tab is on screen and none behind it —
    /// a Firestore listener is not free, and TabView keeps this view alive.
    @State private var isOnScreen = false

    @ScaledMetric(relativeTo: .subheadline) private var glassHeight: CGFloat = 28

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

    /// One pin: a 36 pt amber-washed glass on a surface disc (a wash on a surface
    /// card, per the No-Shadow Rule), the newest drinker's initials, and a count
    /// when several mates share the spot.
    private func marker(for cluster: DrinkCluster) -> some View {
        let newest = cluster.newest
        return Button {
            Haptics.light()
            selection = ClusterSelection(id: cluster.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle().fill(Theme.accentSoft)
                    }
                    .overlay {
                        Text(newest.drink.emoji)
                            .font(.system(size: 18))
                    }
                    .overlay(alignment: .topTrailing) {
                        if cluster.beers.count > 1 {
                            Text("\(cluster.beers.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.onAccent)
                                .frame(width: 18, height: 18)
                                .background(Theme.accent, in: Circle())
                                .offset(x: 5, y: -5)
                        }
                    }

                AvatarView(name: displayName(for: newest), size: 20)
                    .offset(x: 6, y: 2)
            }
            // The paint is 36 pt; the target is 44 (the 44-Point Rule).
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cluster.accessibilityLabel(myUid: profile.id))
        .accessibilityHint("Shows who is drinking here")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No mates on the map yet.")
                .font(Theme.displayTitle2)
                .multilineTextAlignment(.center)
            Text("Turn on 'Share where I'm drinking' in Settings and log a drink.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: 340)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .padding(24)
        .accessibilityElement(children: .combine)
        // The card explains, it doesn't catch: pans and pinches still reach the map.
        .allowsHitTesting(false)
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
                Text("\(beer.drink.emoji) \(beer.drink.label)")
                    .font(.subheadline)
                if let place = beer.place, !place.isEmpty {
                    Text("📍 \(place)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(beer.createdAt, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            glassLevel(for: beer)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calloutAccessibilityLabel(for: beer, name: name))
    }

    /// How much is left in the glass: it drains over the beer's 24 hours.
    private func glassLevel(for beer: BeerLog) -> some View {
        let level = beer.fillLevel(now: Date())
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.accent)
                .frame(height: max(2, glassHeight * level))
        }
        .frame(width: glassHeight * 0.5, height: glassHeight)
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
            }
        } catch {
            // Nothing to say here; the pins simply stop updating.
        }
    }

    // MARK: - Clustering

    /// Active, located beers grouped by place, newest group first. `Coordinate`
    /// is already rounded to ~100 m, so two mates in the same bar land on one pin.
    private var clusters: [DrinkCluster] {
        let now = Date()
        let located = beers
            .filter { $0.expiresAt > now && $0.placeCoordinate != nil }
            .sorted { $0.createdAt > $1.createdAt }
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
