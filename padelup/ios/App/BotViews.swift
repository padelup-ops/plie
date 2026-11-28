import CoreLocation
import SwiftUI

// RÉSA AUTO : « dis-moi quand tu veux jouer, je m'occupe du reste ».
// Quatre questions, une par écran, en grand : où, quels jours, quel moment, combien de temps. Puis le billet, et c'est parti.
// Tout le reste (ouverture des créneaux, fréquence de lecture…) se règle tout seul ; les curieux ont « Plus d'options ».

// MARK: - Moments de la journée

enum PlayMoment: String, CaseIterable, Identifiable {
    case morning, noon, afternoon, evening, any
    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: return "Matin"
        case .noon: return "Midi"
        case .afternoon: return "Aprèm"
        case .evening: return "Soir"
        case .any: return "Peu importe"
        }
    }

    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .noon: return "sun.max.fill"
        case .afternoon: return "sun.haze.fill"
        case .evening: return "moon.stars.fill"
        case .any: return "clock.fill"
        }
    }

    /// Début au plus tôt / au plus tard (minutes depuis minuit).
    var range: (Int, Int) {
        switch self {
        case .morning: return (8 * 60, 11 * 60 + 30)
        case .noon: return (12 * 60, 13 * 60 + 30)
        case .afternoon: return (14 * 60, 17 * 60 + 30)
        case .evening: return (18 * 60, 21 * 60 + 30)
        case .any: return (8 * 60, 21 * 60 + 30)
        }
    }

    var hours: String {
        let end = range.1 % 60 == 0 ? "\(range.1 / 60) h" : "\(range.1 / 60) h \(range.1 % 60)"
        return "\(range.0 / 60) h – " + end
    }

    static func of(_ rule: BotRule) -> PlayMoment {
        allCases.first { $0.range.0 == rule.timeFrom && $0.range.1 == rule.timeTo } ?? .any
    }
}

extension BotRule {
    var moment: PlayMoment { PlayMoment.of(self) }

    /// « en semaine », « le week-end », « le mardi et le jeudi »…
    var daysPhrase: String {
        let full = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
        if weekdays.count == 7 { return "tous les jours" }
        if weekdays == [0, 1, 2, 3, 4] { return "en semaine" }
        if weekdays == [5, 6] { return "le week-end" }
        let names = weekdays.sorted().map { full[$0] }
        guard let last = names.last else { return "" }
        return names.count == 1 ? "le \(last)" : "le " + names.dropLast().joined(separator: ", ") + " et le \(last)"
    }
}

/// Les sept jours en petites balles : jaunes les jours où l'on joue.
struct DayBalls: View {
    var days: Set<Int>
    var size: CGFloat = 26
    private let letters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: size * 0.22) {
            ForEach(0..<7, id: \.self) { d in
                let on = days.contains(d)
                Text(letters[d])
                    .font(.system(size: size * 0.42, weight: .bold).width(.expanded))
                    .foregroundStyle(on ? UI.onBall : UI.faint)
                    .frame(width: size, height: size)
                    .background(Circle().fill(on ? UI.ball : Color.clear))
                    .overlay(Circle().strokeBorder(on ? UI.onBall.opacity(0.25) : UI.rule, lineWidth: 1))
            }
        }
        .accessibilityLabel(days.sorted().map { BotRule.dayNames[$0] }.joined(separator: ", "))
    }
}

// MARK: - L'écran « Résa auto »

struct BotView: View {
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @State private var showEditor = false
    @State private var booking: BookingRequest? = nil
    @State private var login: BotProvider? = nil
    @State private var accountsVersion = 0

    var body: some View {
        Screen(title: "Résa auto", eyebrow: "Je guette, tu joues", accessory: {
            if !bot.rules.isEmpty {
                RoundIconButton(systemImage: "plus", filled: true) { showEditor = true }.accessibilityLabel("Programmer une partie")
            }
        }) {
            if let snipe = bot.snipe { SnipePanel(snipe: snipe) }
            if bot.rules.isEmpty {
                AutoHero { showEditor = true }
            } else {
                rulesBlock
            }
            accountsBlock
            historyBlock
        }
        .refreshable { await bot.runAll() }
        .onReceive(NotificationCenter.default.publisher(for: .webAccountChanged)) { _ in accountsVersion += 1 }
        .onAppear { if ShotMode.current?.hasPrefix("wizard") == true { showEditor = true } }
        .sheet(isPresented: $showEditor) { RuleEditorView(prefill: nil) }
        .sheet(item: $booking) { r in BookingFlowSheet(request: r) }
        .sheet(item: $login) { p in ProviderWebSheet(provider: p, url: WebAccount.loginURL(p), title: "Connexion \(p.name)") }
    }

