// Search.swift — Vicefold
//
// La recherche générale : guides, missions, lieux, véhicules, easter eggs, personnages, objets et codes de triche,
// d'un seul geste. Sans accent ni majuscule (« defi » trouve « Défi »), et sans spoiler : ce qui est masqué ne se
// trouve pas par son nom. Un lieu trouvé s'ouvre sur la carte.

import SwiftUI

struct SearchView: View {
    /// Appelé quand un lieu est choisi (la feuille de recherche se ferme : on part sur la carte).
    var onPlace: (() -> Void)?
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var vehicles = VehicleStore.shared
    @State private var query = ShotMode.route == "search" ? "Vice" : ""
    @State private var scope: Scope = .all

    enum Scope: String, CaseIterable, Identifiable {
        case all, guides, missions, places, vehicles, eggs, characters, collectibles, cheats
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .guides: return "Guides"
            case .missions: return "Missions"
            case .places: return "Places"
            case .vehicles: return "Vehicles"
            case .eggs: return "Easter eggs"
            case .characters: return "Characters"
            case .collectibles: return "Collectibles"
            case .cheats: return "Cheat codes"
            }
        }
        var icon: String {
            switch self {
            case .all: return "magnifyingglass"
            case .guides: return "book.pages.fill"
            case .missions: return "flag.fill"
            case .places: return "mappin.and.ellipse"
            case .vehicles: return "car.side.fill"
            case .eggs: return "oval.portrait.fill"
            case .characters: return "person.2.fill"
            case .collectibles: return "sparkles"
            case .cheats: return "gamecontroller.fill"
            }
        }
        var color: Color {
            switch self {
            case .all: return VF.flamingo
            case .guides: return VF.sun
            case .missions: return VF.flamingo
            case .places: return VF.cyan
            case .vehicles: return VF.palm
            case .eggs: return VF.cyan
            case .characters: return VF.sky
            case .collectibles: return VF.sun
            case .cheats: return Color(red: 0.80, green: 0.58, blue: 1.0)
            }
        }
    }

    private struct Results {
        var guides: [VFGuide] = []
        var missions: [VFMission] = []
        var places: [VFPlace] = []
        var vehicles: [VFVehicle] = []
        var eggs: [VFEgg] = []
        var characters: [VFCharacter] = []
        var collectibles: [VFCollectibleSet] = []
        var cheats: [VFCheat] = []

        func count(_ s: Scope) -> Int {
            switch s {
            case .all: return guides.count + missions.count + places.count + vehicles.count + eggs.count + characters.count + collectibles.count + cheats.count
            case .guides: return guides.count
            case .missions: return missions.count
            case .places: return places.count
            case .vehicles: return vehicles.count
            case .eggs: return eggs.count
            case .characters: return characters.count
            case .collectibles: return collectibles.count
            case .cheats: return cheats.count
            }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private func m(_ s: String?) -> Bool {
        guard let s else { return false }
        return s.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func search() -> Results {
        let c = content.content
        var r = Results()
        // Un guide masqué se trouve par son titre (visible dans la liste), pas par son texte.
        r.guides = c.guides.filter { m($0.title) || (!progress.hidden($0.spoiler) && (m($0.summary) || m($0.body))) }
        r.missions = c.missions.filter { !progress.hidden($0.chapter) && (m($0.title) || m($0.giver) || m($0.location) || m($0.walkthrough)) }
        r.places = c.places.filter { $0.kind != .region && !progress.hidden($0.spoiler) && (m($0.name) || m($0.real)) }
        r.vehicles = vehicles.list.vehicles.filter { m($0.name) || m($0.maker) }
        r.eggs = c.eggs.filter { !progress.hidden($0.spoiler) && (m($0.title) || m($0.area) || m($0.summary)) }
        r.characters = c.characters.filter { !progress.hidden($0.spoiler) && (m($0.name) || m($0.role)) }
        r.collectibles = c.collectibles.filter { m($0.title) || m($0.summary) }
        r.cheats = c.cheats.filter { m($0.name) || m($0.effect) }
        return r
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if trimmed.count >= 2 {
                        let r = search()
                        if r.count(.all) == 0 {
                            Section {
                                VFEmptyState(icon: "magnifyingglass", title: "Nothing found", message: "Try another word. Anything past your chapter stays hidden.")
                                    .listRowBackground(Color.clear)
                            }
                        } else {
                            Section { scopes(r) }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            sections(r)
                        }
                    } else {
                        Section {
                            VFEmptyState(icon: "magnifyingglass", title: "Search", message: "Search guides, missions, places, vehicles, easter eggs, characters and cheat codes.")
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .vfRows()
            }
            .navigationTitle("Search")
            .vfScreen()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onChange(of: query) { _, _ in scope = .all }
        }
    }

    // MARK: Les catégories trouvées

    private func scopes(_ r: Results) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases.filter { r.count($0) > 0 }) { s in
                    Button { withAnimation(VFMotion.snap) { scope = s } } label: {
                        HStack(spacing: 5) {
                            if s != .all { Image(systemName: s.icon).font(.caption) }
                            Text(s.title)
                            Text(verbatim: "\(r.count(s))").font(VF.mono(10)).opacity(0.75)
                        }
                        .vfChip(selected: scope == s, color: s.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == s ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }

    /// Dans « Tout », chaque catégorie montre ses premiers résultats et un bouton pour voir les autres.
    private func shown<T>(_ items: [T], _ s: Scope) -> [T] {
        scope == .all ? Array(items.prefix(5)) : (scope == s ? items : [])
    }

    @ViewBuilder private func more(_ total: Int, _ s: Scope) -> some View {
        if scope == .all, total > 5 {
            Button { withAnimation(VFMotion.snap) { scope = s } } label: {
                Text("Show all \(total)").font(.subheadline.weight(.semibold)).foregroundStyle(s.color)
            }
        }
    }

    @ViewBuilder private func sections(_ r: Results) -> some View {
        let guides = shown(r.guides, .guides)
        if !guides.isEmpty {
            Section {
                ForEach(guides) { g in NavigationLink { GuideReader(guide: g) } label: { row(g.category.icon, Scope.guides.color, g.title, g.category.title) } }
                more(r.guides.count, .guides)
            } header: { Text("Guides") }
        }
        let missions = shown(r.missions, .missions)
        if !missions.isEmpty {
            Section {
                ForEach(missions) { x in
                    NavigationLink { MissionDetail(mission: x) } label: {
                        row(progress.isDone(x) ? "checkmark.circle.fill" : "flag.fill", progress.isDone(x) ? VF.palm : Scope.missions.color, x.title, content.chapter(x.chapter)?.title)
                    }
                }
                more(r.missions.count, .missions)
            } header: { Text("Missions") }
        }
        let places = shown(r.places, .places)
        if !places.isEmpty {
            Section {
                ForEach(places) { p in
                    Button {
                        AppRouter.shared.mapPlace = p
                        onPlace?()
                    } label: {
                        HStack {
                            row(p.kind.icon, MapColors.color(p.kind), p.name, p.region ?? p.kind.title)
                            Image(systemName: "map").font(.footnote).foregroundStyle(VF.textFaint)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Map")
                }
                more(r.places.count, .places)
            } header: { Text("Places") }
        }
        let cars = shown(r.vehicles, .vehicles)
        if !cars.isEmpty {
            Section {
                ForEach(cars) { v in NavigationLink { VehiclesView(initialQuery: v.name) } label: { row("car.side.fill", Scope.vehicles.color, v.name, v.maker) } }
                more(r.vehicles.count, .vehicles)
            } header: { Text("Vehicles") }
        }
        let eggs = shown(r.eggs, .eggs)
        if !eggs.isEmpty {
            Section {
                ForEach(eggs) { e in
                    NavigationLink { EggDetail(egg: e) } label: { row(progress.found(e) ? "checkmark.circle.fill" : "oval.portrait.fill", progress.found(e) ? VF.palm : Scope.eggs.color, e.title, e.area) }
                }
                more(r.eggs.count, .eggs)
            } header: { Text("Easter eggs") }
        }
        let people = shown(r.characters, .characters)
        if !people.isEmpty {
            Section {
                ForEach(people) { p in NavigationLink { CharacterDetail(character: p) } label: { row("person.fill", Scope.characters.color, p.name, p.role) } }
                more(r.characters.count, .characters)
            } header: { Text("Characters") }
        }
        let sets = shown(r.collectibles, .collectibles)
        if !sets.isEmpty {
            Section {
                ForEach(sets) { s in NavigationLink { CollectiblesView() } label: { row("sparkles", Scope.collectibles.color, s.title, "\(progress.found(s))/\(s.target)") } }
                more(r.collectibles.count, .collectibles)
            } header: { Text("Collectibles") }
        }
        let cheats = shown(r.cheats, .cheats)
        if !cheats.isEmpty {
            Section {
                ForEach(cheats) { x in NavigationLink { CheatsView(initialQuery: x.name) } label: { row("gamecontroller.fill", Scope.cheats.color, x.name, x.effect) } }
                more(r.cheats.count, .cheats)
            } header: { Text("Cheat codes") }
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color).frame(width: 26)
                .shadow(color: color.opacity(0.6), radius: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).foregroundStyle(VF.text).lineLimit(2)
                if let subtitle, !subtitle.isEmpty { Text(verbatim: subtitle).font(.caption).foregroundStyle(VF.textDim).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
    }
}
