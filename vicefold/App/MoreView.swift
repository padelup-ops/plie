// MoreView.swift — Vicefold
//
// Le reste : personnages (notes et favoris), radio (extraits Apple Music), codes de triche, profil, réglages, Pro.

import AVFoundation
import SwiftUI

enum MoreItem: String, Hashable, CaseIterable, Identifiable {
    case characters, eggs, radio, cheats, collectibles, profile, settings
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .characters: return "Characters"
        case .eggs: return "Easter eggs"
        case .radio: return "Radio"
        case .cheats: return "Cheat codes"
        case .collectibles: return "Collectibles"
        case .profile: return "Profile and play time"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .characters: return "person.2"
        case .eggs: return "oval.portrait"
        case .radio: return "radio"
        case .cheats: return "gamecontroller"
        case .collectibles: return "sparkles"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
    @ViewBuilder var screen: some View {
        switch self {
        case .characters: CharactersView()
        case .eggs: EggsView()
        case .radio: RadioView()
        case .cheats: CheatsView()
        case .collectibles: CollectiblesView()
        case .profile: ProfileView()
        case .settings: SettingsView()
        }
    }
}

struct MoreView: View {
    @State private var selected: MoreItem? = MoreItem(rawValue: ShotMode.route ?? "")

    var body: some View {
        DualLayout {
            MoreList(selected: $selected)
        } secondary: {
            NavigationStack {
                if let s = selected { s.screen.id(s) } else { EmptyDetail(icon: "square.grid.2x2", text: "More") }
            }
        }
    }
}

private struct MoreList: View {
    @Binding var selected: MoreItem?
    @Environment(\.vfWide) private var wide
    @Environment(Store.self) private var store
    @State private var showPro = ShotMode.route == "pro"
    @State private var push: MoreItem?

    var body: some View {
        NavigationStack {
            List {
                if !store.isPro {
                    Section {
                        Button { showPro = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "star.circle.fill").font(.largeTitle).foregroundStyle(VF.gradient)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Vicefold Pro").font(.headline).foregroundStyle(.primary)
                                    Text("Unlimited pins, map layers, your own map, iCloud sync, PlayStation hours.").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section { ForEach([MoreItem.characters, .radio, .cheats, .collectibles]) { row($0) } }
                Section { ForEach([MoreItem.profile, .settings]) { row($0) } }
            }
            .navigationTitle("More")
            .navigationDestination(item: $push) { $0.screen }
            .sheet(isPresented: $showPro) { ProView() }
            .onAppear { if !wide, let s = selected, ShotMode.route != nil { push = s } }
        }
    }

    private func row(_ i: MoreItem) -> some View {
        Button { if wide { selected = i } else { push = i } } label: {
            HStack {
                Label(i.title, systemImage: i.icon).foregroundStyle(.primary)
                Spacer()
                if !wide { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .contentShape(.rect)
        }
        .listRowBackground(selected == i && wide ? VF.coral.opacity(0.15) : nil)
    }
}

// MARK: - Personnages

struct CharactersView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var favoritesOnly = false
    @State private var query = ""

    var body: some View {
        List {
            ForEach(list) { c in
                NavigationLink { CharacterDetail(character: c) } label: {
                    HStack(spacing: 12) {
                        Monogram(name: c.name, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(progress.hidden(c.spoiler) ? String(localized: "Hidden character") : c.name).font(.headline)
                            Text(progress.hidden(c.spoiler) ? String(localized: "Revealed later in the story") : c.role).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if progress.isFavorite(c) { Image(systemName: "star.fill").foregroundStyle(VF.sun) }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Characters")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $favoritesOnly) { Image(systemName: "star") }.toggleStyle(.button).accessibilityLabel("Favorites only")
            }
        }
    }

    private var list: [VFCharacter] {
        content.content.characters.filter { c in
            (!favoritesOnly || progress.isFavorite(c)) && (query.isEmpty || c.name.localizedCaseInsensitiveContains(query) || c.role.localizedCaseInsensitiveContains(query))
        }
    }
}

struct Monogram: View {
    var name: String
    var size: CGFloat
    var body: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
        Text(letters)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hue: hue, saturation: 0.6, brightness: 0.85), Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
    }
}

struct CharacterDetail: View {
    var character: VFCharacter
    @Environment(Progress.self) private var progress
    @State private var revealed = false
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Monogram(name: character.name, size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(character.name).font(.title.bold())
                        Text(character.role).foregroundStyle(.secondary)
                    }
                }
                if progress.hidden(character.spoiler) && !revealed {
                    SpoilerGate(chapter: character.spoiler ?? 0) { revealed = true }
                } else {
                    Text(character.bio).font(.body)
                    if let f = character.firstSeen { Label(f, systemImage: "eye").font(.subheadline).foregroundStyle(.secondary) }
                    if let t = character.tags, !t.isEmpty {
                        HStack { ForEach(t, id: \.self) { Text($0).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5).background(VF.teal.opacity(0.15), in: .capsule) } }
                    }
                }
                Text("My notes").font(.headline).padding(.top, 8)
                TextField("What you want to remember about them", text: $note, axis: .vertical)
                    .lineLimit(3...10)
                    .padding(12)
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
                    .onChange(of: note) { _, v in progress.edit { $0.notes[character.id] = v } }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { note = progress.data.notes[character.id] ?? "" }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { progress.toggleFavorite(character) } label: {
                    Image(systemName: progress.isFavorite(character) ? "star.fill" : "star")
                }
                .tint(VF.sun)
                .accessibilityLabel("Favorite")
            }
        }
    }
}