    private var rulesBlock: some View {
        let found = bot.log.filter { $0.kind == .found }.count
        let booked = bot.log.filter { $0.kind == .booked }.count
        return Block(title: "En veille", meta: found + booked == 0 ? nil : "\(found) trouvé\(found > 1 ? "s" : "") · \(booked) réservé\(booked > 1 ? "s" : "")",
                     live: bot.rules.contains { $0.active }) {
            VStack(spacing: 16) {
                ForEach(bot.rules) { rule in AutoRuleCard(rule: rule) }
            }
        }
    }

    private var accountsBlock: some View {
        let _ = accountsVersion
        return Block(title: "Tes comptes") {
            VStack(spacing: 0) {
                accountRow(.playtomic)
                Hairline()
                accountRow(.anybuddy)
                Text("Tu te connectes sur leur site, dans l'app : ton mot de passe ne passe jamais par PadelUp.")
                    .font(UI.small()).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private func accountRow(_ p: BotProvider) -> some View {
        let connected = WebAccount.isConnected(p) || (ShotMode.current != nil && p == .playtomic)
        return HStack(spacing: 12) {
            Text(String(p.name.prefix(1)))
                .font(.system(size: 15, weight: .bold).width(.expanded))
                .foregroundStyle(connected ? UI.onBall : UI.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(connected ? UI.ball : UI.sunken))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(UI.headline()).foregroundStyle(UI.ink)
                Text(connected ? "Connecté : je réserve avec ton compte" : "À connecter pour réserver en un geste")
                    .font(UI.caption()).foregroundStyle(UI.muted)
            }
            Spacer(minLength: 8)
            if connected {
                Menu {
                    Button("Déconnecter", role: .destructive) { Task { await WebAccount.disconnect(p); accountsVersion += 1 } }
                } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.muted).frame(width: 32, height: 32) }
            } else {
                Button("Connecter") { login = p }.buttonStyle(LinkButtonStyle())
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var historyBlock: some View {
        if !bot.log.isEmpty {
            Block(title: "Historique") {
                VStack(spacing: 0) {
                    let items = Array(bot.log.prefix(6))
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                        JournalRow(entry: entry, last: i == items.count - 1) { url in
                            booking = BookingRequest(url: url, target: entry.slotStart.map {
                                BookingTarget(time: FR.time($0), duration: entry.duration, start: $0, clubName: entry.clubName, court: entry.court, price: entry.price)
                            })
                        }
                    }
                }
            }
        }
    }
}

/// L'invitation, quand rien n'est programmé : une balle qui rebondit, trois étapes, un bouton jaune.
struct AutoHero: View {
    var start: () -> Void
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                BallMark(size: 46)
                    .offset(y: bounce ? -14 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: bounce)
                Spacer()
                Stamp(text: "Nouveau")
            }
            Text("Ta prochaine partie se réserve toute seule.")
                .font(UI.display(28)).foregroundStyle(UI.paper).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                stepLine("1", "Choisis ton club")
                stepLine("2", "Tes jours, ton moment")
                stepLine("3", "Je guette et je te prépare la résa")
            }
            Button(action: start) { Label("Programmer ma partie", systemImage: "bolt.fill") }
                .buttonStyle(PrimaryButtonStyle(fill: UI.ball, text: UI.onBall))
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(UI.ink))
        .onAppear { bounce = true }
    }

    private func stepLine(_ n: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(n).font(UI.score(16)).foregroundStyle(UI.onBall).frame(width: 28, height: 28).background(Circle().fill(UI.ball))
            Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(UI.paper)
        }
    }
}

/// Une résa auto, en billet : je guette, les jours en balles, le moment, la durée, ce que j'ai vu.
struct AutoRuleCard: View {
    var rule: BotRule
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI

