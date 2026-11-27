// Onboarding.swift — Vicefold
//
// La présentation de l'app, à la première ouverture (et rouvrable depuis les réglages) : cinq pages animées qui
// disent ce que fait l'app et la règlent. 1. bienvenue ; 2. la carte ; 3. le 100 % et les widgets ; 4. toi (prénom,
// où tu en es dans l'histoire pour ne rien te dévoiler, alertes de nouveaux guides : la permission n'est demandée
// qu'ici, si tu actives l'interrupteur) ; 5. gratuit ou Pro (comme le vend Store.swift : tous les guides restent
// gratuits). Sur le Duo ouvert et l'iPad : l'illustration d'un côté du pli, le texte et les boutons de l'autre.
// Avec « Réduire les animations » : des fondus, et des illustrations immobiles.

import SwiftUI

struct OnboardingFlow: View {
    var finish: () -> Void
    @Environment(Progress.self) private var progress
    @Environment(ContentStore.self) private var content
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = min(OnboardingFlow.count - 1, ShotMode.onboardingPage ?? 0)
    @State private var forward = true
    @State private var name = ""
    @State private var chapter = 1
    @State private var alerts = Alerts.shared
    @State private var showPro = false

    static let count = 5

    var body: some View {
        GeometryReader { geo in
            let fold = DualLayout<EmptyView, EmptyView>.fold(geo)
            let wide = fold != nil || geo.size.width >= 740
            ZStack {
                VFBackdrop(vivid: true)
                if wide {
                    HStack(spacing: 0) {
                        // L'illustration garde une forme agréable même sur un grand écran (iPad).
                        ZStack { hero.frame(maxWidth: 560, maxHeight: 680).padding(28).id(page).transition(turn) }
                            .frame(width: fold?.minX ?? geo.size.width / 2)
                            .frame(maxHeight: .infinity)
                        Color.clear.frame(width: fold?.width ?? 0)
                        VStack(spacing: 0) {
                            topBar
                            ZStack {
                                centered { copy.padding(.horizontal, 28).padding(.vertical, 18).frame(maxWidth: 520) }
                                    .id(page)
                                    .transition(turn)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            bottomBar
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        topBar
                        ZStack {
                            centered {
                                VStack(spacing: 22) {
                                    hero.frame(height: heroHeight(geo.size.height))
                                    copy
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .frame(maxWidth: 560)
                            }
                            .id(page)
                            .transition(turn)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        bottomBar
                    }
                }
            }
        }
        .simultaneousGesture(swipe)
        .sheet(isPresented: $showPro) { ProView() }
        .onAppear {
            name = progress.data.name
            chapter = max(1, progress.data.chapter)
        }
    }

    /// Le contenu d'une page, centré en hauteur s'il tient, défilant sinon (y compris quand le clavier est là :
    /// la vue reste la même, le champ de texte garde la main).
    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        let inner = content()
        return GeometryReader { box in
            ScrollView {
                inner.frame(maxWidth: .infinity, minHeight: box.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Tourner les pages

    private var turn: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(_ to: Int) {
        guard to >= 0, to < Self.count, to != page else { return }
        forward = to > page
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : VFMotion.reveal) { page = to }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) * 1.5, abs(v.translation.width) > 60 else { return }
            go(v.translation.width < 0 ? page + 1 : page - 1)
        }
    }

    private func complete() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n != progress.data.name || chapter != progress.data.chapter {
            progress.edit { $0.name = n; $0.chapter = chapter }
        }
        finish()
    }

    private func heroHeight(_ h: CGFloat) -> CGFloat {
        let share: CGFloat = [0.40, 0.40, 0.34, 0.24, 0.30][page]
        return max(page >= 3 ? 130 : 200, min(380, h * share))
    }

    // MARK: Les barres

    private var topBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? AnyShapeStyle(VF.gradient) : AnyShapeStyle(Color.white.opacity(i < page ? 0.45 : 0.16)))
                    .frame(width: i == page ? 26 : 8, height: 4)
                    .shadow(color: i == page ? VF.flamingo.opacity(0.7) : .clear, radius: 5)
            }
            Spacer()
            if page < Self.count - 1 {
                Button("Skip") { complete() }
                    .buttonStyle(.vf(.secondary, compact: true))
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(page + 1) of \(Self.count)")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button { go(page - 1) } label: { Image(systemName: "chevron.left").frame(width: 22) }
                    .buttonStyle(.vfSecondary)
                    .accessibilityLabel("Back")
            }
            if page < Self.count - 1 {
                Button { go(page + 1) } label: { Text("Continue").frame(maxWidth: .infinity) }
                    .buttonStyle(.vfPrimary)
            } else {
                Button { complete() } label: { Text("Start exploring").frame(maxWidth: .infinity) }
                    .buttonStyle(.vfPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    // MARK: Les pages

    @ViewBuilder private var hero: some View {
        switch page {
        case 0: WelcomeHero()
        case 1: MapHero(places: content.content.places.count)
        case 2: TrackerHero(snapshot: progress.snapshot())
        case 3: ProfileHero(name: name)
        default: ProHero()
        }
    }

    @ViewBuilder private var copy: some View {
        switch page {
        case 0:
            OnbCopy(kicker: "Unofficial fan companion", title: "Welcome to Vicefold",
                    text: "Your companion for Leonida: guides, a map with your own pins, and every mission on your way to 100%.") {
                VStack(alignment: .leading, spacing: 14) {
                    FeatureChips()
                    // Ce qu'il y a vraiment dans le guide, compté dans son contenu.
                    StatStrip(items: [("Missions", content.missions.count), ("Places", content.content.places.count),
                                      ("Vehicles", VehicleStore.shared.list.vehicles.count), ("Easter eggs", content.content.eggs.count)])
                }
            }
        case 1:
            OnbCopy(kicker: "Map", title: "Every corner of Leonida",
                    text: "A detailed fan map with filters by category and your own pins. Mark each place as you visit it.") {
                OnbPoint(icon: "rectangle.split.2x1", color: VF.cyan, title: "Made for the Duo", text: "Open it: the list on one side, the map on the other.")
            }
        case 2:
            OnbCopy(kicker: "Tracker", title: "Chase the 100%",
                    text: "Tick off missions, places, collectibles and challenges. Your progress follows you to the Home Screen and the Lock Screen.") {
                OnbPoint(icon: "bubble.left.and.bubble.right", color: VF.flamingo, title: "Stuck? Ask the community", text: "Ask the community or help someone stuck here.")
            }
        case 3:
            OnbCopy(kicker: "Spoiler-free", title: "Make it yours",
                    text: "Nothing past your chapter shows up unless you ask.") {
                setup
            }
        default:
            OnbCopy(kicker: "Yours only", title: "Free to explore",
                    text: "Every guide stays free. Pro is for the map and your progress.") {
                proBlock
            }
        }
    }

    private var setup: some View {
        @Bindable var alerts = alerts
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill").foregroundStyle(VF.cyan).frame(width: 24)
                TextField("Your name (optional)", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.done)
            }
            .vfCard(radius: 16, padding: 14)
            HStack(spacing: 12) {
                Image(systemName: "book.pages.fill").foregroundStyle(VF.cyan).frame(width: 24)
                Text("Where are you in the story?").font(.subheadline).foregroundStyle(VF.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Picker("Where are you in the story?", selection: $chapter) {
                    Text("Just starting").tag(1)
                    ForEach(content.chapters.dropFirst()) { c in Text("Chapter \(c.id)").tag(c.id) }
                }
                .labelsHidden()
                .tint(VF.flamingo)
            }
            .vfCard(radius: 16, padding: 14)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $alerts.enabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill").foregroundStyle(VF.cyan).frame(width: 24)
                        Text("New guide alerts").font(.subheadline).foregroundStyle(VF.text)
                    }
                }
                .tint(VF.flamingo)
                Text("A notification when new guides arrive. Nothing about you is sent.")
                    .font(.caption).foregroundStyle(VF.textDim)
                    .padding(.leading, 36)
                if alerts.denied && alerts.enabled {
                    Text("Notifications are off for Vicefold in Settings.").font(.caption).foregroundStyle(VF.sun).padding(.leading, 36)
                }
            }
            .vfCard(radius: 16, padding: 14)
        }
    }

    private var proBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                proPerk("square.3.layers.3d", "Every map layer")
                proPerk("icloud", "iCloud sync")
                proPerk("square.grid.2x2", "Progress widgets")
            }
            .vfCard(radius: 18, padding: 14, tint: VF.flamingo)
            if store.isPro {
                Label("Pro is on", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(VF.palm)
            } else {
                Button { showPro = true } label: { Label("See Vicefold Pro", systemImage: "star.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.vfSecondary)
            }
            Label("No account, no ads, no tracking.", systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(VF.textDim)
        }
    }

    private func proPerk(_ icon: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(VF.sunset).frame(width: 24)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(VF.text)
            Spacer(minLength: 0)
            Text("Pro").font(VF.mono(10, weight: .bold)).foregroundStyle(VF.ink)
                .padding(.horizontal, 7).padding(.vertical, 3).background(VF.gradient, in: .capsule)
        }
    }
}

