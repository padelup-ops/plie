// Cars.swift — Vicefold
//
// Les véhicules rares de la carte, alimentés par les joueurs : chacun peut ajouter l'endroit où il a trouvé un
// véhicule, et tout le monde vote « il est là » ou « pas là ». Un emplacement confirmé reste, un faux disparaît.
// Tout passe par l'entraide (Community.swift), sans rien de plus côté serveur : mêmes règles, même filtre, même
// signalement, même blocage, et la signature Game Center.
//   · Un emplacement ajouté par un joueur est un message du sujet « cars » : « Nom du véhicule @ 0.6123,0.4571 »
//     (la position sur notre carte, de 0 à 1). « Il est là » est le vote « utile » du message ; « pas là » est une
//     réponse « [not here] ».
//   · Pour un véhicule de la carte (Open GTA 6 Map), les votes sont des messages « [here] » ou « [not here] » dans son
//     fil (le sujet est l'identifiant du lieu) ; le dernier avis de chaque joueur compte.

import SwiftUI

extension VFPlace {
    /// Un véhicule rare ajouté par un joueur (pas encore dans le guide).
    var playerSpot: Bool { id.hasPrefix("c-") }
}

@MainActor @Observable
final class CarStore {
    static let shared = CarStore()
    static let topic = "cars"
    static let here = "[here]"
    static let gone = "[not here]"

    struct Spot: Identifiable, Hashable {
        var post: VFPost
        var name: String
        var x: Double
        var y: Double
        var id: String { "c-" + post.id }
    }

    /// Les votes sur un emplacement. mine : 1 « il est là », -1 « pas là », 0 rien.
    struct Tally: Hashable {
        var yes = 0
        var no = 0
        var mine = 0
        /// Mon message de vote (pour le retirer quand je change d'avis).
        var marker: VFPost?
        var confirmed: Bool { yes - no >= 2 }
        var rejected: Bool { no - yes >= 2 }
    }

    private(set) var spots: [Spot] = []
    private(set) var tallies: [String: Tally] = [:]

    /// Les emplacements des joueurs, comme des lieux de la carte.
    var places: [VFPlace] {
        spots.map { VFPlace(id: $0.id, name: $0.name, kind: .vehicle, x: $0.x, y: $0.y, note: String(localized: "Added by \($0.post.alias)")) }
    }

    static func isMarker(_ text: String) -> Bool { text == here || text == gone }

    /// « Bravado Banshee @ 0.6123,0.4571 » → le nom et la position.
    static func parse(_ text: String) -> (String, Double, Double)? {
        guard let r = text.range(of: " @ ", options: .backwards) else { return nil }
        let name = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let nums = text[r.upperBound...].split(separator: ",")
        guard nums.count == 2, let x = Double(nums[0]), let y = Double(nums[1]),
              x >= 0, x <= 1, y >= 0, y <= 1, name.count >= 2, name.count <= 60 else { return nil }
        return (name, x, y)
    }

    func loadSpots() async {
        if ShotMode.route != nil { demo(); return }
        guard let posts = await CommunityStore.shared.thread(Self.topic) else { return }
        let blocked = CommunityStore.shared.blocked, reported = CommunityStore.shared.reported
        var out: [Spot] = []
        for p in posts where p.parent == nil && !blocked.contains(p.author) && !reported.contains(p.id) {
            guard let (name, x, y) = Self.parse(p.text) else { continue }
            let against = posts.filter { $0.parent == p.id && $0.text == Self.gone }
            var t = Tally(yes: p.votes + (p.voted && p.mine ? 0 : 1), no: Set(against.map(\.author)).count)
            if let m = against.first(where: { $0.mine }) { t.mine = -1; t.marker = m } else if p.voted || p.mine { t.mine = 1 }
            // Rejeté par les joueurs : il disparaît (sauf pour celui qui l'a ajouté, qui peut le retirer).
            if t.rejected && !p.mine { continue }
            let s = Spot(post: p, name: name, x: x, y: y)
            out.append(s)
            tallies[s.id] = t
        }
        spots = out
    }

    /// Les votes d'un véhicule de la carte (lus quand on ouvre sa fiche).
    func loadTally(_ place: VFPlace) async {
        guard place.openMap, ShotMode.route == nil else { return }
        guard let posts = await CommunityStore.shared.thread(place.id) else { return }
        var last: [String: VFPost] = [:]
        for p in posts.sorted(by: { $0.created < $1.created }) where p.parent == nil && Self.isMarker(p.text) { last[p.author] = p }
        var t = Tally()
        for p in last.values { if p.text == Self.here { t.yes += 1 } else { t.no += 1 } }
        if let m = last.values.first(where: { $0.mine }) { t.mine = m.text == Self.here ? 1 : -1; t.marker = m }
        tallies[place.id] = t
    }