    var body: some View {
        Ticket {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if rule.active && !rule.isPaused {
                        LiveDot(size: 7)
                        Eyebrow(text: "Je guette", color: UI.ink)
                    } else {
                        Image(systemName: "pause.fill").font(.system(size: 10)).foregroundStyle(UI.muted)
                        Eyebrow(text: "En pause")
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { rule.active }, set: { v in
                        if let i = bot.rules.firstIndex(where: { $0.id == rule.id }) { bot.rules[i].active = v }
                    }))
                    .labelsHidden().tint(UI.court)
                }
                Text(rule.clubName).font(UI.title(22)).foregroundStyle(UI.ink).lineLimit(2)
                DayBalls(days: rule.weekdays)
                HStack(spacing: 14) {
                    Label(rule.moment.label, systemImage: rule.moment.symbol)
                    Label(rule.durations.sorted().map(String.init).joined(separator: "/") + " min", systemImage: "timer")
                    if rule.maxBookings == 0 { Label("chaque semaine", systemImage: "repeat") }
                }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(UI.muted)
            }
        } stub: {
            HStack(alignment: .top, spacing: 10) {
                Text(rule.lastStatus).font(UI.callout()).foregroundStyle(rule.isPaused ? UI.clay : UI.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Menu {
                    Button { Task { await bot.run(ruleID: rule.id, force: true) } } label: { Label("Regarder maintenant", systemImage: "eye") }
                    Button(role: .destructive) {
                        if let id = rule.serverRuleID { Task { await server.deleteServerRule(id) } }
                        bot.rules.removeAll { $0.id == rule.id }
                    } label: { Label("Supprimer", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.muted).frame(width: 32, height: 24)
                }
            }
        }
        .opacity(rule.active ? 1 : 0.6)
    }
}

struct JournalRow: View {
    var entry: BotLogEntry
    var last: Bool
    var open: (URL) -> Void

    private var color: Color {
        switch entry.kind {
        case .booked: return UI.ball
        case .found: return UI.court
        case .needsAction: return UI.clay
        case .failed: return UI.danger
        case .info: return UI.faint
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(UI.ink.opacity(entry.kind == .booked ? 0.4 : 0), lineWidth: 0.75))
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.clubName).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(FR.relative(entry.date)).font(UI.small()).foregroundStyle(UI.faint)
                }
                if let start = entry.slotStart {
                    Text(FR.string(start, "EEE d MMM · HH:mm").uppercased(with: UI.fr) + (entry.court.isEmpty ? "" : " · " + entry.court.uppercased(with: UI.fr)))
                        .font(UI.score(14)).foregroundStyle(UI.ink)
                }
                Text(entry.message).font(UI.caption()).foregroundStyle(UI.muted)
                if let s = entry.actionURL, let url = URL(string: s), (entry.slotStart ?? .distantFuture) > Date() {
                    Button { open(url) } label: { Label("Réserver maintenant", systemImage: "arrow.right") }
                        .buttonStyle(LinkButtonStyle()).padding(.top, 4)
                }
            }
            .padding(.bottom, last ? 0 : 18)
        }
        // La frise : un filet vertical qui relie les points (dessiné en fond, à la hauteur de la ligne).
        .background(alignment: .topLeading) {
            if !last {
                Rectangle().fill(UI.rule).frame(width: 1).frame(maxHeight: .infinity).padding(.top, 17).offset(x: 4.5)
            }
        }
    }
}

/// Ouverture des réservations en direct : compte à rebours, lecture, résultat. Un tableau de score, à l'encre.
struct SnipePanel: View {
    var snipe: Snipe
    @EnvironmentObject private var bot: BotEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(text: "Ouverture · " + snipe.clubName, color: UI.paper.opacity(0.7))
                Spacer()
                Button { bot.cancelSnipe() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .foregroundStyle(UI.paper.opacity(0.7))
            }
            switch snipe.phase {
            case .countdown:
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = max(0, snipe.release.timeIntervalSince(context.date))
                    Text(String(format: "%02d:%02d.%d", Int(left) / 60, Int(left) % 60, Int((left * 10).truncatingRemainder(dividingBy: 10))))
                        .font(UI.scoreHeavy(72)).foregroundStyle(UI.paper)
                        .contentTransition(.numericText(countsDown: true))
                }
                Text("Créneaux du \(FR.longDay(snipe.day, tz: TimeZone(identifier: snipe.timezone) ?? .current)). Garde l'app ouverte : je regarde à la seconde où ça ouvre.")
                    .font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .scanning(let n):
                HStack(spacing: 10) {
                    LiveDot(size: 10)
                    Text("Lecture \(n)").font(UI.scoreHeavy(56)).foregroundStyle(UI.paper)
                }
                Text("Une lecture par seconde, puis toutes les 3 s. Je m'arrête si Playtomic refuse.")
                    .font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .found(let what):
                Stamp(text: "Trouvé")
                Text(what).font(UI.title(22)).foregroundStyle(UI.paper)
                Text("La réservation s'est ouverte, déjà remplie : confirme-la.").font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .missed:
                Text("Rien n'est apparu.").font(UI.title(22)).foregroundStyle(UI.paper)
                Text("Le club n'a pas encore publié ce créneau. Je continue de guetter.").font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .blocked:
                Text("Arrêté.").font(UI.title(22)).foregroundStyle(UI.paper)
                Text("Playtomic a limité les lectures : je me suis arrêté, comme prévu.").font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(UI.ink))
    }
}

// MARK: - Programmer une partie (quatre questions, une par écran)