// MARK: - Le texte d'une page

private struct OnbCopy<Extra: View>: View {
    var kicker: LocalizedStringKey
    var title: LocalizedStringKey
    var text: LocalizedStringKey
    @ViewBuilder var extra: Extra
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kicker).vfHUD(VF.cyan, size: 11).vfAppear(shown, index: 0)
            Text(title)
                .font(VF.display(40))
                .foregroundStyle(VF.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .vfAppear(shown, index: 1)
            Text(text).font(.body).foregroundStyle(VF.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .vfAppear(shown, index: 2)
            extra.padding(.top, 4).vfAppear(shown, index: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { shown = true }
    }
}

private struct OnbPoint: View {
    var icon: String
    var color: Color
    var title: LocalizedStringKey
    var text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VFIconBadge(icon: icon, color: color, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(VF.text)
                Text(text).font(.subheadline).foregroundStyle(VF.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .vfCard(radius: 18, padding: 14)
    }
}

/// Quatre chiffres clés, en néon.
private struct StatStrip: View {
    var items: [(LocalizedStringKey, Int)]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<items.count, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(verbatim: "\(items[i].1)").font(VF.display(26, relativeTo: .title2)).monospacedDigit()
                        .foregroundStyle(VF.gradient).shadow(color: VF.flamingo.opacity(0.5), radius: 8)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(items[i].0).font(.caption2.weight(.semibold)).foregroundStyle(VF.textDim)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .vfCard(radius: 18, padding: 12)
    }
}

/// Ce que fait l'app, en cinq pastilles.
private struct FeatureChips: View {
    private let items: [(String, LocalizedStringKey, Color)] = [
        ("map.fill", "Map", VF.cyan), ("checklist", "100% tracker", VF.flamingo), ("book.pages.fill", "Guides", VF.sun),
        ("bubble.left.and.bubble.right.fill", "Community", VF.sky), ("square.grid.2x2.fill", "Widgets", VF.palm),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { chip(0); chip(1); chip(2) }
                HStack(spacing: 8) { chip(3); chip(4) }
            }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(0..<items.count, id: \.self) { chip($0) }
    }

    private func chip(_ i: Int) -> some View {
        Label { Text(items[i].1).lineLimit(1).fixedSize() } icon: { Image(systemName: items[i].0).foregroundStyle(items[i].2) }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(VF.text)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(items[i].2.opacity(0.12), in: .capsule)
            .overlay(Capsule().stroke(items[i].2.opacity(0.45), lineWidth: 1))
    }
}

