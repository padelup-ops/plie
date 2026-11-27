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
    @FocusState private var searching: Bool

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

    private var center: CLLocation { CLLocation(latitude: region.center.latitude, longitude: region.center.longitude) }

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
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                reload()
                Task { await directory.refreshLive(region: context.region); reload() }
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                searchBar
                if searching || (!query.isEmpty && (!places.isEmpty || !clubHits.isEmpty)) {
                    if !query.isEmpty { searchResults }
                } else {
                    filters
                }
                Spacer()
                if !searching { bottomPanel }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showList) { listSheet.presentationDetents([.medium, .large]).presentationBackground(UI.paper) }
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
        searching = false
        reload()
        Task { await directory.refreshLive(region: r); reload() }
    }

    // MARK: Recherche

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(UI.ink)
                TextField("Un club, une ville", text: $query)
                    .font(UI.body()).foregroundStyle(UI.ink).autocorrectionDisabled()
                    .focused($searching)
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
                    Button { query = ""; places = []; clubHits = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(UI.faint)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

            Button { location.request(); centeredOnUser = false; centerOnUserIfPossible() } label: {
                Image(systemName: "location").font(.system(size: 17, weight: .medium)).foregroundStyle(UI.ink)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.raised))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Autour de moi")
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { places = []; return }
        let found = await PlaceSearch.search(text)
        if text == query.trimmingCharacters(in: .whitespaces) { places = found }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !clubHits.isEmpty {
                Eyebrow(text: "Clubs").padding(.top, 4).padding(.bottom, 2)
                ForEach(Array(clubHits.prefix(4).enumerated()), id: \.element.id) { i, c in
                    Button { searching = false; router.openClub = c } label: {
                        ClubRow(club: c, distance: c.distance(from: location.location))
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
            if !places.isEmpty {
                Eyebrow(text: "Lieux").padding(.top, 12).padding(.bottom, 2)
                ForEach(places.prefix(4)) { p in
                    Button { go(latitude: p.latitude, longitude: p.longitude, spanKm: p.spanKm) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin").font(.system(size: 15)).foregroundStyle(UI.muted).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink)
                                Text(p.detail).font(UI.caption()).foregroundStyle(UI.muted)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(UI.faint)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .surface(padding: 14)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { withAnimation(.snappy(duration: 0.2)) { filter = f } } label: {
                        Chip(text: f.label, systemImage: f == .bot ? "circle.fill" : nil, active: filter == f)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Panneau du bas : combien de clubs ici, les plus proches, la liste

    private var bottomPanel: some View {
        let nearest = filtered.sorted { $0.location.distance(from: center) < $1.location.distance(from: center) }.prefix(2)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(filtered.isEmpty ? "Aucun club ici" : "\(filtered.count) club\(filtered.count > 1 ? "s" : "") ici")
                    .font(UI.title(18)).foregroundStyle(UI.ink)
                Spacer()
                if !directory.liveStatus.isEmpty {
                    Text(directory.liveStatus).font(UI.small()).foregroundStyle(UI.muted).lineLimit(1)
                } else if !filtered.isEmpty {
                    Button("Liste") { showList = true }.buttonStyle(LinkButtonStyle())
                }
            }
            .padding(.bottom, nearest.isEmpty ? 0 : 4)
            ForEach(Array(nearest.enumerated()), id: \.element.id) { i, club in
                if i > 0 { Hairline() }
                Button { router.openClub = club } label: { ClubRow(club: club, distance: location.location.map { club.location.distance(from: $0) }) }
                    .buttonStyle(.plain)
            }
        }
        .surface(padding: 16)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private var listSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.sorted { $0.location.distance(from: center) < $1.location.distance(from: center) }.enumerated()), id: \.element.id) { i, club in
                        Button { showList = false; router.openClub = club } label: {
                            ClubRow(club: club, distance: club.distance(from: location.location ?? center), index: i + 1)
                        }
                        .buttonStyle(.plain)
                        Hairline(inset: 38)
                    }
                }
                .padding(.horizontal, UI.margin)
            }
            .background(UI.paper.ignoresSafeArea())
            .navigationTitle("\(filtered.count) clubs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Repère de club : encre (nombre de terrains) ; jaune balle quand on peut réserver en ligne.
struct ClubPin: View {
    var club: Club

    var body: some View {
        let bookable = club.canBookWithBot
        ZStack {
            Circle().fill(bookable ? UI.ball : UI.ink)
            if club.courts > 1 {
                Text("\(min(club.courts, 99))").font(.system(size: 11, weight: .bold).width(.condensed))
                    .foregroundStyle(bookable ? UI.onBall : UI.paper)
            } else {
                Circle().fill(bookable ? UI.onBall : UI.paper).frame(width: 6, height: 6)
            }
        }
        .frame(width: 26, height: 26)
        .overlay(Circle().strokeBorder(bookable ? UI.onBall.opacity(0.8) : UI.paper, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .accessibilityLabel(club.displayName)
    }
}