struct RuleEditorView: View {
    var prefill: BotRule?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var favorites: Favorites

    @State private var rule = BotRule(provider: .playtomic, clubID: "", clubName: "", weekdays: [])
    @State private var step = 0
    @State private var forward = true
    @State private var moment: PlayMoment = .evening
    @State private var weekly = true
    @State private var choices: [Club] = []
    @State private var detected: BookingWindow? = nil
    @State private var showFinder = false
    @State private var showOptions = false
    @State private var celebrate = false
    @State private var options = AutoOptions()

    private let questions = ["Où veux-tu jouer ?", "Quels jours ?", "À quel moment ?", "Combien de temps ?", "Ta résa auto"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: step < 4 ? "Question \(step + 1) sur 4" : "C'est prêt")
                            Text(questions[step]).font(UI.display(32)).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        stepContent
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .padding(.horizontal, UI.margin)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .background(PageBackground(seasonal: false))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > (prefill == nil ? 0 : 1) {
                        Button { go(step - 1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Retour")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .sheet(isPresented: $showFinder) { ClubFinderSheet { picked in choose(picked) } }
            .sheet(isPresented: $showOptions) { AutoOptionsSheet(options: $options, detected: detected) }
        }
        .tint(UI.court)
        .overlay { if celebrate { ConfettiBurst() } }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: celebrate)
        .task { await setup() }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: clubStep
        case 1: daysStep
        case 2: momentStep
        case 3: durationStep
        default: ticketStep
        }
    }

    // MARK: Progression (des barres qui montent, comme le niveau)

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(i <= step ? (i == 4 ? UI.ball : UI.ink) : UI.rule)
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, UI.margin)
        .padding(.top, 6)
        .animation(.snappy, value: step)
    }

    private func go(_ next: Int) {
        forward = next > step
        withAnimation(.snappy(duration: 0.32)) { step = max(0, min(4, next)) }
    }

    // MARK: 1. Où

    private var clubStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if choices.isEmpty {
                Text("Aucun club reconnu autour de toi pour l'instant. Cherche le tien :").font(UI.callout()).foregroundStyle(UI.muted)
            }
            ForEach(choices) { club in
                Button { choose(club) } label: { clubTile(club, selected: isChosen(club)) }.buttonStyle(.plain)
            }
            Button { showFinder = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
                    Text("Un autre club…").font(UI.headline())
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(UI.ink)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(UI.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            }
            .buttonStyle(.plain)
        }
    }

    private func isChosen(_ c: Club) -> Bool { !rule.clubID.isEmpty && (rule.clubID == c.playtomicTenantID || rule.clubID == c.anybuddySlug) }

    private func clubTile(_ club: Club, selected: Bool) -> some View {
        HStack(spacing: 14) {
            Text(club.playtomicTenantID != nil ? "P" : "A")
                .font(.system(size: 15, weight: .bold).width(.expanded))
                .foregroundStyle(UI.onBall)
                .frame(width: 38, height: 38)
                .background(Circle().fill(UI.ball))
            VStack(alignment: .leading, spacing: 3) {
                Text(club.displayName).font(UI.headline()).foregroundStyle(selected ? UI.paper : UI.ink).lineLimit(1)
                Text([club.city, club.distance(from: location.location).map { formatDistance($0) } ?? "", club.playtomicTenantID != nil ? "Playtomic" : "Anybuddy"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(UI.caption()).foregroundStyle(selected ? UI.paper.opacity(0.7) : UI.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if favorites.contains(club) { Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(selected ? UI.ball : UI.clay) }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22)).foregroundStyle(selected ? UI.ball : UI.faint)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? UI.ink : UI.raised))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.clear : UI.rule, lineWidth: 1))
        .scaleEffect(selected ? 1.01 : 1)
        .animation(.snappy(duration: 0.2), value: selected)
    }

    private func choose(_ club: Club) {
        rule.provider = club.playtomicTenantID != nil ? .playtomic : .anybuddy
        rule.clubID = club.playtomicTenantID ?? club.anybuddySlug ?? ""
        rule.clubSlug = club.playtomicSlug
        rule.clubName = club.displayName
        rule.clubCity = club.city
        rule.timezone = club.timezone ?? TimeZone.current.identifier
        Task { await detectWindow() }
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            go(1)
        }
    }

    // MARK: 2. Quels jours (des balles à remplir)

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                preset("En semaine", [0, 1, 2, 3, 4])
                preset("Le week-end", [5, 6])
                preset("Tous", Set(0...6))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                ForEach(0..<7, id: \.self) { d in dayToken(d) }
            }
            Text(rule.weekdays.isEmpty ? "Touche les jours où tu peux jouer." : "Je guette \(rule.daysPhrase).")
                .font(UI.callout()).foregroundStyle(UI.muted)
            Button { go(2) } label: { Text("Suivant") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(rule.weekdays.isEmpty).opacity(rule.weekdays.isEmpty ? 0.35 : 1)
        }
    }

    private func preset(_ label: String, _ days: Set<Int>) -> some View {
        Button { withAnimation(.snappy) { rule.weekdays = days } } label: { Chip(text: label, active: rule.weekdays == days) }
            .buttonStyle(.plain)
    }

    private func dayToken(_ d: Int) -> some View {
        let on = rule.weekdays.contains(d)
        let names = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                if on { rule.weekdays.remove(d) } else { rule.weekdays.insert(d) }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(on ? UI.ball : UI.raised)
                    Circle().strokeBorder(on ? UI.onBall.opacity(0.25) : UI.rule, lineWidth: 1)
                    if on {
                        // La couture de la balle
                        Circle().trim(from: 0.1, to: 0.4).stroke(UI.onBall.opacity(0.55), lineWidth: 2).rotationEffect(.degrees(-36)).padding(9)
                        Circle().trim(from: 0.6, to: 0.9).stroke(UI.onBall.opacity(0.55), lineWidth: 2).rotationEffect(.degrees(-36)).padding(9)
                    }
                }
                .frame(width: 62, height: 62)
                .scaleEffect(on ? 1.06 : 1)
                Text(names[d]).font(.system(size: 13, weight: .semibold).width(.expanded)).foregroundStyle(on ? UI.ink : UI.muted)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: on)
        .accessibilityLabel(BotRule.dayNames[d])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 3. Quel moment

    private var momentStep: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach([PlayMoment.morning, .noon, .afternoon, .evening]) { m in momentTile(m) }
            }
            momentTile(.any)
        }
    }

    private func momentTile(_ m: PlayMoment) -> some View {
        let on = moment == m
        let night = m == .evening
        return Button {
            moment = m
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                go(3)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: m.symbol)
                    .font(.system(size: m == .any ? 20 : 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(on ? UI.onBall : (night ? UI.ball : UI.court))
                Text(m.label).font(UI.title(20)).foregroundStyle(on ? UI.onBall : (night ? UI.paper : UI.ink))
                Text(m.hours).font(UI.score(15)).foregroundStyle(on ? UI.onBall.opacity(0.7) : (night ? UI.paper.opacity(0.7) : UI.muted))
            }
            .frame(maxWidth: .infinity, minHeight: m == .any ? 0 : 128, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(on ? UI.ball : (night ? UI.ink : UI.raised)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on || night ? Color.clear : UI.rule, lineWidth: 1))
            .scaleEffect(on ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
        }
        .buttonStyle(.plain)
    }

    // MARK: 4. Combien de temps

    private var durationStep: some View {
        HStack(spacing: 12) {
            ForEach([60, 90, 120], id: \.self) { d in durationTile(d) }
        }
    }

    private func durationTile(_ d: Int) -> some View {
        let on = rule.durations == [d]
        return Button {
            rule.durations = [d]
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                go(4)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(d)").font(UI.scoreHeavy(58)).foregroundStyle(on ? UI.onBall : UI.ink)
                Text("MIN").font(UI.label()).tracking(1).foregroundStyle(on ? UI.onBall : UI.muted)
                Text(d == 90 ? "le classique" : " ").font(.system(size: 11, weight: .medium)).foregroundStyle(on ? UI.onBall.opacity(0.7) : UI.faint)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(on ? UI.ball : UI.raised))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Color.clear : UI.rule, lineWidth: 1))
            .scaleEffect(on ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
        }
        .buttonStyle(.plain)
    }

    // MARK: 5. Le billet

    private var ticketStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Ticket {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Eyebrow(text: rule.provider.name)
                        Spacer()
                        Stamp(text: "Résa auto")
                    }
                    Text(rule.clubName).font(UI.title(24)).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                    DayBalls(days: rule.weekdays, size: 30)
                    HStack(spacing: 16) {
                        Label(moment.label + " · " + moment.hours, systemImage: moment.symbol)
                        Label("\(rule.durations.first ?? 90) min", systemImage: "timer")
                    }
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(UI.ink)
                    if let w = detected {
                        Label(w.rolling ? "Les créneaux ouvrent \(w.days) jours avant, à la même heure : je serai là à la seconde."
                                        : "Les créneaux ouvrent \(w.days) jours à l'avance : je guette l'ouverture.",
                              systemImage: "alarm.fill")
                            .font(UI.caption()).foregroundStyle(UI.muted)
                    }
                }
            } stub: {
                Toggle(isOn: $weekly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toutes les semaines").font(UI.headline()).foregroundStyle(UI.ink)
                        Text(weekly ? "Je recommence chaque semaine." : "Une seule partie, puis je m'arrête.").font(UI.caption()).foregroundStyle(UI.muted)
                    }
                }
                .tint(UI.court)
            }
            Text("Dès qu'un créneau se libère, je te préviens et je t'ouvre la réservation déjà remplie : tu n'as plus qu'à confirmer.")
                .font(UI.callout()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
            Button { Task { await save() } } label: { Label("C'est parti", systemImage: "bolt.fill") }
                .buttonStyle(PrimaryButtonStyle(fill: UI.ball, text: UI.onBall))
                .disabled(celebrate)
            Button("Plus d'options") { showOptions = true }.buttonStyle(LinkButtonStyle(color: UI.muted)).frame(maxWidth: .infinity)
        }
    }

    // MARK: Données

    private func setup() async {
        if let prefill, !prefill.clubID.isEmpty, rule.clubID.isEmpty {
            rule = prefill
            rule.weekdays = []
            moment = prefill.moment
            step = 1
            await detectWindow()
        }
        if let shot = ShotMode.current {
            choices = Array(ShotMode.demoClubs.filter { $0.playtomicTenantID != nil || $0.anybuddySlug != nil }.prefix(4))
            if shot.hasPrefix("wizard"), let club = choices.first {
                rule.provider = .playtomic
                rule.clubID = club.playtomicTenantID ?? ""
                rule.clubName = club.displayName
                rule.weekdays = [1, 3]
                rule.durations = [90]
                moment = .evening
                detected = BookingWindow(days: 7, rolling: true, lastDay: Date().addingTimeInterval(7 * 86_400), checked: Date())
                step = shot == "wizard-moment" ? 2 : (shot == "wizard-ticket" ? 4 : 1)
            }
            return
        }
        // Tes favoris d'abord, puis les clubs proches qu'on sait lire (Playtomic, ou reconnus sur Anybuddy).
        var list = favorites.clubs.map { directory.club(id: $0.id) ?? $0 }
        if let loc = location.location {
            for c in directory.nearest(to: loc, limit: 20, maxKm: 30) where !list.contains(where: { $0.id == c.id }) { list.append(c) }
        }
        list = list.map { c in
            guard c.playtomicTenantID == nil, c.anybuddySlug == nil, let slug = AnybuddyDirectory.match(c) else { return c }
            var linked = c
            linked.anybuddySlug = slug
            return linked
        }
        choices = Array(list.filter { $0.playtomicTenantID != nil || $0.anybuddySlug != nil }.prefix(6))
    }

    private func detectWindow() async {
        guard rule.provider == .playtomic, !rule.clubID.isEmpty, ShotMode.current == nil else { return }
        detected = await PlaytomicWeb.bookingWindow(tenantID: rule.clubID, timezone: rule.timezone)
    }

    private func save() async {
        var r = rule
        r.timeFrom = moment.range.0
        r.timeTo = moment.range.1
        if r.durations.isEmpty { r.durations = [90] }
        r.autoBook = true
        r.maxBookings = weekly ? 0 : 1
        r.court = options.court
        r.maxPrice = options.limitPrice ? options.price : nil
        if let w = detected {
            r.releaseDays = w.days
            r.releaseMinutes = w.rolling ? r.timeFrom : (options.releaseMinutes ?? 0)
            r.daysAhead = min(21, max(7, w.days))
        } else if let d = options.releaseDays {
            r.releaseDays = d
            r.releaseMinutes = options.releaseMinutes ?? 8 * 60
        }
        r.lastStatus = "C'est parti, je regarde…"
        if r.provider == .padelup, server.botServerEnabled, let id = try? await server.pushRule(r) { r.serverRuleID = id }
        bot.addRule(r)
        withAnimation { celebrate = true }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        dismiss()
    }

    static func timezone(country: String) -> String {
        switch country.uppercased() {
        case "MA": return "Africa/Casablanca"
        case "DZ": return "Africa/Algiers"
        case "TN": return "Africa/Tunis"
        case "ES": return "Europe/Madrid"
        case "IT": return "Europe/Rome"
        case "DE": return "Europe/Berlin"
        case "BE": return "Europe/Brussels"
        case "CH": return "Europe/Zurich"
        case "LU": return "Europe/Luxembourg"
        case "MC": return "Europe/Monaco"
        case "AD": return "Europe/Andorra"
        default: return "Europe/Paris"
        }
    }
}