// MARK: - Les illustrations

/// Un cadre d'illustration : coins doux, filet lumineux, repères d'angle.
private struct HeroFrame<Content: View>: View {
    var tint: Color = VF.cyan
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(LinearGradient(colors: [tint.opacity(0.7), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .vfTicks(tint, length: 14, inset: 12)
            .shadow(color: tint.opacity(0.25), radius: 24)
            .accessibilityHidden(true)
    }
}

/// Page 1 : le lever de soleil et le nom de l'app.
private struct WelcomeHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HeroFrame(tint: VF.flamingo) {
            GeometryReader { g in
                ZStack {
                    if reduceMotion || ShotMode.route != nil {
                        SynthScene(time: 0, sunrise: 1)
                    } else {
                        TimelineView(.animation) { tl in
                            SynthScene(time: tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600), sunrise: 1)
                        }
                    }
                    NeonWordmark(lit: [], size: min(g.size.width / 6.2, g.size.height * 0.18, 84))
                        .position(x: g.size.width / 2, y: g.size.height * 0.20)
                }
            }
        }
    }
}

/// Page 2 : la vraie carte, en hologramme, balayée par un radar, avec quelques repères qui battent.
private struct MapHero: View {
    var places: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let pins: [(CGFloat, CGFloat, Color, String)] = [
        (0.30, 0.34, VF.flamingo, "building.columns.fill"), (0.66, 0.26, VF.sun, "bed.double.fill"), (0.74, 0.60, VF.cyan, "fork.knife"),
        (0.24, 0.70, VF.palm, "leaf.fill"), (0.50, 0.52, VF.sky, "bag.fill"),
    ]

