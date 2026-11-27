import CoreLocation
import SwiftUI

// Radar des joueurs (comme l'app PadelUp actuelle) : qui joue près de toi, à ton niveau, et quand.

/// Joueur à ouvrir dans une feuille posée sur une autre feuille (fiche match, amis).
struct PlayerRef: Identifiable, Hashable { let id: Int }

struct RadarSection: View {
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var router: Router
    @AppStorage("radarVisible") private var visible = false
    @State private var radius = 15
    @State private var levelBand = true
    @State private var slot: TimeSlot? = nil
    @State private var players: [APIRadarPlayer] = []
    @State private var proposals = APIProposals(sent: [], received: [])
    @State private var availabilities: [APIAvailability] = []
    @State private var loading = false
    @State private var error: String? = nil
    @State private var proposeTo: APIRadarPlayer? = nil
    @State private var showAvailability = false

    private var myLevel: Int { server.me?.profile?.skillLevel ?? 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            visibilityRow
            filters
            RadarScope(players: players, radiusKm: radius) { p in router.sheet = .player(p.userId) }
            playersBlock
            proposalsBlock
            availabilityBlock
        }
        .task(id: "\(radius)-\(levelBand)-\(slot?.rawValue ?? "")-\(location.location != nil)") { await load() }
        .sheet(item: $proposeTo) { p in ProposalSheet(userID: p.userId, name: p.name) { Task { await load() } } }
        .sheet(isPresented: $showAvailability) { AvailabilitySheet { Task { await load() } } }
    }

    // MARK: Consentement

    private var visibilityRow: some View {
        Toggle(isOn: Binding(get: { visible }, set: { v in
            visible = v
            Task { try? await server.setRadarVisible(v, at: location.location?.coordinate); await load() }
        })) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Me montrer sur le radar").font(UI.body()).foregroundStyle(UI.ink)
                Text("Ta position est arrondie à 1 km et n'est jamais affichée : les autres voient seulement une distance.")
                    .font(UI.caption()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(UI.court)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            InlinePicker(options: [(5, "5 km"), (15, "15 km"), (30, "30 km"), (50, "50 km")], selection: $radius)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { levelBand.toggle() } label: { Chip(text: levelBand ? "Niveau \(max(1, myLevel - 1))–\(min(10, myLevel + 1))" : "Tous niveaux", active: levelBand) }
                        .buttonStyle(.plain)
                    Button { slot = nil } label: { Chip(text: "Tout moment", active: slot == nil) }.buttonStyle(.plain)
                    ForEach(TimeSlot.allCases) { s in
                        Button { slot = s } label: { Chip(text: s.label, active: slot == s) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Joueurs

    @ViewBuilder private var playersBlock: some View {
        Block(title: "Autour de toi", meta: loading ? "recherche…" : "\(players.count) joueur\(players.count > 1 ? "s" : "")") {
            if location.location == nil && ShotMode.current == nil {
                EmptyNote(title: "Active la localisation.", message: "Le radar a besoin de savoir où tu joues.", actionTitle: "Activer") { location.request() }
            } else if let error {
                EmptyNote(title: "Radar indisponible.", message: error)
            } else if players.isEmpty && !loading {
                EmptyNote(title: "Personne pour l'instant.", message: "Élargis le rayon ou le niveau. Plus il y a de joueurs visibles, plus le radar est utile : invite tes partenaires.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { i, p in
                        Button { router.sheet = .player(p.userId) } label: { RadarRow(player: p) { proposeTo = p } }
                            .buttonStyle(.plain)
                        if i < players.count - 1 { Hairline(inset: 56) }
                    }
                }
            }
        }
    }

    // MARK: Propositions

    @ViewBuilder private var proposalsBlock: some View {
        let received = proposals.received.filter { $0.status == "pending" }
        let sent = proposals.sent.filter { $0.status != "cancelled" }.prefix(6)
        if !received.isEmpty || !sent.isEmpty {
            Block(title: "Propositions", meta: received.isEmpty ? nil : "\(received.count) à traiter") {
                VStack(spacing: 0) {
                    ForEach(received) { p in
                        ProposalRow(title: "\(p.senderName) te propose", proposal: p) {
                            HStack(spacing: 8) {
                                Button { Task { try? await server.answerProposal(p.id, accept: false); await load() } } label: {
                                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 36)
                                        .overlay(Circle().strokeBorder(UI.rule, lineWidth: 1))
                                }
                                .foregroundStyle(UI.muted).accessibilityLabel("Refuser")
                                Button { Task { try? await server.answerProposal(p.id, accept: true); await load() } } label: {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
                                        .background(Circle().fill(UI.court))
                                }
                                .foregroundStyle(UI.onCourt).accessibilityLabel("Accepter")
                            }
                            .buttonStyle(.plain)
                        }
                        Hairline()
                    }
                    ForEach(Array(sent)) { p in
                        ProposalRow(title: "Pour \(p.receiverName)", proposal: p) {
                            if p.status == "pending" {
                                Menu {
                                    Button("Annuler la proposition", role: .destructive) { Task { try? await server.cancelProposal(p.id); await load() } }
                                } label: { Stamp(text: "En attente", style: .outline) }
                            } else {
                                Stamp(text: p.statusDisplay ?? p.status, style: p.status == "accepted" ? .ball : .outline)
                            }
                        }
                        Hairline()
                    }
                }
            }
        }
    }

    // MARK: Mes disponibilités

    private var availabilityBlock: some View {
        Block(title: "Mes disponibilités", actionTitle: "Ajouter", action: { showAvailability = true }) {
            if availabilities.isEmpty {
                EmptyNote(title: "Dis quand tu joues.", message: "Tes créneaux habituels (ex. mardi soir) aident les autres à te proposer un match au bon moment.")
            } else {
                FlowRow(availabilities.map { ($0.id, "\($0.dayLabel) · \($0.slot?.label ?? $0.timeSlot)") }) { id, label in
                    Menu {
                        Button("Supprimer", role: .destructive) { Task { try? await server.deleteAvailability(id); await load() } }
                    } label: { Chip(text: label) }
                }
            }
        }
    }

    private func load() async {
        if ShotMode.current != nil {
            players = ShotMode.demoRadar()
            proposals = ShotMode.demoProposals()
            availabilities = ShotMode.demoAvailabilities()
            return
        }
        guard server.isLoggedIn, let c = location.location?.coordinate else { return }
        loading = true
        defer { loading = false }
        if visible { try? await server.setRadarVisible(true, at: c) }
        do {
            let r = try await server.radar(near: c, radiusKm: radius, minSkill: levelBand ? max(1, myLevel - 1) : 1,
                                           maxSkill: levelBand ? min(10, myLevel + 1) : 10, slot: slot)
            players = r.results
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        proposals = (try? await server.proposals()) ?? proposals
        availabilities = (try? await server.availabilities()) ?? availabilities
    }
}

/// Un joueur du radar : initiales, prénom, niveau en barres, distance, quand il joue, bouton Proposer.
struct RadarRow: View {
    var player: APIRadarPlayer
    var propose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: player.name, size: 42)
                .overlay(Circle().strokeBorder(player.isFriend == true ? UI.ball : Color.clear, lineWidth: 2.5).padding(-3))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(player.name).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                    if player.isFriend == true { Stamp(text: "Ami", style: .outline) }
                }
                HStack(spacing: 6) {
                    LevelBars(level: player.skillLevel ?? 1, count: player.evaluationType == "old" ? 10 : 8, height: 11, barWidth: 2.5)
                    Text([player.tierName ?? "", player.city ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
                }
                if let a = player.availability, !a.isEmpty {
                    Text(a.prefix(3).map { "\($0.dayLabel.prefix(3).lowercased()) \($0.slot?.label.lowercased() ?? "")" }.joined(separator: " · "))
                        .font(UI.small()).foregroundStyle(UI.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(player.distanceKm < 10 ? String(format: "%.1f km", player.distanceKm).replacingOccurrences(of: ".", with: ",") : "\(Int(player.distanceKm)) km")
                    .font(UI.score(16)).foregroundStyle(UI.ink)
                if player.hasPendingProposal == true {
                    Text("proposé").font(UI.small()).foregroundStyle(UI.muted)
                } else {
                    Button("Proposer", action: propose).buttonStyle(LinkButtonStyle())
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct ProposalRow<Trailing: View>: View {
    var title: String
    var proposal: APIProposal
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DateBlock(date: proposal.date)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(UI.headline()).foregroundStyle(UI.ink)
                Text([TimeSlot(rawValue: proposal.proposedTimeSlot)?.label ?? proposal.proposedTimeSlot, proposal.locationText ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · ")).font(UI.caption()).foregroundStyle(UI.muted)
                if let m = proposal.message, !m.isEmpty {
                    Text("« \(m) »").font(UI.caption()).foregroundStyle(UI.ink).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.vertical, 12)
    }
}

/// Le radar : cercles de distance, toi au centre, les joueurs placés à leur distance (l'angle est arbitraire :
/// on ne connaît que la distance, et c'est voulu).
struct RadarScope: View {
    var players: [APIRadarPlayer]
    var radiusKm: Int
    var onTap: (APIRadarPlayer) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let r = side / 2 - 18
            let center = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                ForEach([1.0, 0.66, 0.33], id: \.self) { k in
                    Circle().strokeBorder(UI.rule, lineWidth: 1).frame(width: r * 2 * k, height: r * 2 * k).position(center)
                }
                Path { p in
                    p.move(to: CGPoint(x: center.x - r, y: center.y)); p.addLine(to: CGPoint(x: center.x + r, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: center.y - r)); p.addLine(to: CGPoint(x: center.x, y: center.y + r))
                }
                .stroke(UI.rule, style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                        let angle = Angle.degrees(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360)
                        Circle()
                            .fill(AngularGradient(colors: [UI.ball.opacity(0), UI.ball.opacity(0), UI.ball.opacity(0.35)], center: .center,
                                                  startAngle: .degrees(0), endAngle: .degrees(360)))
                            .frame(width: r * 2, height: r * 2)
                            .rotationEffect(angle)
                            .position(center)
                    }
                    .allowsHitTesting(false)
                }
                Text("\(radiusKm) km").font(UI.score(11)).foregroundStyle(UI.faint).position(x: center.x + 18, y: center.y - r + 8)
                Circle().fill(UI.court).frame(width: 12, height: 12).overlay(Circle().stroke(UI.paper, lineWidth: 2)).position(center)
                ForEach(players.prefix(30)) { p in
                    let k = min(1, max(0.12, p.distanceKm / Double(max(1, radiusKm))))
                    let a = Double((p.userId &* 2_654_435_761) % 360) * .pi / 180
                    Button { onTap(p) } label: {
                        Avatar(name: p.name, size: 28)
                            .overlay(Circle().stroke(p.isFriend == true ? UI.ball : UI.paper, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .position(x: center.x + CGFloat(cos(a) * k) * r, y: center.y + CGFloat(sin(a) * k) * r)
                    .accessibilityLabel("\(p.name), \(Int(p.distanceKm.rounded())) kilomètres")
                }
            }
        }
        .frame(height: 300)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Proposer un match

struct ProposalSheet: View {
    var userID: Int
    var name: String
    var onSent: () -> Void = {}
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var slot: TimeSlot = .evening
    @State private var place = ""
    @State private var message = ""
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Proposer un match", eyebrow: "à \(name)", seasonal: false) {
                Block(title: "Quand") {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("Jour", selection: $date, in: Date()...(Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()),
                                   displayedComponents: .date)
                            .environment(\.locale, UI.fr).font(UI.body())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TimeSlot.allCases) { s in
                                    Button { slot = s } label: { Chip(text: "\(s.label) · \(s.hours)", active: slot == s) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Block(title: "Où et quoi") {
                    VStack(spacing: 10) {
                        InputField(title: "Club ou ville (facultatif)", text: $place, systemImage: "mappin")
                        InputField(title: "Un mot (facultatif)", text: $message)
                    }
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await server.propose(to: userID, date: date, slot: slot, message: message, place: place)
                            onSent()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text("Envoyer la proposition") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
    }
}

struct AvailabilitySheet: View {
    var onSaved: () -> Void = {}
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int> = [1]
    @State private var slot: TimeSlot = .evening
    @State private var radius = 10
    @State private var busy = false
    @State private var error: String? = nil
    private let letters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            Screen(title: "Quand joues-tu ?", seasonal: false) {
                Block(title: "Jours") {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { d in
                            let on = days.contains(d)
                            Button { if on { days.remove(d) } else { days.insert(d) } } label: {
                                Text(letters[d]).font(.system(size: 15, weight: .semibold).width(.expanded))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(on ? UI.paper : UI.ink)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? UI.ink : UI.raised))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Color.clear : UI.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(BotRule.dayNames[d])
                        }
                    }
                }
                Block(title: "Moment") {
                    VStack(alignment: .leading, spacing: 14) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TimeSlot.allCases) { s in
                                    Button { slot = s } label: { Chip(text: "\(s.label) · \(s.hours)", active: slot == s) }.buttonStyle(.plain)
                                }
                            }
                        }
                        Stepper(value: $radius, in: 2...50, step: 2) {
                            Text("Jusqu'à \(radius) km").font(UI.score(20)).foregroundStyle(UI.ink)
                        }
                    }
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            for d in days.sorted() { try await server.addAvailability(day: d, date: nil, slot: slot, radiusKm: radius) }
                            onSaved()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text("Enregistrer") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || days.isEmpty)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
    }
}

// MARK: - Profil d'un joueur

struct PlayerProfileView: View {
    var userID: Int
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var data: APIPublicProfile? = nil
    @State private var error: String? = nil
    @State private var requested = false
    @State private var propose = false

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    Screen(title: data.name, eyebrow: data.profile.map { "Niveau \($0.skillLevel ?? 1) · " + ($0.tierName ?? "") }, seasonal: false) {
                        HStack(spacing: 16) {
                            Avatar(name: data.name, size: 64)
                            VStack(alignment: .leading, spacing: 6) {
                                LevelBars(level: data.profile?.skillLevel ?? 1, count: data.profile?.evaluationType == "old" ? 10 : 8, height: 20, barWidth: 5)
                                Text([data.profile?.location ?? "", data.profile?.rightHanded == false ? "gaucher" : "droitier"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(UI.caption()).foregroundStyle(UI.muted)
                            }
                        }
                        if let bio = data.profile?.bio, !bio.isEmpty {
                            Text(bio).font(UI.body()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        StatsRow(items: [
                            ("\(data.stats?.matchesPlayed ?? 0)", "matchs"),
                            ("\(data.stats?.matchesWon ?? 0)", "victoires"),
                            ("\(Int((data.stats?.winRate ?? 0).rounded())) %", "réussite"),
                        ])
                        if data.isOwnProfile != true {
                            VStack(spacing: 10) {
                                Button { propose = true } label: { Label("Proposer un match", systemImage: "calendar.badge.plus") }
                                    .buttonStyle(PrimaryButtonStyle())
                                if data.isFriend == true {
                                    Text("Vous êtes amis.").font(UI.callout()).foregroundStyle(UI.muted).frame(maxWidth: .infinity)
                                } else if requested || data.friendRequest != nil {
                                    Text("Demande d'ami en attente.").font(UI.callout()).foregroundStyle(UI.muted).frame(maxWidth: .infinity)
                                } else {
                                    Button {
                                        Task {
                                            do { try await server.sendFriendRequest(to: userID); requested = true } catch { self.error = error.localizedDescription }
                                        }
                                    } label: { Label("Ajouter en ami", systemImage: "person.badge.plus") }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                            }
                        }
                        if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                    }
                } else if let error {
                    Screen(title: "Joueur", seasonal: false) { EmptyNote(title: "Profil indisponible.", message: error) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(UI.paper)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .sheet(isPresented: $propose) { ProposalSheet(userID: userID, name: data?.name ?? "ce joueur") }
        .task {
            if ShotMode.current != nil { data = ShotMode.demoPublicProfile(); return }
            do { data = try await server.publicProfile(userID) } catch { self.error = error.localizedDescription }
        }
    }
}
