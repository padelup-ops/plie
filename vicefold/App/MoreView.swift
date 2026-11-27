// MoreView.swift — Vicefold
//
// Le reste : communauté, personnages (notes et favoris), secrets, radio (extraits Apple Music), codes de triche,
// véhicules, profil, réglages, Pro.

import AVFoundation
import SwiftUI

enum MoreItem: String, Hashable, CaseIterable, Identifiable {
    case community, characters, eggs, radio, cheats, vehicles, collectibles, profile, settings
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .community: return "Community"
        case .characters: return "Characters"
        case .eggs: return "Easter eggs"
        case .radio: return "Radio"
        case .cheats: return "Cheat codes"
        case .vehicles: return "Vehicles"
        case .collectibles: return "Collectibles"
        case .profile: return "Profile and play time"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .community: return "bubble.left.and.bubble.right.fill"
        case .characters: return "person.2.fill"
        case .eggs: return "oval.portrait.fill"
        case .radio: return "radio.fill"
        case .cheats: return "gamecontroller.fill"
        case .vehicles: return "car.side.fill"
        case .collectibles: return "sparkles"
        case .profile: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
    var color: Color {
        switch self {
        case .community: return VF.flamingo
        case .characters: return VF.sky
        case .eggs: return VF.cyan
        case .radio: return VF.sunset
        case .cheats: return Color(red: 0.80, green: 0.58, blue: 1.0)
        case .vehicles: return VF.palm
        case .collectibles: return VF.sun
        case .profile: return VF.cyan
        case .settings: return Color(red: 0.70, green: 0.74, blue: 0.84)
        }
    }
    @ViewBuilder var screen: some View {
        switch self {
        case .community: CommunityView()
        case .characters: CharactersView()
        case .eggs: EggsView()
        case .radio: RadioView()
        case .cheats: CheatsView()
        case .vehicles: VehiclesView()
        case .collectibles: CollectiblesView()
        case .profile: ProfileView()
        case .settings: SettingsView()
        }
    }
}