// MARK: - Radio

/// Un extrait de 30 secondes et le lien Apple Music, trouvés avec la recherche publique d'Apple (iTunes Search).
@MainActor @Observable
final class Previews {
    static let shared = Previews()
    struct Hit: Decodable { var previewUrl: String?; var trackViewUrl: String?; var artworkUrl100: String? }
    private struct Response: Decodable { var results: [Hit] }

    private var cache: [String: Hit] = [:]
    private var player: AVPlayer?
    private(set) var playing: String?

    func hit(for s: VFSong) async -> Hit? {
        if let h = cache[s.id] { return h }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: "\(s.artist) \(s.title)"), URLQueryItem(name: "entity", value: "song"),
                        URLQueryItem(name: "limit", value: "1"), URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US")]
        guard let url = c.url, let (d, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: d), let h = r.results.first else { return nil }
        cache[s.id] = h
        return h
    }

    func toggle(_ s: VFSong) async {
        if playing == s.id { player?.pause(); playing = nil; return }
        guard let h = await hit(for: s), let u = h.previewUrl.flatMap(URL.init(string:)) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = AVPlayer(url: u)
        player?.play()
        playing = s.id
    }

    func stop() { player?.pause(); playing = nil }
}

struct RadioView: View {
    @Environment(ContentStore.self) private var content
    @State private var previews = Previews.shared

