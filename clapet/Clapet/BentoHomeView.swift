import SwiftUI

// MARK: - Le look « Bento » (à l'essai)
//
// Une grille de cartes vivantes, façon « design system » : fond clair et plat, cartes blanches à ombre douce,
// deux cartes sombres, UNE couleur d'accent (bleu). Tout bouge un peu : entrée en ressort décalée, chiffres
// qui roulent, jauge de charnière qui suit le téléphone, point qui pulse quand le Duo est ouvert.

enum Bento {
    /// Une couleur pour le clair, une pour le sombre : le thème suit le réglage de l'iPhone.
    private static func dyn(_ light: UInt32, _ dark: UInt32, _ alpha: CGFloat = 1) -> Color {
        func ui(_ h: UInt32) -> UIColor {
            UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: alpha)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    /// Atelier (à l'essai) : règles anti « design d'IA » (swiftui-design-skill, MIT) — papier chaud, la couleur de
    /// Foldly (vert) au lieu du bleu par défaut, chiffres et titres en serif (New York), pas de dégradé.
    static var atelier: Bool { DFLook.current == .atelier }
    // Bento : une seule famille de gris, chauds.
    private static let bBg = dyn(0xF7F7F5, 0x11110F), aBg = dyn(0xF5F3EF, 0x151412)
    private static let bTray = dyn(0xEEEEEA, 0x1A1A17), aTray = dyn(0xEBE8E1, 0x24231F)
    private static let bCard = dyn(0xFFFFFF, 0x1F1F1C), aCard = dyn(0xFFFFFF, 0x1E1D1A)
    private static let bDark = dyn(0x121210, 0x2C2C28), aDark = dyn(0x1F2A24, 0x26332C)
    private static let bInk = dyn(0x161614, 0xF3F3EF), aInk = dyn(0x1A1917, 0xF2F0EB)
    private static let bMuted = dyn(0x8B8B87, 0x96968F), aMuted = dyn(0x75716A, 0x9C978E)
    private static let bAccent = dyn(0x2F5BFF, 0x5A7DFF), aAccent = dyn(0x2E8B6A, 0x55C49A)
    private static let bTint = dyn(0xEEF2FF, 0x1C2440), aTint = dyn(0xE3F1EA, 0x1D3329)
    private static let bLine = dyn(0x000000, 0xFFFFFF, 0.07), aLine = dyn(0xE3DFD6, 0x2E2C28)
    static var bg: Color { atelier ? aBg : bBg }
    static var tray: Color { atelier ? aTray : bTray }
    static var card: Color { atelier ? aCard : bCard }
    static var dark: Color { atelier ? aDark : bDark }      // la carte « héros », sombre dans les deux thèmes
    static var ink: Color { atelier ? aInk : bInk }
    static var muted: Color { atelier ? aMuted : bMuted }
    /// LA seule couleur d'accent : celle du thème, ou celle choisie (« Arranger » > couleur).
    static var accent: Color {
        let i = UserDefaults.standard.integer(forKey: accentKey)
        if i > 0 && i < palette.count { return palette[i] }
        return atelier ? aAccent : bAccent
    }
    static var tint: Color {
        UserDefaults.standard.integer(forKey: accentKey) > 0 ? accent.opacity(0.16) : (atelier ? aTint : bTint)
    }
    static var accentKey: String { atelier ? "atelierAccent" : "bentoAccent" }
    /// 0 : la couleur du thème. Puis vert, bleu, terre cuite, prune, rose, ambre.
    static let palette: [Color] = [.clear, dyn(0x2E8B6A, 0x55C49A), dyn(0x2F5BFF, 0x5A7DFF), dyn(0xC4532F, 0xE2774F),
                                   dyn(0x7B4FD6, 0x9C7BF0), dyn(0xD6457A, 0xF0709E), dyn(0xC98A12, 0xF0B23E)]
    static var line: Color { atelier ? aLine : bLine }
    /// Les chiffres et les titres : serif dans Atelier.
    static var design: Font.Design { atelier ? .serif : .default }
    // Règle de formes : cartes 22, tuiles 14, barres 6, boutons en pilule.
    static var rCard: CGFloat { atelier ? 16 : 22 }
    static var rTile: CGFloat { atelier ? 8 : 14 }
}

/// Le Duo à moitié ouvert : tenu comme un livre (pli vertical) ou posé en L sur la table (pli horizontal).
enum BentoFold { case book, laptop }

enum BentoIntro { static var played = false }

struct BentoHomeView: View {
    var fold: BentoFold? = nil
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showBoards = false
    @State private var showHistory = false
    @State private var showWeek = false
    @State private var showAuto = false
    @State private var showAdjust = false
    @State private var showShare = false
    @State private var showWidgets = false
    @State private var showMonth = false
    @State private var showHours = false
    @State private var plusReason: PlusReason?
    @State private var foldboardPromoHidden = false
    @State private var ideasHidden = IdeasRule.promoHidden
    @State private var showIdeas = false
    @State private var appeared = BentoIntro.played
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var bigSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title2) private var midSize: CGFloat = 22
    @State private var pulse = false
    @State private var bump = false
    @State private var editing = false
    @State private var wiggle = false
    @State private var dropTarget: String?
    @AppStorage("bentoOrder") private var orderRaw = ""
    @AppStorage("bentoBook") private var bookRaw = ""
    @AppStorage("bentoLaptop") private var laptopRaw = ""
    /// Les cartes cachées (« Arranger » > moins), communes aux deux thèmes et aux positions.
    @AppStorage("bentoHidden") private var hiddenRaw = ""
    @AppStorage("bentoAccent") private var bentoAccent = 0
    @AppStorage("atelierAccent") private var atelierAccent = 0
    @AppStorage(DFLook.key) private var lookRaw = ""