struct MoreView: View {
    @State private var selected: MoreItem? = MoreItem(rawValue: ["friends", "thread"].contains(ShotMode.route ?? "") ? "community" : ShotMode.route ?? "")

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
                Group {
                    if !store.isPro || ShotMode.route == "pro" {
                        Section {
                            Button { showPro = true } label: { proBanner }
                                .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    Section { ForEach([MoreItem.community, .characters, .eggs, .radio, .cheats, .vehicles, .collectibles]) { row($0) } }
                    Section { ForEach([MoreItem.profile, .settings]) { row($0) } }
                }
                .vfRows()
            }
            .navigationTitle("More")
            .vfScreen()
            .navigationDestination(item: $push) { $0.screen }
            .sheet(isPresented: $showPro) { ProView() }
            .task {
                // Captures : ouvrir l'écran demandé une seule fois, une fois la mise en page posée (sinon il
                // s'empilait deux fois).
                guard !wide, let s = selected, ShotMode.route != nil, !Self.autoPushed else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, !Self.autoPushed else { return }
                Self.autoPushed = true
                push = s
            }
        }
    }

    @MainActor static var autoPushed = false

    private var proBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.circle.fill").font(.system(size: 40)).foregroundStyle(VF.blaze)
                .shadow(color: VF.sunset.opacity(0.7), radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vicefold Pro").font(VF.display(22, relativeTo: .title3)).foregroundStyle(VF.text)
                Text("Unlimited pins, map layers, your own map, iCloud sync, PlayStation hours.").font(.footnote).foregroundStyle(VF.textDim)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(VF.textFaint)
        }
        .vfCard(radius: 22, padding: 14, tint: VF.flamingo)
    }

    private func row(_ i: MoreItem) -> some View {
        Button { if wide { selected = i } else { push = i } } label: {
            HStack(spacing: 12) {
                VFIconBadge(icon: i.icon, color: i.color, size: 34)
                Text(i.title).foregroundStyle(VF.text)
                Spacer()
                if !wide { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(VF.textFaint) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(selected == i && wide ? VF.rowSelected : VF.row)
    }
}

// MARK: - Personnages

struct CharactersView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var favoritesOnly = false
    @State private var query = ""

    var body: some View {
        let list = self.list
        ScrollView {
            if list.isEmpty {
                VFEmptyState(icon: favoritesOnly ? "star" : "person.2",
                             title: favoritesOnly ? "No favorites yet" : "No character found",
                             message: favoritesOnly ? "Open a character and tap the star to keep them here." : "Try another name.")
                    .padding(.top, 60)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(list) { c in
                    NavigationLink { CharacterDetail(character: c) } label: { CharacterPoster(character: c) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .searchable(text: $query)
        .navigationTitle("Characters")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $favoritesOnly) { Image(systemName: favoritesOnly ? "star.fill" : "star") }.toggleStyle(.button).tint(VF.sun)
                    .accessibilityLabel("Favorites only")
            }
        }
    }

    private var list: [VFCharacter] {
        content.content.characters.filter { c in
            guard !favoritesOnly || progress.isFavorite(c) else { return false }
            if query.isEmpty { return true }
            // Un personnage masqué ne se trouve pas par son nom.
            return !progress.hidden(c.spoiler) && (c.name.localizedCaseInsensitiveContains(query) || c.role.localizedCaseInsensitiveContains(query))
        }
    }
}

/// Un personnage en affiche : ses initiales en grand sur un ciel de nuit à sa couleur, son nom dessous.
struct CharacterPoster: View {
    var character: VFCharacter
    @Environment(Progress.self) private var progress

    var body: some View {
        let hidden = progress.hidden(character.spoiler)
        let hue = Monogram.hue(character.name)
        let glow = Color(hue: hue, saturation: 0.75, brightness: 1)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.80, brightness: 0.55), Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(hidden ? "?" : Monogram.letters(character.name))
                .font(VF.display(110))
                .foregroundStyle(glow.opacity(0.30))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 6, y: -14)
            LinearGradient(colors: [.clear, VF.abyss.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(hidden ? String(localized: "Hidden character") : character.name)
                    .font(VF.display(24, relativeTo: .title3)).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
                Text(hidden ? String(localized: "Revealed later in the story") : character.role)
                    .font(.caption.weight(.semibold)).foregroundStyle(VF.text.opacity(0.85)).lineLimit(1)
            }
            .foregroundStyle(VF.text)
            .padding(12)
            if progress.isFavorite(character) {
                Image(systemName: "star.fill").foregroundStyle(VF.sun).shadow(color: VF.sun.opacity(0.8), radius: 5).padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel("Favorite")
            }
        }
        .frame(height: 210)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LinearGradient(colors: [glow.opacity(0.75), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: glow.opacity(0.22), radius: 12)
    }
}

struct Monogram: View {
    static func hue(_ name: String) -> Double { Double(name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360 }
    static func letters(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }

    var name: String
    var size: CGFloat
    var body: some View {
        let hue = Self.hue(name)
        Text(Self.letters(name))
            .font(VF.display(size * 0.42))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.85), Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
            .overlay(Circle().stroke(Color(hue: hue, saturation: 0.6, brightness: 1).opacity(0.7), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct CharacterDetail: View {
    var character: VFCharacter
    @Environment(Progress.self) private var progress
    @State private var revealed = false
    @State private var note = ""

    var body: some View {
        // Tant que le personnage est masqué, ni son nom ni son rôle ne s'affichent (seulement après « Voir quand même »).
        let hidden = progress.hidden(character.spoiler) && !revealed
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Monogram(name: hidden ? "?" : character.name, size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hidden ? String(localized: "Hidden character") : character.name).font(VF.display(32, relativeTo: .title)).foregroundStyle(VF.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(hidden ? String(localized: "Revealed later in the story") : character.role).vfHUD(VF.cyan, size: 11)
                    }
                }
                if hidden {
                    SpoilerGate(chapter: character.spoiler ?? 0) { revealed = true }
                } else {
                    Text(character.bio).font(.body).foregroundStyle(VF.text).lineSpacing(3)
                    if let f = character.firstSeen { Label(f, systemImage: "eye").font(.subheadline).foregroundStyle(VF.textDim) }
                    if let t = character.tags, !t.isEmpty {
                        // Les étiquettes passent à la ligne au lieu de sortir de l'écran.
                        FlowLayout(spacing: 8) {
                            ForEach(t, id: \.self) {
                                Text($0).font(.caption.weight(.semibold)).foregroundStyle(VF.text).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(VF.cyan.opacity(0.12), in: .capsule)
                                    .overlay(Capsule().stroke(VF.cyan.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                }
                SectionTitle(title: "My notes").padding(.top, 8)
                TextField("What you want to remember about them", text: $note, axis: .vertical)
                    .lineLimit(3...10)
                    .vfCard(radius: 14, padding: 12)
                    .onChange(of: note) { _, v in
                        // Rien à écrire si la note n'a pas changé (elle vient d'être relue à l'ouverture).
                        if v != (progress.data.notes[character.id] ?? "") { progress.edit { $0.notes[character.id] = v.isEmpty ? nil : v } }
                    }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            note = progress.data.notes[character.id] ?? ""
            if !progress.hidden(character.spoiler) { Recents.shared.opened(.character, character.id) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { progress.toggleFavorite(character) } label: {
                    Image(systemName: progress.isFavorite(character) ? "star.fill" : "star")
                }
                .tint(VF.sun)
                .accessibilityLabel("Favorite")
                .accessibilityAddTraits(progress.isFavorite(character) ? .isSelected : [])
            }
        }
    }
}

/// Des éléments à la suite, qui passent à la ligne quand la largeur manque.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in rows.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, widest, y + line)
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
    private var ended: NSObjectProtocol?
    private(set) var playing: String?
    /// Le morceau qu'on est en train de chercher (le bouton montre qu'il a bien été touché).
    private(set) var loading: String?

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
        if playing == s.id { stop(); return }
        loading = s.id
        let hit = await hit(for: s)
        // Un autre morceau a été demandé entre-temps : on ne lance pas celui-ci par-dessus.
        guard loading == s.id else { return }
        loading = nil
        guard let u = hit?.previewUrl.flatMap(URL.init(string:)) else { return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let item = AVPlayerItem(url: u)
        player = AVPlayer(playerItem: item)
        // À la fin de l'extrait, le bouton revient à « lecture ».
        ended = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        player?.play()
        playing = s.id
    }

    func stop() {
        player?.pause()
        player = nil
        if let ended { NotificationCenter.default.removeObserver(ended) }
        ended = nil
        playing = nil
    }
}

struct RadioView: View {
    @Environment(ContentStore.self) private var content
    @State private var previews = Previews.shared

    var body: some View {
        List {
            Group {
                ForEach(content.content.stations) { st in
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(VF.sunset).shadow(color: VF.sunset.opacity(0.8), radius: 5)
                                Text(st.name).font(VF.display(20, relativeTo: .headline)).foregroundStyle(VF.text)
                                Spacer(minLength: 6)
                                if !st.genre.isEmpty { Text(st.genre).vfHUD(VF.cyan, size: 9.5).lineLimit(1).minimumScaleFactor(0.7) }
                            }
                            if let h = st.host { Text("Host: \(h)").font(.caption).foregroundStyle(VF.textDim) }
                            if let s = st.summary { Text(s).font(.subheadline).foregroundStyle(VF.textDim) }
                        }
                        ForEach(st.songs) { song in SongRow(song: song) }
                        if st.songs.isEmpty { Text("Track list coming in a content update.").font(.footnote).foregroundStyle(VF.textDim) }
                    }
                }
                if content.content.stations.isEmpty {
                    Section { VFEmptyState(icon: "radio", title: "No stations yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
                }
                Section {
                    Text("Previews and links come from Apple Music. Vicefold doesn't host any music.").font(.footnote).foregroundStyle(VF.textDim)
                }
            }
            .vfRows()
        }
        .navigationTitle("Radio")
        .vfScreen()
        .onDisappear { previews.stop() }
    }
}

private struct SongRow: View {
    var song: VFSong
    @State private var previews = Previews.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        let playing = previews.playing == song.id
        HStack {
            Button { Task { await previews.toggle(song) } } label: {
                Group {
                    if previews.loading == song.id {
                        ProgressView().tint(VF.sunset)
                    } else {
                        Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill").font(.title2).foregroundStyle(playing ? VF.flamingo : VF.sunset)
                            .shadow(color: (playing ? VF.flamingo : VF.sunset).opacity(playing ? 0.8 : 0.3), radius: 5)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Stop preview" : "Play preview")
            VStack(alignment: .leading) {
                Text(song.title).foregroundStyle(VF.text)
                Text(song.artist).font(.caption).foregroundStyle(VF.textDim)
            }
            Spacer()
            Button {
                Task {
                    if let u = await previews.hit(for: song)?.trackViewUrl.flatMap(URL.init(string:)) { openURL(u) }
                }
            } label: { Image(systemName: "arrow.up.forward.app").frame(width: 32, height: 32).contentShape(.rect) }
                .buttonStyle(.plain)
                .foregroundStyle(VF.textDim)
                .accessibilityLabel("Open in Apple Music")
        }
    }
}

// MARK: - Codes de triche

struct CheatsView: View {
    /// Une recherche déjà remplie (quand on arrive de la recherche générale).
    var initialQuery = ""
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var query = ""

    var body: some View {
        let list = content.content.cheats.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.effect.localizedCaseInsensitiveContains(query) }
        let groups = list.reduce(into: [String]()) { let g = $1.group ?? ""; if !$0.contains(g) { $0.append(g) } }
        List {
            Group {
                Section {
                    Picker("Platform", selection: Binding(get: { progress.data.platform }, set: { v in progress.edit { $0.platform = v } })) {
                        Text("PlayStation").tag("ps5")
                        Text("Xbox").tag("xbox")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                ForEach(groups, id: \.self) { g in
                    Section(g) {
                        ForEach(list.filter { ($0.group ?? "") == g }) { c in cheatRow(c) }
                    }
                }
                if content.content.cheats.isEmpty {
                    Section { VFEmptyState(icon: "gamecontroller", title: "No cheat codes yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
                } else if list.isEmpty {
                    Section { ContentUnavailableView.search(text: query).listRowBackground(Color.clear) }
                }
                Section {
                    Text("Cheats unlock after the story, one by one. Open the phone (↑), hold L1 (LB on Xbox), press R1 (RB), then enter the arrows. A cheat turns off trophies and saving until you quit: save first.").font(.footnote).foregroundStyle(VF.textDim)
                }
            }
            .vfRows()
        }
        .searchable(text: $query)
        .navigationTitle("Cheat codes")
        .vfScreen()
        .onAppear { if query.isEmpty { query = initialQuery } }
    }
}

extension CheatsView {
    @ViewBuilder func cheatRow(_ c: VFCheat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(c.name).font(.headline).foregroundStyle(VF.text)
            Text(c.effect).font(.subheadline).foregroundStyle(VF.textDim)
            if let code = progress.data.platform == "xbox" ? c.xbox : c.playstation {
                Text(code).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(VF.cyan).textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(VF.cyan.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VF.cyan.opacity(0.35), lineWidth: 1))
            }
            if let p = c.phone { Label(p, systemImage: "iphone").font(.callout.monospaced()).foregroundStyle(VF.text) }
            if let n = c.note { Text(n).font(.caption).foregroundStyle(VF.textDim) }
        }
        .padding(.vertical, 4)
    }
}