// MARK: - Plus d'options (pour les curieux)

struct AutoOptions {
    var court: BotRule.Court = .any
    var limitPrice = false
    var price = 40.0
    var releaseDays: Int? = nil
    var releaseMinutes: Int? = nil
}

struct AutoOptionsSheet: View {
    @Binding var options: AutoOptions
    var detected: BookingWindow?
    @Environment(\.dismiss) private var dismiss
    @State private var useRelease = false
    @State private var days = 7
    @State private var minutes = 8 * 60

    var body: some View {
        NavigationStack {
            Screen(title: "Options", seasonal: false) {
                Block(title: "Terrain") {
                    InlinePicker(options: BotRule.Court.allCases.map { ($0, $0.label) }, selection: $options.court)
                }
                Block(title: "Prix") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Prix maximum", isOn: $options.limitPrice.animation(.snappy)).tint(UI.court).font(UI.body())
                        if options.limitPrice {
                            Stepper(value: $options.price, in: 5...200, step: 5) { Text("\(Int(options.price)) € maximum").font(UI.score(20)) }
                        }
                    }
                }
                Block(title: "Ouverture des créneaux") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let w = detected {
                            Text("Détectée sur Playtomic : \(w.title.lowercased()), \(w.rolling ? "à la même heure que le créneau" : "journée entière").")
                                .font(UI.callout()).foregroundStyle(UI.ink)
                        } else {
                            Toggle("Le club ouvre ses créneaux à heure fixe", isOn: $useRelease.animation(.snappy)).tint(UI.court).font(UI.body())
                            if useRelease {
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Eyebrow(text: "Jours avant")
                                        Text("J-\(days)").font(UI.score(34)).foregroundStyle(UI.ink).lineLimit(1).fixedSize()
                                        Stepper("", value: $days, in: 1...30).labelsHidden()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Rectangle().fill(UI.rule).frame(width: 0.5, height: 90).padding(.horizontal, 14)
                                    TimeField(label: "à", minutes: $minutes, range: 0...(23 * 60 + 45), step: 15)
                                }
                            }
                        }
                    }
                }
                Button("Valider") {
                    options.releaseDays = useRelease ? days : nil
                    options.releaseMinutes = useRelease ? minutes : nil
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .onAppear {
            useRelease = options.releaseDays != nil
            days = options.releaseDays ?? 7
            minutes = options.releaseMinutes ?? 8 * 60
        }
    }
}

