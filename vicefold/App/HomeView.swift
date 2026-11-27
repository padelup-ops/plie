// HomeView.swift — Vicefold
//
// L'accueil, comme un tableau de bord de nuit : la prochaine mission en affiche sur la carte en hologramme, de quoi
// reprendre là où on s'était arrêté, la progression en égaliseur de néon, le lieu et le secret du jour (une raison
// de revenir chaque jour), des billets vers le reste.

import SwiftUI

struct HomeView: View {
    @Binding var tab: AppTab
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @State private var recents = Recents.shared
    @State private var showShare = false
    @State private var showProfile = false
    @State private var showSearch = ShotMode.route == "search"
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        DualLayout {
            column
        } secondary: {
            // Droite du pli : le secret du jour (le titre court laisse la place aux icônes d'état du Duo), reprendre, les billets, par où commencer, les nouveautés.
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: VF.Space.l) {
                        secretOfTheDay
                        resume
                        tickets
                        startHere
                        if let news = content.content.news, !news.isEmpty { newsCard(news) }
                        credits
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 20)
                }
                .background(VFBackdrop())
            }
        }
        .sheet(isPresented: $showShare) { ShareProgressView() }
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileView(closable: true) } }
        .sheet(isPresented: $showSearch) { SearchView(onPlace: { showSearch = false }) }
    }

    private var column: some View {
        NavigationStack {
            WideReader { wide in
                ScrollView {
                    VStack(alignment: .leading, spacing: VF.Space.l) {
                        header
                        hero
                        if !wide { resume }
                        progressCard
                        spotOfTheDay
                        if !wide {
                            secretOfTheDay
                            tickets
                            startHere
                            if let news = content.content.news, !news.isEmpty { newsCard(news) }
                            credits
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(VFBackdrop())
            .toolbar {
                // Sur iPhone la recherche n'a pas d'onglet (cinq au plus, sinon iOS range le reste dans « Autre ») :
                // elle s'ouvre d'ici.
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                            .accessibilityLabel("Search")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: { Avatar(size: 32) }
                        .accessibilityLabel("Profile")
                }
            }
            .refreshable { _ = await content.refresh() }
        }
    }

    static var appName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "GTA VI Guide"
    }

    // MARK: En-tête

    private var header: some View {
        // Le même compte de jours que les widgets et l'image à partager (jours du calendrier, pas tranches de 24 h).
        let days = VFDaysFace.days()
        let line: Text = days < 0 ? Text("Release in \(-days) days") : (days == 0 ? Text("Out today on PS5 and Xbox Series") : Text("Day \(days + 1) in Leonida"))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(VF.cyan).frame(width: 6, height: 6).shadow(color: VF.cyan, radius: 5).accessibilityHidden(true)
                line.vfHUD(VF.cyan, size: 11).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(greeting).font(VF.display(40)).foregroundStyle(VF.text).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let n = progress.data.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? String(localized: "Welcome to Leonida") : String(localized: "Hi \(n)")
    }

    // MARK: L'affiche : la prochaine mission sur la carte

    @ViewBuilder private var hero: some View {
        if let m = progress.nextMission(content.content) {
            let hidden = progress.hidden(m.chapter)
            let chapterMissions = content.content.missions.filter { $0.chapter == m.chapter && $0.optional != true }
            let done = chapterMissions.filter { progress.isDone($0) }.count
            // Le lieu de la mission s'il est connu (et pas masqué), sinon Vice City.
            let spot = hidden ? nil : m.place.flatMap { content.place($0) }
            NavigationLink { MissionDetail(mission: m) } label: {
                ZStack(alignment: .bottomLeading) {
                    MapPostcard(focus: spot.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: 0.74, y: 0.5), zoom: spot == nil ? 3.2 : 5, pin: spot != nil)
                    RadarSweep(period: 7)
                    LinearGradient(colors: [VF.abyss.opacity(0), VF.abyss.opacity(0.18), VF.abyss.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    VStack {
                        HStack(alignment: .top) {
                            Text("Next mission")
                                .font(VF.mono(10.5, weight: .bold)).tracking(1.2).textCase(.uppercase)
                                .foregroundStyle(VF.ink)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(VF.gradient, in: .capsule)
                                .shadow(color: VF.flamingo.opacity(0.6), radius: 8)
                            Spacer()
                            Text("Map © GTADB.org · CC BY 4.0")
                                .font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                    }
                    .padding(20)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(hidden ? String(localized: "Hidden until you get there") : m.title)
                            .font(VF.display(38))
                            .foregroundStyle(VF.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.6), radius: 8)
                        if let c = content.chapter(m.chapter) {
                            HStack(spacing: 10) {
                                Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(verbatim: "\(done)/\(chapterMissions.count)").font(VF.mono(13, weight: .bold))
                            }
                            .foregroundStyle(VF.text.opacity(0.9))
                            VFBar(value: Double(done) / Double(max(1, chapterMissions.count)))
                        }
                    }
                    .padding(20)
                }
                .frame(height: 300)
                .clipShape(.rect(cornerRadius: VF.Radius.hero, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: VF.Radius.hero, style: .continuous)
                    .stroke(LinearGradient(colors: [VF.cyan.opacity(0.7), .white.opacity(0.08), VF.flamingo.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .vfTicks(VF.cyan, length: 14, inset: 12)
                .shadow(color: VF.cyan.opacity(0.18), radius: 22)
                .contentShape(.rect(cornerRadius: VF.Radius.hero))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the mission")
        } else {
            // Toutes les missions de l'histoire sont faites.
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(VF.palm).shadow(color: VF.palm.opacity(0.7), radius: 10)
                Text("All missions done").font(VF.display(32)).foregroundStyle(VF.text)
                Button { tab = .tracker } label: { Label("Your 100%", systemImage: "checklist") }
                    .buttonStyle(.vf(.secondary, compact: true))
            }
            .vfCard(radius: VF.Radius.hero, padding: 20, tint: VF.palm)
        }
    }

    // MARK: Reprendre

    private struct ResumeEntry: Identifiable {
        var id: String
        var icon: String
        var color: Color
        var kicker: String
        var title: String
        var destination: AnyView
    }

    /// Les derniers écrans ouverts qui ne sont pas encore finis (mission pas faite, guide pas lu, secret pas trouvé).
    private var resumeEntries: [ResumeEntry] {
        let c = content.content
        var out: [ResumeEntry] = []
        for item in recents.items {
            switch item.kind {
            case .guide:
                guard let g = c.guides.first(where: { $0.id == item.ref }), !progress.data.readGuides.contains(g.id) else { continue }
                out.append(ResumeEntry(id: item.id, icon: g.category.icon, color: VF.sun, kicker: g.category.title, title: g.title, destination: AnyView(GuideReader(guide: g))))
            case .mission:
                guard let m = c.missions.first(where: { $0.id == item.ref }), !progress.isDone(m) else { continue }
                let hidden = progress.hidden(m.chapter)
                out.append(ResumeEntry(id: item.id, icon: "flag.fill", color: VF.flamingo,
                                       kicker: hidden ? String(localized: "Chapter \(m.chapter)") : (content.chapter(m.chapter)?.title ?? String(localized: "Missions")),
                                       title: hidden ? String(localized: "Hidden mission") : m.title, destination: AnyView(MissionDetail(mission: m))))
            case .egg:
                guard let e = c.eggs.first(where: { $0.id == item.ref }), !progress.found(e) else { continue }
                out.append(ResumeEntry(id: item.id, icon: "oval.portrait.fill", color: VF.cyan, kicker: e.area,
                                       title: progress.hidden(e.spoiler) ? String(localized: "Hidden until your chapter") : e.title, destination: AnyView(EggDetail(egg: e))))
            case .character:
                guard let p = c.characters.first(where: { $0.id == item.ref }), !progress.hidden(p.spoiler) else { continue }
                out.append(ResumeEntry(id: item.id, icon: "person.fill", color: VF.sky, kicker: p.role, title: p.name, destination: AnyView(CharacterDetail(character: p))))
            }
            if out.count == 4 { break }
        }
        return out
    }

    @ViewBuilder private var resume: some View {
        let entries = resumeEntries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Pick up where you left off")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(entries) { e in
                            NavigationLink { e.destination } label: {
                                HStack(spacing: 12) {
                                    VFIconBadge(icon: e.icon, color: e.color, size: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: e.kicker).vfHUD(e.color, size: 9.5).lineLimit(1)
                                        Text(verbatim: e.title).font(.subheadline.weight(.semibold)).foregroundStyle(VF.text).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(VF.textFaint)
                                }
                                .frame(width: 236, alignment: .leading)
                                .vfCard(radius: 18, padding: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Progression

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { tab = .tracker } label: {
                ProgressEqualizer(parts: progress.parts(content.content))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Your 100%")
            Rectangle().fill(VF.hairline).frame(height: 1)
            HStack {
                Label("\(progress.data.missions.count) missions done", systemImage: "flag.checkered")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VF.textDim)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button { showShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.vf(.secondary, compact: true))
            }
        }
        .vfCard(radius: 26, padding: 18)
    }

    // MARK: Le lieu du jour

    @ViewBuilder private var spotOfTheDay: some View {
        let spots = content.content.places.filter { $0.community && ($0.real != nil || $0.enterable == true) && !progress.hidden($0.spoiler) }
        if !spots.isEmpty {
            let p = spots[Daily.index(spots.count, salt: 7)]
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Spot of the day")
                Button { AppRouter.shared.mapPlace = p } label: {
                    HStack(spacing: 14) {
                        MapPostcard(focus: CGPoint(x: p.x, y: p.y), zoom: 9, pin: true)
                            .frame(width: 112, height: 112)
                            .clipShape(.rect(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VF.cyan.opacity(0.45), lineWidth: 1))
                            .vfTicks(VF.cyan, length: 8, inset: 6)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(p.kind.title).vfHUD(MapColors.color(p.kind), size: 10).lineLimit(1)
                            Text(p.name).font(VF.display(24, relativeTo: .title3)).foregroundStyle(VF.text).lineLimit(2).minimumScaleFactor(0.7)
                                .multilineTextAlignment(.leading)
                            if let r = p.region { Text(r).font(.caption).foregroundStyle(VF.textDim).lineLimit(1) }
                            if let real = p.real { Text("Inspired by \(real)").font(.caption).foregroundStyle(VF.textDim).lineLimit(2).multilineTextAlignment(.leading) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(VF.cyan)
                            .frame(width: 34, height: 34).background(VF.cyan.opacity(0.12), in: .circle)
                            .overlay(Circle().stroke(VF.cyan.opacity(0.5), lineWidth: 1))
                    }
                    .vfCard(radius: 24, padding: 12)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Map")
            }
        }
    }

    // MARK: Le secret du jour

    @ViewBuilder private var secretOfTheDay: some View {
        let eggs = content.content.eggs.filter { !progress.found($0) && !progress.hidden($0.spoiler) }
        let pool = eggs.isEmpty ? content.content.eggs.filter { !progress.hidden($0.spoiler) } : eggs
        if !pool.isEmpty {
            let e = pool[Daily.index(pool.count, salt: 3)]
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Secret of the day")
                NavigationLink { EggDetail(egg: e) } label: { HoloCard(egg: e) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Les billets

    private var tickets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { tab = .map } label: { TicketTile(title: "Map", stub: "\(content.content.places.count) places", icon: "map.fill", color: VF.cyan) }
                NavigationLink { EggsView() } label: {
                    TicketTile(title: "Easter eggs", stub: "\(content.content.eggs.filter { progress.found($0) }.count)/\(content.content.eggs.count) found", icon: "oval.portrait.fill", color: VF.flamingo)
                }
                NavigationLink { VehiclesView() } label: { TicketTile(title: "Vehicles", stub: "\(VehicleStore.shared.list.vehicles.count) vehicles", icon: "car.side.fill", color: VF.palm) }
                NavigationLink { RadioView() } label: { TicketTile(title: "Radio", stub: "Songs & previews", icon: "radio.fill", color: VF.sunset) }
                NavigationLink { CheatsView() } label: { TicketTile(title: "Cheat codes", stub: "PS5 and Xbox", icon: "gamecontroller.fill", color: VF.sky) }
                Button { tab = .tracker } label: { TicketTile(title: "Collectibles", stub: "Every 100% item", icon: "sparkles", color: VF.sun) }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: Par où commencer

    @ViewBuilder private var startHere: some View {
        let g = content.guides(.start)
        if !g.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Start here")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(g) { guide in
                            NavigationLink { GuideReader(guide: guide) } label: { GuideCard(guide: guide) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func newsCard(_ news: [VFNews]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "What's new in the guide")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(news.prefix(3)) { n in
                    HStack(alignment: .top, spacing: 12) {
                        Capsule().fill(VF.ice).frame(width: 3).shadow(color: VF.cyan.opacity(0.7), radius: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.date).font(VF.mono(10)).foregroundStyle(VF.cyan)
                            Text(n.title).font(.headline).foregroundStyle(VF.text)
                            Text(n.body).font(.subheadline).foregroundStyle(VF.textDim)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .vfCard()
        }
    }

    private var credits: some View {
        Text("Unofficial fan guide. Not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. Game names are trademarks of their owners.")
            .font(.caption2)
            .foregroundStyle(VF.textFaint)
            .padding(.top, 8)
    }
}

/// Un morceau de la vraie carte de Leonida, fixe (pour les affiches et les aperçus).
struct MapPostcard: View {
    var focus: CGPoint
    var zoom: CGFloat
    var pin = false
    @State private var map = MapState()

    var body: some View {
        LeonidaMapView(showsCredit: false, decorated: false)
            .environment(map)
            .allowsHitTesting(false)
            .overlay {
                if pin {
                    ZStack {
                        Circle().stroke(VF.flamingo.opacity(0.55), lineWidth: 1.5).frame(width: 40, height: 40)
                        Circle().fill(VF.flamingo).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: VF.flamingo, radius: 8)
                    }
                }
            }
            .onAppear {
                map.layers = []
                map.showPins = false
                map.animateFocus = false
                map.zoom = zoom
                map.focus = CGPoint(x: focus.x * Leonida.size.width, y: focus.y * Leonida.size.height)
            }
            .accessibilityHidden(true)
    }
}

/// Un easter egg en carte holographique : la « photo » (un bout de carte, ou un ciel du soir), la légende dessous.
struct HoloCard: View {
    var egg: VFEgg
    var photoHeight: CGFloat = 170
    @Environment(Progress.self) private var progress

    var body: some View {
        let hidden = progress.hidden(egg.spoiler)
        let found = progress.found(egg)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let x = egg.x, let y = egg.y {
                    MapPostcard(focus: CGPoint(x: x, y: y), zoom: 6, pin: true)
                } else {
                    SynthScene(time: 0, sunrise: 1, palms: false, horizon: 0.7)
                        .overlay(Image(systemName: "sparkles").font(.system(size: photoHeight * 0.22, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).offset(y: -photoHeight * 0.2))
                }
                if found {
                    Label("Found", systemImage: "checkmark.seal.fill").font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4).background(VF.palm, in: .capsule).foregroundStyle(VF.ink).padding(8)
                }
            }
            .frame(height: photoHeight)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .vfTicks(found ? VF.palm : VF.cyan, length: 9, inset: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(hidden ? String(localized: "Hidden until your chapter") : egg.title)
                    .font(VF.display(photoHeight < 150 ? 18 : 22, relativeTo: .title3)).foregroundStyle(VF.text)
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                Text(egg.area).vfHUD(VF.textDim, size: 9.5).lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .padding(.bottom, 4)
        .background { VFPanel(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: found ? VF.palm : VF.flamingo) }
    }
}

/// Lit « la page est en deux moitiés » à l'intérieur d'une pile de navigation.
struct WideReader<Content: View>: View {
    @Environment(\.vfWide) private var wide
    @ViewBuilder var content: (Bool) -> Content
    var body: some View { content(wide) }
}

struct GuideCard: View {
    var guide: VFGuide
    @Environment(Progress.self) private var progress

    var body: some View {
        let read = progress.data.readGuides.contains(guide.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VFIconBadge(icon: guide.category.icon, color: VF.sun, size: 40)
                Spacer()
                if read { Image(systemName: "checkmark.circle.fill").foregroundStyle(VF.palm).accessibilityLabel("Read") }
            }
            Text(guide.title).font(VF.display(20, relativeTo: .headline)).foregroundStyle(VF.text).lineLimit(2).multilineTextAlignment(.leading)
            if let s = guide.summary { Text(s).font(.caption).foregroundStyle(VF.textDim).lineLimit(3).multilineTextAlignment(.leading) }
            Spacer(minLength: 0)
            if let m = guide.minutes { Text("\(m) min read").vfHUD(VF.cyan, size: 10) }
        }
        .padding(14)
        .frame(width: 200, height: 200, alignment: .topLeading)
        .background { VFPanel(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: nil) }
    }
}

struct Avatar: View {
    var size: CGFloat
    @Environment(Progress.self) private var progress

    var body: some View {
        Group {
            if let img = UIImage(contentsOfFile: progress.photoURL.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(initial)
                    .font(VF.display(size * 0.5))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VF.dusk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(VF.gradient, lineWidth: max(1.5, size * 0.035)))
    }

    private var initial: String {
        progress.data.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "V"
    }
}