    var body: some View {
        HeroFrame(tint: VF.cyan) {
            GeometryReader { g in
                ZStack {
                    MapPostcard(focus: CGPoint(x: 0.775, y: 0.5), zoom: 2.6)
                    RadarSweep(period: 5)
                    ForEach(0..<pins.count, id: \.self) { i in
                        let p = pins[i]
                        ZStack {
                            Circle().stroke(p.2.opacity(0.7), lineWidth: 1.5)
                                .frame(width: 30, height: 30)
                                .scaleEffect(pulse ? 2.1 : 1)
                                .opacity(pulse ? 0 : 0.9)
                                .animation(reduceMotion ? nil : .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.3), value: pulse)
                            Image(systemName: p.3)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(p.2)
                                .frame(width: 30, height: 30)
                                .background(VF.ink.opacity(0.9), in: .circle)
                                .overlay(Circle().stroke(p.2, lineWidth: 1.5))
                                .shadow(color: p.2.opacity(0.9), radius: 7)
                        }
                        .position(x: g.size.width * p.0, y: g.size.height * p.1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(places) places").font(VF.display(26, relativeTo: .title2)).foregroundStyle(VF.text)
                            .shadow(color: .black.opacity(0.8), radius: 6)
                        Text("Map © GTADB.org · CC BY 4.0").font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .background(LinearGradient(colors: [.clear, VF.abyss.opacity(0.85)], startPoint: .center, endPoint: .bottom))
                }
            }
        }
        .onAppear {
            guard !reduceMotion, ShotMode.route == nil else { return }
            pulse = true
        }
    }
}

/// Page 3 : l'anneau qui se remplit jusqu'à 100 %, et le widget avec ta vraie progression.
private struct TrackerHero: View {
    var snapshot: VFSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.height, (g.size.width - 16) / 2, 220)
            let stacked = g.size.height > g.size.width * 1.25
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 26)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                ZStack {
                    VFRing(parts: filled ? [1, 1, 1, 1] : [0.04, 0.03, 0.02, 0.01], lineWidth: side * 0.06, gap: side * 0.018)
                    VStack(spacing: 0) {
                        Text(verbatim: "100%").font(VF.display(side * 0.13)).foregroundStyle(VF.gradient)
                            .shadow(color: VF.flamingo.opacity(0.6), radius: 10)
                            .opacity(filled ? 1 : 0.25)
                    }
                }
                .frame(width: side, height: side)
                VFWidgetFace(snap: snapshot, size: .small)
                    .padding(14)
                    .frame(width: side * 0.92, height: side * 0.92)
                    .background(VFWidgetBackground())
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VF.hairline, lineWidth: 1))
                    .shadow(color: VF.flamingo.opacity(0.3), radius: 18)
                    .rotationEffect(.degrees(reduceMotion ? 0 : 4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion || ShotMode.route != nil { filled = true; return }
            withAnimation(.easeOut(duration: 1.6).delay(0.25)) { filled = true }
        }
    }
}

/// Page 4 : ton profil, qui se met à jour pendant que tu écris ton prénom.
private struct ProfileHero: View {
    var name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        GeometryReader { g in
            let side = min(g.size.height * 0.78, g.size.width * 0.5, 190)
            let stacked = g.size.height > 260
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 18))
            layout {
                ZStack {
                    Circle()
                        .stroke(AngularGradient(colors: [VF.flamingo, VF.sunset, VF.cyan, VF.flamingo], center: .center), lineWidth: 3)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .shadow(color: VF.flamingo.opacity(0.7), radius: 10)
                    Text(verbatim: trimmed.first.map { String($0).uppercased() } ?? "V")
                        .font(VF.display(side * 0.46))
                        .foregroundStyle(VF.text)
                        .frame(width: side - 16, height: side - 16)
                        .background(VF.dusk, in: .circle)
                        .contentTransition(.opacity)
                }
                .frame(width: side, height: side)
                VStack(alignment: stacked ? .center : .leading, spacing: 4) {
                    Text(trimmed.isEmpty ? String(localized: "Welcome to Leonida") : String(localized: "Hi \(trimmed)"))
                        .font(VF.display(30, relativeTo: .title))
                        .foregroundStyle(VF.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .animation(.easeInOut(duration: 0.2), value: trimmed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, ShotMode.route == nil else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// Page 5 : l'étoile de Pro.
private struct ProHero: View {
    var body: some View {
        GeometryReader { g in
            ProEmblem(size: min(g.size.height * 0.95, g.size.width * 0.6, 240))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