// MARK: - Trouver un autre club (Playtomic ou Anybuddy)

struct ClubFinderSheet: View {
    var onPick: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: LocationManager
    @State private var query = ""
    @State private var link = ""
    @State private var results: [PlaytomicClub] = []
    @State private var anybuddy: [String] = []
    @State private var searching = false
    @State private var info: String? = nil
    @State private var pickOnSite = false

    var body: some View {
        NavigationStack {
            Screen(title: "Trouver un club", seasonal: false) {
                HStack(spacing: 10) {
                    InputField(title: "Nom du club ou ville", text: $query, systemImage: "magnifyingglass")
                        .onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: { if searching { ProgressView() } else { Text("Chercher") } }
                        .buttonStyle(LinkButtonStyle())
                }
                if let info { Text(info).font(UI.callout()).foregroundStyle(UI.muted) }
                if !results.isEmpty {
                    Block(title: "Sur Playtomic") {
                        VStack(spacing: 0) {
                            ForEach(Array(results.prefix(8).enumerated()), id: \.element.key) { i, c in
                                Button { Task { await pickPlaytomic(c) } } label: {
                                    row(c.name, [c.street, c.postalCode].filter { !$0.isEmpty }.joined(separator: " · "))
                                }
                                .buttonStyle(.plain)
                                if i < min(results.count, 8) - 1 { Hairline() }
                            }
                        }
                    }
                }
                if !anybuddy.isEmpty {
                    Block(title: "Sur Anybuddy") {
                        VStack(spacing: 0) {
                            ForEach(Array(anybuddy.prefix(8).enumerated()), id: \.element) { i, slug in
                                Button { pickAnybuddy(slug) } label: { row(Self.pretty(slug), "anybuddyapp.com") }.buttonStyle(.plain)
                                if i < min(anybuddy.count, 8) - 1 { Hairline() }
                            }
                        }
                    }
                }
                Block(title: "Autres façons") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button { pickOnSite = true } label: { Label("Choisir sur le site Playtomic", systemImage: "safari") }
                            .buttonStyle(SecondaryButtonStyle())
                        HStack(spacing: 10) {
                            InputField(title: "Coller le lien du club", text: $link, keyboard: .URL, systemImage: "link")
                            Button("Ajouter") { Task { await useLink() } }.buttonStyle(LinkButtonStyle())
                        }
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
            .sheet(isPresented: $pickOnSite) { PlaytomicPickerSheet(query: query) { c in Task { await pickPlaytomic(c) } } }
        }
        .tint(UI.court)
    }

    static func pretty(_ slug: String) -> String { slug.replacingOccurrences(of: "-", with: " ").capitalized }

    private func row(_ title: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1) }
            }
            Spacer()
            Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(UI.court)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func search() async {
        var q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty, let loc = location.location, let city = try? await CLGeocoder().reverseGeocodeLocation(loc).first?.locality { q = city }
        guard q.count >= 2 else { info = "Tape le nom du club ou une ville."; return }
        searching = true
        defer { searching = false }
        info = nil
        // Anybuddy : dans la liste publique de leurs clubs, tout de suite.
        let words = AnybuddyDirectory.tokens(q)
        anybuddy = AnybuddyDirectory.slugs.filter { slug in
            let parts = Set(slug.split(separator: "-").map(String.init))
            return !words.isEmpty && words.isSubset(of: parts)
        }
        // Playtomic : requête directe, puis le site dans le navigateur invisible.
        results = (try? await PlaytomicWeb.search(q)) ?? []
        if results.isEmpty {
            results = PlaytomicWeb.rank(await HiddenBrowser.shared.search(q + " france"), query: q)
        }
        if results.isEmpty && anybuddy.isEmpty { info = "Rien trouvé pour « \(q) ». Essaie le nom exact, ou choisis-le sur le site Playtomic." }
    }

    private func pickPlaytomic(_ c: PlaytomicClub) async {
        var id = c.id
        if id.isEmpty {
            info = "Je reconnais \(c.name)…"
            if let found = await HiddenBrowser.shared.tenantID(slug: c.slug) {
                id = found
            } else if let resolved = await PlaytomicWeb.resolve(link: "https://playtomic.com/clubs/\(c.slug)") {
                id = resolved.id
            }
        }
        guard !id.isEmpty else { info = "Impossible de reconnaître ce club : choisis-le sur le site Playtomic."; return }
        var club = Club(id: "pt:" + id, name: c.name, latitude: 0, longitude: 0, source: .playtomic, playtomicTenantID: id,
                        timezone: RuleEditorView.timezone(country: c.countryCode))
        club.playtomicSlug = c.slug
        club.city = c.postalCode
        onPick(club)
        dismiss()
    }

    private func pickAnybuddy(_ slug: String) {
        onPick(Club(id: "ab:" + slug, name: Self.pretty(slug), latitude: 0, longitude: 0, source: .osm, anybuddySlug: slug, timezone: "Europe/Paris"))
        dismiss()
    }

    private func useLink() async {
        if link.lowercased().contains("anybuddy"), let slug = AnybuddyAPI.slug(from: link) {
            pickAnybuddy(slug)
        } else if let c = await PlaytomicWeb.resolve(link: link) {
            await pickPlaytomic(c)
        } else {
            info = "Lien non reconnu. Dans l'app Playtomic ou Anybuddy, ouvre le club puis « Partager », et colle le lien ici."
        }
    }
}