    /// Voter : 1 « il est là », -1 « pas là ». Le même vote une seconde fois le retire.
    func vote(_ place: VFPlace, _ value: Int) async throws {
        let c = CommunityStore.shared
        let t = tallies[place.id] ?? Tally()
        if place.openMap {
            if let m = t.marker { await c.act(m, "delete") }
            if t.mine != value { try await c.post(topic: place.id, text: value > 0 ? Self.here : Self.gone, parent: nil, spoiler: false) }
            await loadTally(place)
        } else if let s = spots.first(where: { $0.id == place.id }) {
            if let m = t.marker { await c.act(m, "delete") }
            if value > 0 {
                if !s.post.mine { await c.act(s.post, "vote", extra: ["on": t.mine != 1]) }
            } else {
                if s.post.voted { await c.act(s.post, "vote", extra: ["on": false]) }
                if t.mine != -1 { try await c.post(topic: Self.topic, text: Self.gone, parent: s.post.id, spoiler: false) }
            }
            await loadSpots()
        }
    }

    /// Ajouter l'endroit où l'on a trouvé un véhicule (position sur la carte, de 0 à 1).
    func add(name: String, x: Double, y: Double) async throws {
        let clean = name.replacingOccurrences(of: "@", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let posix = Locale(identifier: "en_US_POSIX")
        let text = clean + " @ " + String(format: "%.4f", locale: posix, min(1, max(0, x))) + "," + String(format: "%.4f", locale: posix, min(1, max(0, y)))
        try await CommunityStore.shared.post(topic: Self.topic, text: text, parent: nil, spoiler: false)
        await loadSpots()
    }

    func remove(_ s: Spot) async {
        await CommunityStore.shared.act(s.post, "delete")
        spots.removeAll { $0.id == s.id }
    }

    func report(_ s: Spot, reason: String) async {
        await CommunityStore.shared.report(s.post, reason: reason)
        spots.removeAll { $0.id == s.id }
    }

    /// Pour les captures : deux emplacements de joueurs et quelques votes, sans réseau.
    private func demo() {
        let now = Date().timeIntervalSince1970 * 1000
        func post(_ id: String, _ alias: String, _ text: String, _ votes: Int) -> VFPost {
            VFPost(id: id, topic: Self.topic, parent: nil, text: text, alias: alias, lang: "en", created: now - 3_600_000,
                   spoiler: false, votes: votes, voted: false, mine: false, author: String(repeating: "c", count: 12))
        }
        spots = [Spot(post: post("demo1", "Mia_VC", "Pegassi Tempesta @ 0.8100,0.4700", 6), name: "Pegassi Tempesta", x: 0.81, y: 0.47),
                 Spot(post: post("demo2", "KeysRunner", "Bravado Banshee @ 0.7700,0.5300", 1), name: "Bravado Banshee", x: 0.77, y: 0.53)]
        tallies["c-demo1"] = Tally(yes: 7, no: 0)
        tallies["c-demo2"] = Tally(yes: 2, no: 1)
        for (i, p) in ContentStore.shared.content.places.filter({ $0.openMap }).enumerated() {
            tallies[p.id] = Tally(yes: 3 + (i * 7) % 19, no: i % 4 == 0 ? 1 : 0, mine: i % 3 == 0 ? 1 : 0)
        }
    }
}

extension ContentStore {
    /// Tous les lieux de la carte : ceux du guide, puis les véhicules rares ajoutés par les joueurs.
    var mapPlaces: [VFPlace] { content.places + CarStore.shared.places }
}

/// Sur la fiche d'un véhicule rare : « il est là » ou « pas là », et ce qu'en disent les joueurs.
struct CarVoteRow: View {
    var place: VFPlace
    var close: () -> Void
    @State private var cars = CarStore.shared
    @State private var hub = GameCenterHub.shared
    @State private var busy = false
    @State private var error: String?
    @State private var showRules = false
    @State private var pending = 0
    @State private var reporting = false
    @AppStorage("vicefold.rulesAccepted") private var rulesAccepted = false