    var body: some View {
        List {
            ForEach(content.content.stations) { st in
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(VF.coral)
                            Text(st.name).font(.headline)
                            Spacer()
                            Text(st.genre).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        if let h = st.host { Text("Host: \(h)").font(.caption).foregroundStyle(.secondary) }
                        if let s = st.summary { Text(s).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    ForEach(st.songs) { song in SongRow(song: song) }
                    if st.songs.isEmpty { Text("Track list coming in a content update.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text("Previews and links come from Apple Music. Vicefold doesn't host any music.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Radio")
        .onDisappear { previews.stop() }
    }
}

private struct SongRow: View {
    var song: VFSong
    @State private var previews = Previews.shared
    @State private var link: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack {
            Button { Task { await previews.toggle(song) } } label: {
                Image(systemName: previews.playing == song.id ? "stop.circle.fill" : "play.circle.fill").font(.title2).foregroundStyle(VF.coral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previews.playing == song.id ? "Stop preview" : "Play preview")
            VStack(alignment: .leading) {
                Text(song.title)
                Text(song.artist).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    if let u = await previews.hit(for: song)?.trackViewUrl.flatMap(URL.init(string:)) { openURL(u) }
                }
            } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open in Apple Music")
        }
    }
}

// MARK: - Codes de triche

struct CheatsView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var query = ""

    var body: some View {
        @Bindable var progress = progress
        List {
            Section {
                Picker("Platform", selection: Binding(get: { progress.data.platform }, set: { v in progress.edit { $0.platform = v } })) {
                    Text("PlayStation").tag("ps5")
                    Text("Xbox").tag("xbox")
                }
                .pickerStyle(.segmented)
            }
            let list = content.content.cheats.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.effect.localizedCaseInsensitiveContains(query) }
            let groups = list.reduce(into: [String]()) { if let g = $1.group, !$0.contains(g) { $0.append(g) } }
            ForEach(groups.isEmpty ? [""] : groups, id: \.self) { g in
                Section(g) {
                    ForEach(list.filter { ($0.group ?? "") == g }) { c in cheatRow(c) }
                }
            }
            if content.content.cheats.isEmpty {
                ContentUnavailableView("No cheat codes yet", systemImage: "gamecontroller", description: Text("They arrive with a content update, no app update needed."))
            }
            Section {
                Text("Cheats unlock after the story, one by one. Open the phone (↑), hold L1 (LB on Xbox), press R1 (RB), then enter the arrows. A cheat turns off trophies and saving until you quit: save first.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query)
        .navigationTitle("Cheat codes")
    }
}

extension CheatsView {
    @ViewBuilder func cheatRow(_ c: VFCheat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.name).font(.headline)
            Text(c.effect).font(.subheadline).foregroundStyle(.secondary)
            if let code = progress.data.platform == "xbox" ? c.xbox : c.playstation {
                Text(code).font(.system(.callout, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                    .padding(8).background(VF.magenta.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            if let p = c.phone { Label(p, systemImage: "iphone").font(.callout.monospaced()) }
            if let n = c.note { Text(n).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recherche

struct SearchView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var query = ShotMode.route == "search" ? "Vice" : ""

    var body: some View {
        NavigationStack {
            List {
                if query.count >= 2 {
                    let c = content.content
                    let guides = c.guides.filter { m($0.title) || m($0.body) }
                    let missions = c.missions.filter { !progress.hidden($0.chapter) && (m($0.title) || m($0.walkthrough ?? "")) }
                    let places = c.places.filter { !progress.hidden($0.spoiler) && m($0.name) }
                    let people = c.characters.filter { !progress.hidden($0.spoiler) && (m($0.name) || m($0.role)) }
                    let cheats = c.cheats.filter { m($0.name) || m($0.effect) }
                    if !guides.isEmpty { Section("Guides") { ForEach(guides) { g in NavigationLink(g.title) { GuideReader(guide: g) } } } }
                    if !missions.isEmpty { Section("Missions") { ForEach(missions) { x in NavigationLink(x.title) { MissionDetail(mission: x) } } } }
                    if !places.isEmpty { Section("Places") { ForEach(places) { p in Label(p.name, systemImage: p.kind.icon) } } }
                    if !people.isEmpty { Section("Characters") { ForEach(people) { p in NavigationLink(p.name) { CharacterDetail(character: p) } } } }
                    if !cheats.isEmpty { Section("Cheat codes") { ForEach(cheats) { x in NavigationLink(x.name) { CheatsView() } } } }
                    if guides.isEmpty && missions.isEmpty && places.isEmpty && people.isEmpty && cheats.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                } else {
                    Section { Text("Search guides, missions, places, characters and cheat codes.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query)
        }
    }

    private func m(_ s: String) -> Bool { s.localizedCaseInsensitiveContains(query) }
}