// MARK: - Confettis (balle, bleu, terre battue, encre)

struct ConfettiBurst: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                let colors: [Color] = [UI.ball, UI.court, UI.clay, UI.hex(0x0D1B24), UI.ball]
                for i in 0..<70 {
                    let seed = Double(i) * 12.9898
                    let r1 = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude
                    let r2 = (sin(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1).magnitude
                    let angle = -Double.pi / 2 + (r1 - 0.5) * 2.4
                    let speed = 380 + r2 * 520
                    let x = size.width / 2 + cos(angle) * speed * t
                    let y = size.height * 0.62 + sin(angle) * speed * t + 900 * t * t
                    var c = ctx
                    c.opacity = max(0, 1 - t / 1.6)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * (r1 * 12 - 6)))
                    let w = 6 + r2 * 6, h = 9 + r1 * 7
                    let color = colors[i % colors.count]
                    if i % 3 == 0 {
                        c.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -w / 2, width: w, height: w)), with: .color(color))
                    } else {
                        c.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Heure réglable au quart d'heure ou à la demi-heure, affichée en chiffres de tableau de score.
struct TimeField: View {
    var label: String
    @Binding var minutes: Int
    var range: ClosedRange<Int>
    var step = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: label)
            Text(BotRule.hhmm(minutes)).font(UI.score(34)).foregroundStyle(UI.ink)
                .lineLimit(1).fixedSize().contentTransition(.numericText())
            Stepper("", value: Binding(get: { minutes }, set: { minutes = min(max($0, range.lowerBound), range.upperBound) }),
                    in: range, step: step).labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