    var body: some View {
        attach(
            Group {
                if let fold { folded(fold) } else { flat }
            }
            .background(Bento.bg.ignoresSafeArea())
            .tint(Bento.accent)
        )
    }

    /// Duo à plat (ouvert ou fermé) : une seule grille.
    private var flat: some View {
        GeometryReader { g in
            let wide = g.size.width >= 520
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    grid(wide: wide, width: min(g.size.width - 36, 1100))
                }
                .padding(.horizontal, 18)
                .padding(.top, 36)
                .padding(.bottom, 120)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Duo à moitié plié : deux pages, de part et d'autre du pli. On déplace les cartes d'une page à l'autre.
    private func folded(_ fold: BentoFold) -> some View {
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { full in
                let w = full.size.width, h = full.size.height
                if fold == .book {
                    HStack(spacing: 0) {
                        page(0, width: w / 2 - 34)
                            .padding(.leading, max(insets.leading, 18)).padding(.trailing, 16)
                            .padding(.top, max(insets.top, 16))
                            .frame(width: w / 2, height: h)
                        page(1, width: w / 2 - 34)
                            .padding(.trailing, max(insets.trailing, 18)).padding(.leading, 16)
                            .padding(.top, max(insets.top, 16))
                            .frame(width: w / 2, height: h)
                            .background(Bento.tray.opacity(0.45))
                    }
                } else {
                    VStack(spacing: 0) {
                        page(0, width: w - 36)
                            .padding(.horizontal, 18).padding(.top, max(insets.top, 16)).padding(.bottom, 10)
                            .frame(width: w, height: h / 2)
                        page(1, width: w - 36)
                            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, max(insets.bottom, 10))
                            .frame(width: w, height: h / 2)
                            .background(Bento.tray.opacity(0.45))
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func page(_ i: Int, width: CGFloat) -> some View {
        let ids = i < lists.count ? lists[i] : []
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if i == 0 { header }
                if editing && i == 0 { editHint }
                cards(ids, wide: width >= 520, start: i * 4, width: width)
                if editing {
                    // Lâcher ici : la carte passe en bas de cette page.
                    RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous)
                        .strokeBorder(Bento.accent.opacity(dropTarget == "page\(i)" ? 0.9 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .frame(height: 64)
                        .overlay(Image(systemName: "plus").foregroundStyle(Bento.accent))
                        .dropDestination(for: String.self) { items, _ in
                            if let from = items.first { moveToEnd(from, page: i) }
                            dropTarget = nil
                            return true
                        } isTargeted: { on in
                            if on { dropTarget = "page\(i)" } else if dropTarget == "page\(i)" { dropTarget = nil }
                        }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func attach<C: View>(_ content: C) -> some View {
        content
        .modifier(HingeReader { closed, degrees in model.hinge(closed: closed, degrees: degrees) })
        .sheet(isPresented: $showIdeas) { IdeasView().environment(model) }
        .sheet(isPresented: $showSettings) { SettingsView().environment(model).environment(store) }
        .sheet(isPresented: $showBoards) { LeaderboardView().environment(model).environment(store) }
        .sheet(isPresented: $showAuto) { AutoCountView().environment(model) }
        .sheet(isPresented: $showWeek) { WeekRecapView().environment(model) }
        .sheet(isPresented: $showShare) { ShareDaySheet().environment(model) }
        .sheet(isPresented: $showMonth) {
            if store.hasPlus { MonthRecapView().environment(model) } else { PlusView(reason: Text("The monthly recap is part of Foldly+.")).environment(model).environment(store) }
        }
        .sheet(isPresented: $showHours) { if store.hasPlus { HoursSheet().environment(model) } else { PlusView(reason: Text("Your hours are part of Foldly+.")).environment(model).environment(store) } }
        .sheet(isPresented: $showAdjust) { AdjustCountView().environment(model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showWidgets) { WidgetsHelpView().environment(model).environment(store) }
        .sheet(isPresented: $showHistory) { HistoryView().environment(model) }
        .sheet(item: $plusReason) { reason in PlusView(reason: reason.text(model.stats)).environment(model).environment(store) }
        .onOpenURL { url in
            if url.host == "plus" && !store.hasPlus { plusReason = .widget }
            if url.host == "week" { showWeek = true }
            if url.host == "month" { showMonth = true }
            if url.host == "hours" { showHours = true }
            if url.host == "boards" { showBoards = true }
            if url.host == "share" { showShare = true }
            if url.host == "settings" { showSettings = true }
            if url.host == "repos" { model.setRest(true) }
            if url.host == "utilise" { model.setRest(false) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            let d = UserDefaults.standard
            if !Demo.seeded && !store.hasPlus && model.stats.daysCounted >= 3 && !d.bool(forKey: "plusPromptShown") {
                d.set(true, forKey: "plusPromptShown")
                plusReason = .tracking
            } else if PlusNudgeRule.claimLimit(model.stats, hasPlus: store.hasPlus) {
                plusReason = .limit
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && plusReason == nil && PlusNudgeRule.claimLimit(model.stats, hasPlus: store.hasPlus) {
                plusReason = .limit
            }
        }
        .onAppear {
            // Écran vu des dizaines de fois par jour : l'entrée en ressort une seule fois par lancement.
            if BentoIntro.played || reduceMotion { appeared = true; return }
            BentoIntro.played = true
            DispatchQueue.main.async { appeared = true }
        }
        .onChange(of: model.claps) { _, _ in
            bump = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { withAnimation(.easeOut(duration: 0.3)) { bump = false } }
        }
    }

    // MARK: En haut

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Foldly").font(.system(.largeTitle, design: Bento.design).weight(.bold)).foregroundStyle(Bento.ink)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote).foregroundStyle(Bento.muted)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing.toggle() }
                wiggle = editing
            } label: {
                Group {
                    if editing { Text("Done").font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 14) }
                    else { Image(systemName: "square.grid.2x2").font(.body.weight(.medium)).foregroundStyle(Bento.ink).frame(width: 44) }
                }
                .frame(height: 44)
                .background(Capsule().fill(editing ? Bento.accent : Bento.card))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .accessibilityLabel(Text("Arrange cards"))
            LeaderboardButton(show: $showBoards).font(.body).frame(width: 44, height: 44)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.body.weight(.medium)).foregroundStyle(Bento.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(Bento.card))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .accessibilityLabel(Text("Settings"))
        }
    }

    // MARK: La grille (colonnes de hauteurs différentes)

    /// Deux colonnes de même largeur (sinon la première prend toute la place et écrase l'autre).
    private func row<A: View, B: View>(_ a: A, _ b: B, _ i: Int, width: CGFloat) -> some View {
        let half = max(120, (width - 12) / 2)
        return HStack(alignment: .top, spacing: 12) {
            a.frame(width: half).frame(maxHeight: .infinity)
            b.frame(width: half).frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(Pop(on: appeared, i: i))
    }

    private func one<A: View>(_ a: A, _ i: Int) -> some View {
        a.modifier(Pop(on: appeared, i: i))
    }

    /// L'entrée en ressort, rangée après rangée.
    private struct Pop: ViewModifier {
        let on: Bool
        let i: Int
        func body(content: Content) -> some View {
            content
                .scaleEffect(on ? 1 : 0.95)
                .opacity(on ? 1 : 0)
                .offset(y: on ? 0 : 14)
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28).delay(Double(i) * 0.04), value: on)
        }
    }

    // MARK: Cartes déplaçables
    //
    // L'ordre est gardé sur le téléphone. « Arranger » (en haut) fait trembler les cartes : on en attrape une
    // et on la lâche sur une autre pour prendre sa place.

    static let defaultOrder = ["today", "hinge", "week", "split", "closed", "hours", "lifetime", "actions"]
    static let all = Set(defaultOrder)
    /// Livre : le chiffre et la charnière à gauche, le détail à droite.
    static let defaultBook = [["today", "hinge", "split", "lifetime"], ["week", "closed", "hours", "actions"]]
    /// En L : en haut (debout) ce qu'on lit d'un coup d'œil, en bas (posé) le reste.
    static let defaultLaptop = [["today", "hinge"], ["split", "week", "hours", "closed", "lifetime", "actions"]]

    /// Les cartes de chaque page (une seule page à plat, deux à moitié plié). Gardé séparément pour chaque position.
    private var lists: [[String]] {
        func clean(_ raw: String, _ fallback: [[String]]) -> [[String]] {
            var seen = hidden
            var out = raw.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.split(separator: ",").map(String.init).filter { Self.all.contains($0) && seen.insert($0).inserted }
            }
            if raw.isEmpty || out.count != fallback.count { return fallback.map { $0.filter { !hidden.contains($0) } } }
            // Une carte nouvelle (ou perdue) revient en bas de la dernière page.
            out[out.count - 1] += Self.defaultOrder.filter { !seen.contains($0) }
            return out
        }
        switch fold {
        case .none: return clean(orderRaw, [Self.defaultOrder])
        case .book: return clean(bookRaw, Self.defaultBook)
        case .laptop: return clean(laptopRaw, Self.defaultLaptop)
        }
    }

    private func save(_ l: [[String]]?) {
        let raw = l.map { $0.map { $0.joined(separator: ",") }.joined(separator: "|") } ?? ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            switch fold {
            case .none: orderRaw = raw
            case .book: bookRaw = raw
            case .laptop: laptopRaw = raw
            }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func move(_ from: String, to: String) {
        guard from != to else { return }
        var l = lists
        for k in l.indices { l[k].removeAll { $0 == from } }
        guard let p = l.firstIndex(where: { $0.contains(to) }), let j = l[p].firstIndex(of: to) else { return }
        // Vers le bas de la même page : après la cible ; sinon : à sa place.
        let before = lists[p].firstIndex(of: from).map { $0 < (lists[p].firstIndex(of: to) ?? 0) } ?? false
        l[p].insert(from, at: before ? j + 1 : j)
        save(l)
    }

    private func moveToEnd(_ from: String, page: Int) {
        var l = lists
        guard page < l.count else { return }
        for k in l.indices { l[k].removeAll { $0 == from } }
        l[page].append(from)
        save(l)
    }

    private func card(_ id: String) -> AnyView {
        switch id {
        case "today": return AnyView(today)
        case "hinge": return AnyView(hinge)
        case "week": return AnyView(week)
        case "split": return AnyView(split)
        case "closed": return AnyView(closed)
        case "hours": return AnyView(hours)
        case "lifetime": return AnyView(lifetime)
        default: return AnyView(actions)
        }
    }

    /// Une carte, avec ce qu'il faut pour la déplacer en mode « Arranger ».
    private func movable(_ id: String) -> some View {
        card(id)
            .allowsHitTesting(!editing)
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous)
                        .strokeBorder(Bento.accent.opacity(dropTarget == id ? 0.9 : 0.25), style: StrokeStyle(lineWidth: dropTarget == id ? 3 : 1.5, dash: dropTarget == id ? [] : [6, 5]))
                        .background(Color.white.opacity(0.001))
                        .overlay(alignment: .topLeading) {
                            if id != "today" {
                                Button { hide(id) } label: {
                                    Image(systemName: "minus")
                                        .font(.caption.weight(.heavy)).foregroundStyle(.white)
                                        .frame(width: 26, height: 26).background(Circle().fill(Color.red.opacity(0.85)))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(Text("Hide this card"))
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 26, height: 26).background(Circle().fill(Bento.accent))
                                .padding(8)
                        }
                        .draggable(id) { card(id).frame(width: 220).opacity(0.9) }
                        .dropDestination(for: String.self) { items, _ in
                            if let from = items.first { move(from, to: id) }
                            dropTarget = nil
                            return true
                        } isTargeted: { on in
                            if on { dropTarget = id } else if dropTarget == id { dropTarget = nil }
                        }
                }
            }
            .rotationEffect(.degrees(editing ? (wiggle ? 0.6 : -0.6) : 0))
            .animation(editing ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: wiggle)
    }

    private static let small: Set<String> = ["lifetime"]

    /// Les cartes deux par deux (grand écran), ou les petites deux par deux (petit écran).
    private func rows(_ ids: [String], wide: Bool) -> [[String]] {
        var out: [[String]] = []
        var pending: String?
        for id in ids {
            let pairable = wide ? id != "actions" : Self.small.contains(id)
            if pairable {
                if let p = pending { out.append([p, id]); pending = nil } else { pending = id }
            } else {
                if let p = pending { out.append([p]); pending = nil }
                out.append([id])
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    private func hide(_ id: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { hiddenRaw = (hidden.union([id])).sorted().joined(separator: ",") }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func show(_ id: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { hiddenRaw = hidden.subtracting([id]).sorted().joined(separator: ",") }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func cardName(_ id: String) -> Text {
        switch id {
        case "today": return Text("Today")
        case "hinge": return Text("Hinge")
        case "week": return Text("This week")
        case "split": return Text("Open and closed")
        case "closed": return Text("Time closed")
        case "hours": return Text("Today by hour")
        case "lifetime": return Text("Since day one")
        default: return Text("Shortcuts")
        }
    }

    /// « Arranger » : déplacer, cacher, remettre les cartes, et choisir la couleur.
    private var editHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hold a card, then drop it where you want it. Tap − to hide it.")
                    .font(.footnote).foregroundStyle(Bento.muted)
                Spacer()
                Button { save(nil); withAnimation { hiddenRaw = "" } } label: { Text("Reset").font(.footnote.weight(.semibold)) }
            }
            let gone = Self.defaultOrder.filter { hidden.contains($0) }
            if !gone.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(gone, id: \.self) { id in
                            Button { show(id) } label: {
                                Label { cardName(id) } icon: { Image(systemName: "plus") }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12).frame(minHeight: 36)
                                    .background(Capsule().fill(Bento.card))
                                    .overlay(Capsule().strokeBorder(Bento.accent.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Bento.ink)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 10) {
                Text("Color").font(.footnote.weight(.medium)).foregroundStyle(Bento.muted)
                let current = Bento.atelier ? atelierAccent : bentoAccent
                ForEach(0..<Bento.palette.count, id: \.self) { i in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { if Bento.atelier { atelierAccent = i } else { bentoAccent = i } }
                    } label: {
                        Group {
                            if i == 0 {
                                Circle().strokeBorder(Bento.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .overlay(Text("A").font(.caption2.weight(.bold)).foregroundStyle(Bento.muted))
                            } else {
                                Circle().fill(Bento.palette[i])
                            }
                        }
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Bento.ink, lineWidth: current == i ? 2.5 : 0).padding(-4))
                        .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(i == 0 ? Text("Theme color") : Text("Color \(i)"))
                }
            }
        }
        .padding(.horizontal, 4)
        .id("\(bentoAccent)-\(atelierAccent)")
    }

    /// L'essai sans Foldly+ : combien de temps il reste, et Foldly+ pour le garder.
    private var trialCard: some View {
        Button { plusReason = .theme } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: Bento.rTile, style: .continuous).fill(Bento.accent))
                VStack(alignment: .leading, spacing: 2) {
                    if let end = ThemeTrial.end {
                        Text(String(format: NSLocalizedString("Free trial until %@", comment: ""), end.formatted(date: .abbreviated, time: .shortened)))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Bento.ink)
                    }
                    Text("Keep this theme with Foldly+, a one-time purchase.").font(.caption).foregroundStyle(Bento.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Bento.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous).fill(Bento.tint))
        }
        .buttonStyle(Press())
    }

    @ViewBuilder private func cards(_ ids: [String], wide: Bool, start: Int, width: CGFloat) -> some View {
        let rs = rows(ids, wide: wide)
        ForEach(Array(rs.enumerated()), id: \.element) { i, r in
            if r.count == 2 {
                row(movable(r[0]), movable(r[1]), start + i + 1, width: width)
            } else {
                one(movable(r[0]), start + i + 1)
            }
        }
    }

    @ViewBuilder private func grid(wide: Bool, width: CGFloat) -> some View {
        let showAuto = model.stats.autoLast == nil && !Demo.seeded
        let showPromo = !foldboardPromoHidden && FoldboardPromoRule.shouldShow
        VStack(spacing: 12) {
            if editing { editHint }
            if !store.hasPlus && ThemeTrial.active && !editing { one(trialCard, 0) }
            if showAuto && !editing { one(autoCard, 0) }
            if showPromo && !editing { one(promo, 0) }
            if !ideasHidden && !editing { one(ideasCard, 0) }
            cards(lists.first ?? [], wide: wide, start: 0, width: width)
        }
    }

    private var closed: some View {
        white {
            VStack(alignment: .leading, spacing: 10) {
                label(Text("Time closed"))
                ClosedTimeContent(stats: model.stats, accent: Bento.accent)
            }
        }
    }

    private var ideasCard: some View {
        white {
            IdeasPromo { showIdeas = true } onHide: {
                IdeasRule.promoHidden = true
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { ideasHidden = true }
            }
        }
    }

    private var promo: some View {
        white {
            FoldboardPromo { openURL(FoldboardPromoRule.url) } onHide: {
                FoldboardPromoRule.hide()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { foldboardPromoHidden = true }
            }
        }
    }

    // MARK: Les cartes

    private func white<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous).fill(Bento.card))
            .overlay(RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous).strokeBorder(Bento.atelier ? Bento.line : .clear))
            .shadow(color: .black.opacity(Bento.atelier ? 0 : 0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(Bento.atelier ? 0 : 0.06), radius: 14, y: 6)
    }

    private func trayCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous).fill(Bento.tray))
    }

    private func darkCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous).fill(Bento.dark))
            .environment(\.colorScheme, .dark)
    }

    private func label(_ t: Text) -> some View {
        t.font(.footnote.weight(.medium)).foregroundStyle(Bento.muted)
    }

    /// Aujourd'hui : le grand chiffre, et l'anneau jusqu'au repère (moyenne ou limite).
    private var today: some View {
        let s = model.stats
        return darkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Today").font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("+1").font(.footnote.weight(.semibold)).foregroundStyle(Bento.accent)
                        .opacity(bump ? 1 : 0).offset(y: bump ? 0 : 8)
                }
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: max(0.02, min(1, s.progress)))
                            .stroke(Bento.atelier ? AnyShapeStyle(Bento.accent) : AnyShapeStyle(AngularGradient(colors: [Bento.accent.opacity(0.6), Bento.accent], center: .center)),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: s.progress)
                        Image(systemName: "rectangle.compress.vertical").font(.title3).foregroundStyle(.white)
                    }
                    .frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(FoldUnit.shown(s.today))")
                            .font(.system(size: heroSize, weight: .semibold, design: Bento.design))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: s.today)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text("folds today").font(.subheadline).foregroundStyle(.white.opacity(0.55))
                    }
                }
                statusText.font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            }
            .contentShape(Rectangle())
            .onTapGesture { if !model.hasHinge { model.clap() } }
            .onLongPressGesture { showAdjust = true }
        }
    }

    private var statusText: Text {
        let s = model.stats
        if s.goalOn {
            let left = s.left()
            if left > 0 { return Text("\(FoldUnit.shown(left)) left today") }
            if left == 0 { return Text("Limit reached") }
            return Text("\(FoldUnit.shown(-left)) over the limit")
        }
        return AverageText.status(today: s.today, average: s.averageRef())
    }

    /// La charnière, en direct : un arc qui suit l'angle du téléphone, et un point qui pulse quand il est ouvert.
    private var hinge: some View {
        let deg = model.degrees ?? 0
        let open = deg > 20
        return white {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label(Text("Hinge"))
                    Spacer()
                    // Une seule onde quand le Duo s'ouvre ou se ferme, pas de clignotement permanent.
                    Circle().fill(open ? Bento.accent : Bento.muted.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Bento.accent.opacity(pulse ? 0 : 0.4), lineWidth: 5).scaleEffect(pulse ? 2.4 : 1))
                        .onChange(of: open) { _, _ in
                            guard !reduceMotion else { return }
                            pulse = false
                            withAnimation(.easeOut(duration: 0.6)) { pulse = true }
                        }
                    (open ? Text("Open") : Text("Closed")).font(.caption.weight(.semibold)).foregroundStyle(open ? Bento.accent : Bento.muted)
                }
                ZStack(alignment: .bottom) {
                    Circle().trim(from: 0.5, to: 1).stroke(Bento.tray, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    Circle().trim(from: 0.5, to: 0.5 + 0.5 * min(1, deg / 180))
                        .stroke(Bento.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: deg)
                    Text(model.degrees == nil ? "—" : "\(Int(deg))°")
                        .font(.system(size: bigSize, weight: .semibold, design: Bento.design)).monospacedDigit().foregroundStyle(Bento.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: Int(deg))
                }
                .frame(height: 92)
                .frame(maxWidth: 200)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// La semaine : sept barres qui montent en ressort, aujourd'hui en bleu.
    private var week: some View {
        let s = model.stats
        let days = s.lastWeek()
        let top = Double(max(1, days.map(\.closes).max() ?? 1, s.reference() ?? 0))
        return trayCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(.system(.subheadline, design: Bento.design).weight(.semibold)).foregroundStyle(Bento.ink)
                    Spacer()
                    Text("\(s.weekTotal)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Bento.muted)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<days.count, id: \.self) { i in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(i == days.count - 1 ? Bento.accent : Bento.card)
                                .frame(height: appeared ? max(6, 92 * CGFloat(Double(days[i].closes) / top)) : 6)
                                .animation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.25 + Double(i) * 0.05), value: appeared)
                            Text(days[i].date, format: .dateTime.weekday(.narrow))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(i == days.count - 1 ? Bento.ink : Bento.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 118, alignment: .bottom)
                Button { showWeek = true } label: {
                    Text("Weekly recap").font(.footnote.weight(.semibold))
                }
            }
        }
    }

    /// Ouvert ou fermé aujourd'hui, en une barre.
    private var split: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let s = model.stats
            let now = ctx.date
            let open = s.openTime(now, now: now), closed = s.closedTime(now, now: now)
            let share = open + closed > 0 ? open / (open + closed) : 0
            white {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            label(Text("Open"))
                            Text(TimeFormat.narrow(open)).font(.system(size: midSize, weight: .semibold, design: Bento.design)).monospacedDigit().foregroundStyle(Bento.ink)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            label(Text("Closed"))
                            Text(s.autoLast == nil && closed == 0 ? "—" : TimeFormat.narrow(closed))
                                .font(.system(size: midSize, weight: .semibold, design: Bento.design)).monospacedDigit().foregroundStyle(Bento.ink)
                        }
                    }
                    GeometryReader { g in
                        HStack(spacing: 4) {
                            Capsule().fill(Bento.accent).frame(width: max(8, (g.size.width - 4) * share))
                            Capsule().fill(Bento.tray)
                        }
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: share)
                    }
                    .frame(height: 10)
                }
            }
        }
    }

    private var hours: some View {
        white {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label(Text("Today by hour"))
                    Spacer()
                    Button { showHours = true } label: { Image(systemName: "arrow.up.right").font(.caption.weight(.bold)) }
                }
                TodayByHour(stats: model.stats, accent: Bento.accent, empty: Bento.tray, height: 54)
            }
        }
    }

    /// Le total depuis le début, en chiffres qui roulent.
    private var lifetime: some View {
        trayCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    label(Text("Since day one"))
                    Text(model.stats.totalCloses, format: .number)
                        .font(.system(size: bigSize, weight: .semibold, design: Bento.design)).monospacedDigit().foregroundStyle(Bento.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.stats.totalCloses)
                }
                Spacer()
                Image(systemName: "infinity").font(.title2.weight(.semibold)).foregroundStyle(Bento.accent)
                    .frame(width: 46, height: 46).background(Circle().fill(Bento.tint))
            }
        }
    }

    /// Les raccourcis, sur une carte sombre.
    private var actions: some View {
        darkCard {
            HStack(spacing: 10) {
                pill("square.and.arrow.up", Text("Share")) { showShare = true }
                pill("calendar", Text("Monthly recap")) { showMonth = true }
                pill("clock.arrow.circlepath", Text("History")) {
                    if store.hasPlus { showHistory = true } else { plusReason = .history }
                }
            }
        }
    }

    private func pill(_ icon: String, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.body.weight(.semibold))
                title.font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Bento.rTile, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(Press())
    }

    /// Retour au toucher : 0,97 à l'appui, en 120 ms.
    private struct Press: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    private var autoCard: some View {
        Button { showAuto = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.badge.automatic").font(.title3).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: Bento.rTile, style: .continuous).fill(Bento.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count even when the app is closed").font(.subheadline.weight(.semibold)).foregroundStyle(Bento.ink)
                    Text("Set up the Shortcuts automation in a minute.").font(.caption).foregroundStyle(Bento.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Bento.rCard, style: .continuous).fill(Bento.tint))
        }
        .buttonStyle(Press())
    }
}
