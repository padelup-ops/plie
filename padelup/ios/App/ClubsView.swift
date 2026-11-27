import MapKit
import SwiftUI

struct ClubsView: View {
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var router: Router

    @State private var position: MapCameraPosition = .region(CoverageZone.overview)
    @State private var region = CoverageZone.overview
    @State private var visible: [Club] = []
    @State private var query = ""
    @State private var places: [PlaceSearch.Place] = []
    @State private var clubHits: [Club] = []
    @State private var filter: Filter = .all
    @State private var showList = false
    @State private var centeredOnUser = false

    enum Filter: String, CaseIterable { case all, bot, indoor, big
        var label: String {
            switch self {
            case .all: return "Tous"
            case .bot: return "Bot ⚡︎"
            case .indoor: return "Couverts"
            case .big: return "4 terrains +"
            }
        }
    }

    private var filtered: [Club] {
        switch filter {
        case .all: return visible
        case .bot: return visible.filter { $0.canBookWithBot }
        case .indoor: return visible.filter { $0.indoor > 0 }
        case .big: return visible.filter { $0.courts >= 4 }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                UserAnnotation()
                ForEach(filtered.prefix(250)) { club in
                    Annotation(club.displayName, coordinate: club.coordinate, anchor: .bottom) {
                        Button { router.openClub = club } label: { ClubPin(club: club) }
                            .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                reload()
                Task { await directory.refreshLive(region: context.region); reload() }
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                searchBar
                if !query.isEmpty && (!places.isEmpty || !clubHits.isEmpty) { searchResults }
                filters
                if !directory.liveStatus.isEmpty && query.isEmpty {
                    Text(directory.liveStatus).font(Neo.label(11)).foregroundStyle(Neo.dim)
                        .padding(.vertical, 6).padding(.horizontal, 12).background(Capsule().fill(.ultraThinMaterial))
                }
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showList) { listSheet.presentationDetents([.medium, .large]) }
        .onAppear { reload(); centerOnUserIfPossible() }
        .onChange(of: directory.revision) { _, _ in reload() }
        .onChange(of: location.location) { _, _ in centerOnUserIfPossible() }
    }

    private func reload() { visible = directory.clubs(in: region, limit: 400) }

    private func centerOnUserIfPossible() {
        guard !centeredOnUser, let loc = location.location else { return }
        centeredOnUser = true
        let r = MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
        position = .region(r)
        region = r
        reload()
    }

    private func go(latitude: Double, longitude: Double, spanKm: Double) {
        let deg = max(0.02, spanKm / 111)
        let r = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                   span: MKCoordinateSpan(latitudeDelta: deg, longitudeDelta: deg))
        withAnimation(.easeInOut(duration: 0.8)) { position = .region(r) }
        region = r
        query = ""
        places = []
        clubHits = []
        reload()
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Neo.cyan)
            TextField("Ville ou club… (Lyon, Bruxelles, Tunis)", text: $query)
                .font(Neo.body(15)).foregroundStyle(Neo.text).autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .onChange(of: query) { _, text in
                    clubHits = directory.search(text, near: location.location, limit: 6)
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        if text == query { await search() }
                    }
                }
            if !query.isEmpty {
                Button { query = ""; places = []; clubHits = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Neo.faint) }
            }
            Button { location.request(); centeredOnUser = false; centerOnUserIfPossible() } label: {
                Image(systemName: "location.fill").foregroundStyle(Neo.volt)
            }
        }
        .glassCard(radius: 18, padding: 12)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { places = []; return }
        let found = await PlaceSearch.search(text)
        if text == query.trimmingCharacters(in: .whitespaces) { places = found }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(places.prefix(4)) { p in
                Button { go(latitude: p.latitude, longitude: p.longitude, spanKm: p.spanKm) } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Neo.cyan)
                        VStack(alignment: .leading) {
                            Text(p.name).font(Neo.label(13)).foregroundStyle(Neo.text)
                            Text(p.detail).font(Neo.body(12)).foregroundStyle(Neo.dim)
                        }
                        Spacer()
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
            ForEach(clubHits.prefix(4)) { c in
                Button { router.openClub = c } label: {
                    HStack {
                        Image(systemName: "sportscourt.fill").foregroundStyle(Neo.volt)
                        VStack(alignment: .leading) {
                            Text(c.displayName).font(Neo.label(13)).foregroundStyle(Neo.text)
                            Text(c.city.isEmpty ? c.place : c.city).font(Neo.body(12)).foregroundStyle(Neo.dim)
                        }
                        Spacer()
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
        }
        .glassCard(radius: 18, padding: 12)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { filter = f } label: { Chip(text: f.label, selected: filter == f) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var bottomBar: some View {
        Button { showList = true } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                Text(filtered.isEmpty ? "Aucun club dans cette zone" : "\(filtered.count) clubs dans cette zone")
                Spacer()
                Text("\(directory.totalCount.formatted(.number.locale(Locale(identifier: "fr_FR")))) au total")
                    .font(Neo.label(11)).foregroundStyle(Neo.night.opacity(0.7))
            }
        }
        .buttonStyle(NeonButtonStyle(color: Neo.volt))
    }

    private var listSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { club in
                        Button { showList = false; router.openClub = club } label: {
                            ClubRow(club: club, distance: club.distance(from: location.location ?? CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .background(Neo.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Clubs de la zone")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ClubPin: View {
    var club: Club

    var body: some View {
        let color: Color = club.canBookWithBot ? Neo.volt : Neo.cyan
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Neo.night.opacity(0.85)).frame(width: 30, height: 30)
                Circle().strokeBorder(color, lineWidth: 2).frame(width: 30, height: 30)
                if club.courts > 1 {
                    Text("\(min(club.courts, 99))").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(color)
                } else {
                    Image(systemName: "sportscourt.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                }
            }
            .neonGlow(color, radius: 8)
            Rectangle().fill(color).frame(width: 2, height: 8)
        }
    }
}
