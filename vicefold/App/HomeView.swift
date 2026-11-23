// HomeView.swift — Vicefold
//
// L'accueil, comme une carte postale de Leonida : la prochaine mission en affiche sur la vraie carte, ta progression
// en égaliseur, le lieu et le secret du jour (une raison de revenir chaque jour), des billets vers le reste.

import SwiftUI

struct HomeView: View {
    @Binding var tab: AppTab
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @State private var showShare = false
    @State private var showProfile = false
    @State private var showSearch = ShotMode.route == "search"
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        DualLayout {
            column
        } secondary: {
            // Droite du pli : le secret du jour, les billets, par où commencer, les nouveautés.
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        secretOfTheDay
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
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() } }
        .sheet(isPresented: $showSearch) { SearchView() }
    }

    private var column: some View {
        NavigationStack {
            WideReader { wide in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        hero
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
        let days = Calendar.current.dateComponents([.day], from: VF.release, to: Date()).day ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Group {
                if days < 0 { Text("Release in \(-days) days") }
                else if days == 0 { Text("Out today on PS5 and Xbox Series") }
                else { Text("Day \(days + 1) in Leonida") }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VF.flamingo)
            Text(greeting).font(VF.display(40)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let n = progress.data.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? String(localized: "Welcome to Leonida") : String(localized: "Hi \(n)")
    }

    // MARK: L'affiche : la prochaine mission sur la vraie carte

    @ViewBuilder private var hero: some View {
        if let m = progress.nextMission(content.content) {
            let hidden = progress.hidden(m.chapter)
            let chapterMissions = content.content.missions.filter { $0.chapter == m.chapter && $0.optional != true }
            let done = chapterMissions.filter { progress.isDone($0) }.count
            NavigationLink { MissionDetail(mission: m) } label: {
                ZStack(alignment: .bottomLeading) {
                    MapPostcard(focus: CGPoint(x: 0.74, y: 0.5), zoom: 3.2)
                    LinearGradient(colors: [.clear, VF.ink.opacity(0.25), VF.ink.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    Text("Map © GTADB.org · CC BY 4.0")
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next mission")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(VF.flamingo, in: .capsule)
                        Text(hidden ? String(localized: "Hidden until you get there") : m.title)
                            .font(VF.display(40))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.leading)
                        if let c = content.chapter(m.chapter) {
                            HStack(spacing: 10) {
                                Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(done)/\(chapterMissions.count)").font(.subheadline.weight(.bold)).monospacedDigit()
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            ProgressView(value: Double(done), total: Double(max(1, chapterMissions.count)))
                                .tint(VF.sun)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                }
                .frame(height: 300)
                .clipShape(.rect(cornerRadius: 30, style: .continuous))
                .contentShape(.rect(cornerRadius: 30))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the mission")
        }
    }

    // MARK: Progression

    private var progressCard: some View {
        Button { tab = .tracker } label: {
            VStack(alignment: .leading, spacing: 14) {
                ProgressEqualizer(parts: progress.parts(content.content))
                HStack {
                    Label("\(progress.data.missions.count) missions done", systemImage: "flag.checkered")
                    Spacer()
                    Button { showShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).tint(VF.flamingo).controlSize(.small)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .vfCard(radius: 26, padding: 18)
        }
        .buttonStyle(.plain)
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
                        VStack(alignment: .leading, spacing: 5) {
                            Label(p.kind.title, systemImage: p.kind.icon).font(.caption.weight(.bold)).foregroundStyle(MapColors.color(p.kind))
                            Text(p.name).font(VF.display(24, relativeTo: .title3)).lineLimit(2).minimumScaleFactor(0.7)
                            if let r = p.region { Text(r).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            if let real = p.real { Text("Inspired by \(real)").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.circle.fill").font(.title2).foregroundStyle(VF.flamingo)
                    }
                    .vfCard(radius: 24, padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Le secret du jour (un polaroïd)

    @ViewBuilder private var secretOfTheDay: some View {
        let eggs = content.content.eggs.filter { !progress.found($0) && !progress.hidden($0.spoiler) }
        let pool = eggs.isEmpty ? content.content.eggs.filter { !progress.hidden($0.spoiler) } : eggs
        if !pool.isEmpty {
            let e = pool[Daily.index(pool.count, salt: 3)]
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Secret of the day")
                NavigationLink { EggDetail(egg: e) } label: { Polaroid(egg: e).rotationEffect(.degrees(-1.5)).padding(.horizontal, 6) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Les billets

    private var tickets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { tab = .map } label: { TicketTile(title: "Map", stub: "600 places", icon: "map.fill", color: VF.palm) }
                NavigationLink { EggsView() } label: {
                    TicketTile(title: "Easter eggs", stub: "\(content.content.eggs.filter { progress.found($0) }.count)/\(content.content.eggs.count) found", icon: "oval.portrait.fill", color: VF.flamingo)
                }
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
            ForEach(news.prefix(3)) { n in
                HStack(alignment: .top, spacing: 12) {
                    Capsule().fill(VF.flamingo).frame(width: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title).font(.headline)
                        Text(n.body).font(.subheadline).foregroundStyle(.secondary)
                        Text(n.date).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .vfCard()
    }

    private var credits: some View {
        Text("Unofficial fan guide. Not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. Game names are trademarks of their owners.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
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
        LeonidaMapView(showsCredit: false)
            .environment(map)
            .allowsHitTesting(false)
            .overlay {
                if pin {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white, VF.flamingo)
                        .shadow(radius: 3)
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

/// Un easter egg en polaroïd : la photo (un bout de carte, ou un dégradé du soir), la légende dessous.
struct Polaroid: View {
    var egg: VFEgg
    var photoHeight: CGFloat = 170
    @Environment(Progress.self) private var progress
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hidden = progress.hidden(egg.spoiler)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let x = egg.x, let y = egg.y {
                    MapPostcard(focus: CGPoint(x: x, y: y), zoom: 6, pin: true)
                } else {
                    VF.dusk.overlay(Image(systemName: "sparkles").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
                }
                if progress.found(egg) {
                    Label("Found", systemImage: "checkmark.seal.fill").font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4).background(VF.palm, in: .capsule).foregroundStyle(.white).padding(8)
                }
            }
            .frame(height: photoHeight)
            .clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(hidden ? String(localized: "Hidden until your chapter") : egg.title).font(VF.display(photoHeight < 150 ? 18 : 22, relativeTo: .title3)).foregroundStyle(VF.ink)
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                Text(egg.area).font(.caption).foregroundStyle(VF.ink.opacity(0.6)).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .padding(.bottom, 6)
        .background(Color.white, in: .rect(cornerRadius: 6))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 12, y: 6)
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: guide.category.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(VF.dusk, in: .rect(cornerRadius: 12, style: .continuous))
            Text(guide.title).font(VF.display(20, relativeTo: .headline)).lineLimit(2).multilineTextAlignment(.leading)
            if let s = guide.summary { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            Spacer(minLength: 0)
            if let m = guide.minutes { Text("\(m) min read").font(.caption2.weight(.semibold)).foregroundStyle(VF.flamingo) }
        }
        .padding(14)
        .frame(width: 200, height: 200, alignment: .topLeading)
        .background(VF.card(scheme == .dark), in: .rect(cornerRadius: 22, style: .continuous))
        .shadow(color: VF.ink.opacity(scheme == .dark ? 0 : 0.06), radius: 10, y: 4)
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
    }

    private var initial: String {
        progress.data.name.first.map { String($0).uppercased() } ?? "V"
    }
}
