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
            case .bot: return "Réservables"
            case .indoor: return "Couverts"
            case .big: return "4 terrains et +"
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
                    Annotation(club.displayName, coordinate: club.coordinate, anchor: .center) {
                        Button { router.openClub = club } label: { ClubPin(club: club) }.buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                reload()
                Task { await directory.refreshLive(region: context.region); reload() }
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                searchBar
                if !query.isEmpty && (!places.isEmpty || !clubHits.isEmpty) { searchResults }
                else { filters }
                if !directory.liveStatus.isEmpty && query.isEmpty {
                    Text(directory.liveStatus).font(UI.small()).foregroundStyle(UI.muted)
                        .padding(.vertical, 6).padding(.horizontal, 12).background(Capsule().fill(UI.card))
                        .overlay(Capsule().strokeBorder(UI.line, lineWidth: 0.5))
                }
                Spacer()
                Button { showList = true } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text(filtered.isEmpty ? "Aucun club dans cette zone" : "\(filtered.count) clubs dans cette zone")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
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
        let r = MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.45))
        position = .region(r)
        region = r
        reload()
    }

    private func go(latitude: Double, longitude: Double, spanKm: Double) {
        let deg = max(0.04, min(spanKm, 60) / 111)
        let r = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                   span: MKCoordinateSpan(latitudeDelta: deg, longitudeDelta: deg * 1.3))
        withAnimation(.easeInOut(duration: 0.6)) { position = .region(r) }
        region = r
        query = ""
        places = []
        clubHits = []
        reload()
        Task { await directory.refreshLive(region: r); reload() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(UI.muted)
            TextField("Ville ou club (Lille, Genève, Tunis…)", text: $query)
                .font(UI.body()).foregroundStyle(UI.ink).autocorrectionDisabled()
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
                Button { query = ""; places = []; clubHits = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(UI.faint) }
            }
            Button { location.request(); centeredOnUser = false; centerOnUserIfPossible() } label: {
                Image(systemName: "location.fill").foregroundStyle(UI.accent)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Capsule().fill(UI.card))
        .overlay(Capsule().strokeBorder(UI.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
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
                    HStack(spacing: 12) {
                        Image(systemName: "mappin").foregroundStyle(UI.muted).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                            Text(p.detail).font(UI.caption()).foregroundStyle(UI.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            ForEach(clubHits.prefix(4)) { c in
                Button { router.openClub = c } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sportscourt").foregroundStyle(UI.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                            Text(c.city.isEmpty ? c.source.label : c.city).font(UI.caption()).foregroundStyle(UI.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .card(padding: 12)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { filter = f } label: { Pill(text: f.label, active: filter == f) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var listSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { club in
                        Button { showList = false; router.openClub = club } label: {
                            ClubRow(club: club, distance: club.distance(from: location.location ?? CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)))
                        }.buttonStyle(.plain)
                        Divider().overlay(UI.line).padding(.leading, 62)
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(UI.bg.ignoresSafeArea())
            .navigationTitle("Clubs de la zone")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ClubPin: View {
    var club: Club

    var body: some View {
        let color: Color = club.canBookWithBot ? UI.accent : Color(white: 0.45)
        ZStack {
            Circle().fill(color)
            if club.courts > 1 {
                Text("\(min(club.courts, 99))").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
            } else {
                Circle().fill(.white).frame(width: 7, height: 7)
            }
        }
        .frame(width: 26, height: 26)
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}