    var body: some View {
        let t = cars.tallies[place.id] ?? CarStore.Tally()
        VStack(alignment: .leading, spacing: 6) {
            if t.confirmed {
                Label("Confirmed by players", systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(VF.palm)
            } else if t.rejected {
                Label("Players say it isn't here", systemImage: "xmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(VF.sunset)
            } else if place.playerSpot {
                Label("Added by a player, not confirmed yet", systemImage: "questionmark.circle").font(.caption).foregroundStyle(VF.textDim)
            }
            HStack(spacing: 8) {
                voteButton(1, "It's here", "hand.thumbsup.fill", t.yes, t.mine == 1)
                voteButton(-1, "Not here", "hand.thumbsdown.fill", t.no, t.mine == -1)
            }
            if let error {
                Text(error).font(.caption2).foregroundStyle(VF.sunset)
            } else if !hub.signedIn {
                Text("Sign in to Game Center to vote.").font(.caption2).foregroundStyle(VF.textDim)
            }
            if let s = cars.spots.first(where: { $0.id == place.id }) {
                if s.post.mine {
                    Button("Remove my vehicle", systemImage: "trash") { Task { await cars.remove(s); close() } }
                        .font(.caption.weight(.semibold)).tint(VF.sunset)
                } else {
                    Button("Report", systemImage: "exclamationmark.bubble") { reporting = true }
                        .font(.caption.weight(.semibold)).tint(VF.textDim)
                }
            }
        }
        .task(id: place.id) { await cars.loadTally(place) }
        .sheet(isPresented: $showRules) { RulesSheet { rulesAccepted = true; Task { await send(pending) } } }
        .confirmationDialog("Report this message?", isPresented: $reporting, titleVisibility: .visible) {
            Button("Report", role: .destructive) {
                if let s = cars.spots.first(where: { $0.id == place.id }) { Task { await cars.report(s, reason: "wrong or offensive vehicle spot"); close() } }
            }
        } message: { Text("It disappears for you now. After 3 reports it's hidden for everyone until we review it.") }
    }

    private func voteButton(_ value: Int, _ title: LocalizedStringKey, _ icon: String, _ count: Int, _ on: Bool) -> some View {
        Button {
            if rulesAccepted { Task { await send(value) } } else { pending = value; showRules = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                Text(verbatim: "\(count)").monospacedDigit()
            }
        }
        .buttonStyle(.vf(on ? .done : .secondary, compact: true))
        .disabled(busy)
    }

    private func send(_ value: Int) async {
        guard hub.signedIn, hub.author != nil else { hub.authenticate(); return }
        busy = true
        defer { busy = false }
        do {
            try await cars.vote(place, value)
            error = nil
        } catch CommunityError.limit {
            error = String(localized: "You've posted a lot today. Try again tomorrow.")
        } catch CommunityError.banned {
            error = String(localized: "Your messages are no longer accepted in the community.")
        } catch {
            self.error = String(localized: "Couldn't send. Check your connection and try again.")
        }
    }
}

/// Ajouter un véhicule rare à l'endroit que montre le centre de la carte.
struct CarSpotEditor: View {
    var x: Double
    var y: Double
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hub = GameCenterHub.shared
    @State private var sending = false
    @State private var error: String?
    @State private var showRules = false
    @AppStorage("vicefold.rulesAccepted") private var rulesAccepted = false

    var body: some View {
        let ready = name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        List {
            Group {
                Section {
                    TextField("Vehicle name", text: $name)
                    Text("Use the name shown in the game. The spot is the center of the map: move the map first if it isn't right there.")
                        .font(.footnote).foregroundStyle(VF.textDim)
                }
                Section {
                    Button {
                        if rulesAccepted { Task { await send() } } else { showRules = true }
                    } label: {
                        Label("Share with players", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.vf(.primary))
                    .disabled(sending || !ready)
                    .opacity(sending || !ready ? 0.5 : 1)
                    if let error { Text(error).font(.footnote).foregroundStyle(VF.sunset) }
                    if !hub.signedIn {
                        Text("Sign in to Game Center to post. Your Game Center name signs your messages.").font(.footnote).foregroundStyle(VF.textDim)
                    }
                    Text("Other players vote: confirmed spots stay, wrong ones disappear.").font(.footnote).foregroundStyle(VF.textDim)
                }
            }
            .vfRows()
        }
        .navigationTitle("Add a rare vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .vfScreen()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .task { if hub.used { hub.authenticate() } }
        .sheet(isPresented: $showRules) { RulesSheet { rulesAccepted = true; Task { await send() } } }
    }

    private func send() async {
        guard hub.signedIn, hub.author != nil else { hub.authenticate(); return }
        sending = true
        defer { sending = false }
        do {
            try await CarStore.shared.add(name: name, x: x, y: y)
            dismiss()
        } catch CommunityError.filtered {
            error = String(localized: "Your message has words or links that aren't allowed here.")
        } catch CommunityError.limit {
            error = String(localized: "You've posted a lot today. Try again tomorrow.")
        } catch CommunityError.banned {
            error = String(localized: "Your messages are no longer accepted in the community.")
        } catch {
            self.error = String(localized: "Couldn't send. Check your connection and try again.")
        }
    }
}
