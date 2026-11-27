// Community.swift — Vicefold
//
// L'entraide : un fil de questions et réponses par mission, et un fil général. Les joueurs signent avec leur pseudo
// Game Center (pas de compte). Règles d'Apple pour les contenus des utilisateurs (1.2) : règles acceptées avant le
// premier message, filtre côté serveur, signalement (caché après 3 signalements), blocage d'un joueur, modération.

import SwiftUI

struct VFPost: Codable, Identifiable, Hashable {
    var id: String
    var topic: String
    var parent: String?
    var text: String
    var alias: String
    var lang: String?
    var created: Double
    var spoiler: Bool?
    var votes: Int
    var voted: Bool
    var mine: Bool
    var author: String
    var date: Date { Date(timeIntervalSince1970: created / 1000) }
}

enum CommunityError: Error { case filtered, limit, banned, other }

@MainActor @Observable
final class CommunityStore {
    static let shared = CommunityStore()
    static let base = URL(string: "https://foldly.netlify.app/api/vicefold")!
    static let appURL = URL(string: "https://apps.apple.com/app/id6838298570")!

    private(set) var counts: [String: Int] = [:]
    var blocked: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "vicefold.blocked") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "vicefold.blocked"); version += 1 }
    }
    var reported: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "vicefold.reported") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "vicefold.reported"); version += 1 }
    }
    /// Change à chaque blocage ou signalement : les fils se redessinent.
    private(set) var version = 0

    /// Discord et Reddit, pour ceux qui préfèrent discuter ailleurs. Les liens viennent de Content/links.json :
    /// on les change sans mise à jour de l'app, et le bloc reste caché tant qu'aucun lien n'est donné.
    private(set) var social: [String: URL] = CommunityStore.cachedSocial()

    nonisolated private static func cachedSocial() -> [String: URL] {
        let saved = UserDefaults.standard.dictionary(forKey: "vicefold.social") as? [String: String] ?? [:]
        return saved.compactMapValues { URL(string: $0) }
    }

    func loadSocial() async {
        if ShotMode.route != nil { return }
        var req = URLRequest(url: ContentStore.remoteBase.appendingPathComponent("links.json"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (d, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode([String: String].self, from: d) else { return }
        let ok = r.filter { ["discord", "reddit"].contains($0.key) && $0.value.hasPrefix("https://") }
        UserDefaults.standard.set(ok, forKey: "vicefold.social")
        social = ok.compactMapValues { URL(string: $0) }
    }

    func loadCounts() async {
        if ShotMode.route != nil { counts = ["general": 12, "m1-01": 3, "m1-04": 5, "m2-03": 2]; return }
        guard let (d, _) = try? await URLSession.shared.data(from: Self.base.appendingPathComponent("counts")),
              let r = try? JSONDecoder().decode([String: [String: Int]].self, from: d) else { return }
        counts = r["counts"] ?? [:]
    }

    func thread(_ topic: String) async -> [VFPost]? {
        if ShotMode.route != nil { return Self.demo(topic) }
        var c = URLComponents(url: Self.base.appendingPathComponent("t/\(topic)"), resolvingAgainstBaseURL: false)!
        if let a = GameCenterHub.shared.author { c.queryItems = [URLQueryItem(name: "me", value: a)] }
        guard let (d, _) = try? await URLSession.shared.data(from: c.url!),
              let r = try? JSONDecoder().decode([String: [VFPost]].self, from: d) else { return nil }
        return r["posts"]
    }

    func post(topic: String, text: String, parent: String?, spoiler: Bool) async throws {
        var body: [String: Any] = ["author": GameCenterHub.shared.author ?? "", "alias": GameCenterHub.shared.alias,
                                   "lang": ContentStore.lang, "text": text, "spoiler": spoiler]
        if let parent { body["parent"] = parent }
        let status = await send("t/\(topic)", body)
        switch status {
        case 200: counts[topic, default: 0] += parent == nil ? 1 : 0
        case 422: throw CommunityError.filtered
        case 429: throw CommunityError.limit
        case 403: throw CommunityError.banned
        default: throw CommunityError.other
        }
    }

    func act(_ p: VFPost, _ action: String, extra: [String: Any] = [:]) async {
        var body = extra
        body["author"] = GameCenterHub.shared.author ?? ""
        _ = await send("p/\(p.topic)/\(p.id)/\(action)", body)
    }

    func report(_ p: VFPost, reason: String) async {
        reported.insert(p.id)
        await act(p, "report", extra: ["reason": reason])
    }

    private func send(_ path: String, _ body: [String: Any]) async -> Int {
        guard ShotMode.route == nil else { return 200 }
        var req = URLRequest(url: Self.base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, r) = try? await URLSession.shared.data(for: req) else { return 0 }
        return (r as? HTTPURLResponse)?.statusCode ?? 0
    }

    static func demo(_ topic: String) -> [VFPost] {
        let now = Date().timeIntervalSince1970 * 1000
        func p(_ id: String, _ parent: String?, _ alias: String, _ text: String, _ mins: Double, _ votes: Int) -> VFPost {
            VFPost(id: id, topic: topic, parent: parent, text: text, alias: alias, lang: "en", created: now - mins * 60_000,
                   spoiler: false, votes: votes, voted: false, mine: alias == "Alex", author: String(repeating: "b", count: 12))
        }
        return [
            p("q1", nil, "KeysRunner", "The guard keeps spotting me at the office door. Is there another way in?", 50, 4),
            p("a1", "q1", "Mia_VC", "Wait behind the vending machine until he turns toward the window, then go left along the wall. Crouch the whole time.", 41, 9),
            p("a2", "q1", "Alex", "Same here, the left wall worked for me too. Thanks!", 12, 2),
            p("q2", nil, "Port Gellhorn Pete", "Does failing the chase at the end change anything later?", 180, 2),
            p("a3", "q2", "Mia_VC", "No, the story goes on either way. You just miss a little bonus cash.", 160, 6),
        ]
    }
}

// MARK: - L'écran Communauté

struct CommunityView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var community = CommunityStore.shared
    @State private var hub = GameCenterHub.shared
    @State private var section = ShotMode.route == "friends" ? 1 : 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Section", selection: $section) {
                    Text("Help").tag(0)
                    Text("Friends").tag(1)
                }
                .pickerStyle(.segmented)
                if section == 0 { help } else { friends }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationTitle("Community")
        // Tirer pour rafraîchir : les compteurs de l'entraide, et les amis.
        .refreshable {
            await community.loadCounts()
            if section == 1 { await hub.loadFriends() }
        }
        .task {
            if section == 1 || hub.used { hub.authenticate() }
            await community.loadCounts()
            await community.loadSocial()
        }
        .onChange(of: section) { _, s in if s == 1 { hub.authenticate() } }
        .navigationDestination(isPresented: .constant(ShotMode.route == "thread")) {
            ThreadView(topic: "m1-04", title: ContentStore.shared.content.missions.first { $0.id == "m1-04" }?.title ?? "", chapter: 1)
        }
    }

    // MARK: Entraide

    /// Discord et Reddit, à côté de l'entraide de l'app.
    private var social: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prefer Discord or Reddit? Chat with other players there too.")
                .font(.caption).foregroundStyle(VF.textDim)
            HStack(spacing: 10) {
                if let url = community.social["discord"] { socialLink("Discord", "bubble.left.and.text.bubble.right.fill", url) }
                if let url = community.social["reddit"] { socialLink("Reddit", "person.3.fill", url) }
            }
        }
    }

    private func socialLink(_ name: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(VF.sky)
                Text(verbatim: name).fontWeight(.semibold).foregroundStyle(VF.text)
                Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(VF.textFaint)
            }
            .frame(maxWidth: .infinity)
            .vfCard(radius: 14, padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens outside the app"))
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 18) {
            NavigationLink { ThreadView(topic: "general", title: String(localized: "General")) } label: {
                HStack(spacing: 14) {
                    VFIconBadge(icon: "bubble.left.and.bubble.right.fill", color: VF.flamingo, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ask the community").font(VF.display(24)).foregroundStyle(VF.text).multilineTextAlignment(.leading)
                        Text("Questions about anything in Leonida. No spoilers here: use a mission's thread for those.")
                            .font(.caption).foregroundStyle(VF.textDim).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    count(community.counts["general"])
                }
                .vfCard(radius: 20, padding: 14, tint: VF.flamingo)
            }
            .buttonStyle(.plain)

            if !community.social.isEmpty { social }

            SectionTitle(title: "Missions with questions")
            let missions = content.content.missions.filter { (community.counts[$0.id] ?? 0) > 0 }
            if missions.isEmpty {
                Label("No questions yet. Open a mission and ask the first one.", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline).foregroundStyle(VF.textDim).vfCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(missions) { m in
                        let hidden = progress.hidden(m.chapter)
                        NavigationLink { ThreadView(topic: m.id, title: m.title, chapter: m.chapter) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hidden ? String(localized: "Hidden mission") : m.title).font(.body.weight(.semibold)).foregroundStyle(VF.text).multilineTextAlignment(.leading)
                                    if let c = content.chapter(m.chapter) { Text(hidden ? String(localized: "Chapter \(c.id)") : c.title).font(.caption).foregroundStyle(VF.textDim) }
                                }
                                Spacer()
                                count(community.counts[m.id])
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(VF.textFaint)
                            }
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if m.id != missions.last?.id { Rectangle().fill(VF.hairline).frame(height: 1) }
                    }
                }
                .vfCard(radius: 20, padding: 14)
            }
            RulesFooter()
        }
    }

    private func count(_ n: Int?) -> some View {
        Text(verbatim: "\(n ?? 0)").font(VF.mono(11, weight: .bold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(VF.flamingo.opacity(0.16), in: .capsule).foregroundStyle(VF.flamingo)
            .overlay(Capsule().stroke(VF.flamingo.opacity(0.4), lineWidth: 1))
    }

    // MARK: Amis

    @ViewBuilder private var friends: some View {
        if !hub.signedIn {
            VStack(alignment: .leading, spacing: 12) {
                VFIconBadge(icon: "person.2.fill", color: VF.flamingo, size: 52)
                Text("Play with friends").font(VF.display(28)).foregroundStyle(VF.text)
                Text("Sign in to Game Center to add friends and compare your 100%. No account to create.")
                    .font(.subheadline).foregroundStyle(VF.textDim)
                Button { hub.authenticate() } label: { Label("Sign in to Game Center", systemImage: "gamecontroller.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.vfPrimary)
                if hub.failed {
                    Text("Game Center is off. Turn it on in Settings > Game Center.").font(.caption).foregroundStyle(VF.sun)
                }
            }
            .vfCard(tint: VF.flamingo)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "Leonida with friends")
                    Spacer()
                    if hub.loading { ProgressView() }
                }
                VStack(spacing: 0) {
                    ForEach(Array(hub.friends.enumerated()), id: \.element.id) { i, f in
                        HStack(spacing: 12) {
                            Text(verbatim: "\(i + 1)").font(VF.display(20)).monospacedDigit().foregroundStyle(i == 0 ? VF.sun : VF.textDim).frame(width: 26)
                            Monogram(name: f.name, size: 40)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(f.name).font(.body.weight(.semibold)).foregroundStyle(VF.text).lineLimit(1)
                                    if f.isMe { Text("You").font(VF.mono(9.5, weight: .bold)).textCase(.uppercase).padding(.horizontal, 6).padding(.vertical, 2).background(VF.cyan.opacity(0.16), in: .capsule).foregroundStyle(VF.cyan) }
                                }
                                if let p = f.percent {
                                    VFBar(value: Double(p) / 100, height: 6)
                                } else {
                                    Text("Hasn't shared progress yet").font(.caption).foregroundStyle(VF.textDim)
                                }
                            }
                            Text(f.percent.map { "\($0)%" } ?? "—").font(VF.display(22)).monospacedDigit()
                                .foregroundStyle(f.isMe ? AnyShapeStyle(VF.gradient) : AnyShapeStyle(VF.text))
                                .frame(minWidth: 52, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        if i < hub.friends.count - 1 { Rectangle().fill(VF.hairline).frame(height: 1) }
                    }
                }
                .vfCard(radius: 20, padding: 14)
                if hub.friends.count <= 1 {
                    Text("No friends here yet. Add your Game Center friends, or invite someone who plays.")
                        .font(.subheadline).foregroundStyle(VF.textDim)
                }
                if hub.friendsDenied {
                    Text("Vicefold can't see your Game Center friends. Allow it in Settings > Game Center > Friends.")
                        .font(.caption).foregroundStyle(VF.sun)
                }
                HStack(spacing: 12) {
                    Button { hub.addFriends() } label: { Label("Add friends", systemImage: "person.badge.plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.vfPrimary)
                    ShareLink(item: CommunityStore.appURL, message: Text("Track your GTA VI 100% with me on Vicefold.")) {
                        Label("Invite", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.vfSecondary)
                }
                Text("Your progress is shared through Game Center with your friends only.").font(.caption).foregroundStyle(VF.textDim)
            }
        }
    }
}

struct RulesFooter: View {
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Label("Community rules", systemImage: "hand.raised").font(.footnote.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(VF.textDim)
        .sheet(isPresented: $show) { RulesSheet(accept: nil) }
    }
}

/// Les règles, à accepter avant le premier message (Apple le demande pour les contenus des utilisateurs).
struct RulesSheet: View {
    var accept: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var blocked = CommunityStore.shared.blocked

    var body: some View {
        NavigationStack {
            List {
                Group {
                Section {
                    Label("Be kind. No insults, hate, threats or harassment.", systemImage: "heart")
                    Label("No spoilers outside a mission's own thread. Mark spoilers when you post.", systemImage: "eye.slash")
                    Label("No links, ads, personal details or cheating for money.", systemImage: "link")
                    Label("Anything else that breaks these rules gets removed, and repeat offenders are blocked.", systemImage: "trash")
                } footer: {
                    Text("Report a message with … on it: after 3 reports it's hidden until we review it. Block a player to stop seeing their messages. To reach us: foldly.netlify.app/vicefold")
                }
                if !blocked.isEmpty {
                    Section("Blocked players") {
                        Button("Unblock everyone (\(blocked.count))") {
                            CommunityStore.shared.blocked = []
                            blocked = []
                        }
                    }
                }
                }
                .vfRows()
            }
            .navigationTitle("Community rules")
            .navigationBarTitleDisplayMode(.inline)
            .vfScreen()
            .toolbar {
                if let accept {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("I agree") { accept(); dismiss() }.bold() }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Un fil

struct ThreadView: View {
    var topic: String
    var title: String
    var chapter: Int? = nil
    @Environment(Progress.self) private var progress
    @State private var community = CommunityStore.shared
    @State private var hub = GameCenterHub.shared
    @State private var posts: [VFPost]?
    @State private var text = ""
    @State private var replyTo: VFPost?
    @State private var spoiler = false
    @State private var sending = false
    @State private var error: String?
    @State private var showRules = false
    @State private var reporting: VFPost?
    @State private var revealed: Set<String> = []
    @State private var failed = false
    @AppStorage("vicefold.rulesAccepted") private var rulesAccepted = false
    @FocusState private var focused: Bool

    var body: some View {
        let _ = community.version
        let hiddenMission = chapter.map { progress.hidden($0) } ?? false
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(hiddenMission ? String(localized: "Hidden mission") : title).font(VF.display(34)).foregroundStyle(VF.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let posts {
                    // Les votes « il est là / pas là » des véhicules rares sont des messages à part : ils ne s'affichent pas ici.
                    let visible = posts.filter { !community.blocked.contains($0.author) && !community.reported.contains($0.id) && !CarStore.isMarker($0.text) }
                    let questions = visible.filter { $0.parent == nil }.sorted { $0.created > $1.created }
                    if questions.isEmpty {
                        Label("No questions yet. Ask the first one below.", systemImage: "bubble.left.and.bubble.right")
                            .font(.subheadline).foregroundStyle(VF.textDim).vfCard()
                    }
                    ForEach(questions) { q in
                        VStack(alignment: .leading, spacing: 10) {
                            row(q, question: true)
                            let answers = visible.filter { $0.parent == q.id }.sorted { ($0.votes, -$0.created) > ($1.votes, -$1.created) }
                            ForEach(answers) { a in
                                row(a, question: false).padding(.leading, 16)
                                    .overlay(alignment: .leading) { Capsule().fill(VF.ice).frame(width: 3).shadow(color: VF.cyan.opacity(0.6), radius: 4) }
                            }
                            Button { replyTo = q; focused = true } label: {
                                Label("Answer", systemImage: "arrowshape.turn.up.left").font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.plain).foregroundStyle(VF.flamingo)
                        }
                        .vfCard(radius: 20, padding: 14)
                    }
                    RulesFooter().padding(.top, 4)
                } else if failed {
                    // Pas de réseau, ou le serveur ne répond pas : on le dit, avec un bouton pour réessayer.
                    VStack(spacing: 4) {
                        VFEmptyState(icon: "wifi.slash", title: "Couldn't load the thread", message: "Check your connection and try again.")
                        Button { Task { await load() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                            .buttonStyle(.vf(.secondary, compact: true))
                            .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .vfCard()
                } else {
                    ProgressView().tint(VF.flamingo).frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .task { if hub.used { hub.authenticate() }; await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showRules) { RulesSheet { rulesAccepted = true; Task { await send() } } }
        .alert("Not posted", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Report this message?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible) {
            ForEach(["Spoiler", "Offensive", "Spam", "Other"], id: \.self) { r in
                Button(LocalizedStringKey(r)) { if let p = reporting { Task { await community.report(p, reason: r) } } }
            }
        } message: { Text("It disappears for you now. After 3 reports it's hidden for everyone until we review it.") }
    }

    private func load() async {
        failed = false
        let loaded = await community.thread(topic)
        // Un rafraîchissement raté ne vide pas un fil déjà affiché ; un premier chargement raté le dit.
        if let loaded { posts = loaded } else if posts == nil { failed = true }
    }

    private func row(_ p: VFPost, question: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Monogram(name: p.alias, size: 26)
                Text(p.alias).font(.subheadline.weight(.semibold)).foregroundStyle(p.mine ? VF.cyan : VF.text).lineLimit(1)
                Text(p.date, format: .relative(presentation: .named, unitsStyle: .abbreviated)).font(.caption).foregroundStyle(VF.textDim).lineLimit(1)
                Spacer()
                Menu {
                    if p.mine {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await community.act(p, "delete"); await load() }
                        }
                    } else {
                        Button("Report", systemImage: "exclamationmark.bubble") { reporting = p }
                        Button("Block \(p.alias)", systemImage: "hand.raised") { community.blocked.insert(p.author) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 26).contentShape(.rect)
                }
                .foregroundStyle(VF.textDim)
                .accessibilityLabel("More")
            }
            let hide = (p.spoiler ?? false) && !revealed.contains(p.id)
            Text(p.text)
                .font(question ? .body.weight(.semibold) : .body)
                .foregroundStyle(VF.text)
                .blur(radius: hide ? 7 : 0)
                .accessibilityHidden(hide)
                .overlay { if hide { Button("Show spoiler") { revealed.insert(p.id) }.buttonStyle(.vf(.secondary, compact: true)) } }
            if !question {
                Button {
                    Task { await community.act(p, "vote", extra: ["on": !p.voted]); await load() }
                } label: {
                    Label("Helpful \(p.votes)", systemImage: p.voted ? "hand.thumbsup.fill" : "hand.thumbsup").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(p.voted ? VF.palm : VF.textDim)
                .disabled(p.mine)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = replyTo {
                HStack {
                    Text("Answering \(r.alias)").font(.caption.weight(.semibold)).foregroundStyle(VF.cyan)
                    Spacer()
                    Button { replyTo = nil } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(VF.textDim)
                        .accessibilityLabel("Cancel")
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(replyTo == nil ? String(localized: "Ask a question") : String(localized: "Your answer"), text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(VF.hairline, lineWidth: 1))
                Button { spoiler.toggle() } label: {
                    Image(systemName: spoiler ? "eye.slash.fill" : "eye").font(.headline).frame(width: 40, height: 40)
                        .foregroundStyle(spoiler ? VF.ink : VF.text)
                        .background(spoiler ? AnyShapeStyle(VF.sun) : AnyShapeStyle(Color.white.opacity(0.08)), in: .circle)
                        .overlay(Circle().stroke(VF.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spoiler")
                .accessibilityAddTraits(spoiler ? .isSelected : [])
                Button {
                    if rulesAccepted { Task { await send() } } else { showRules = true }
                } label: {
                    Image(systemName: sending ? "hourglass" : "arrow.up").font(.headline).frame(width: 40, height: 40)
                        .background(VF.gradient, in: .circle).foregroundStyle(VF.ink)
                }
                .buttonStyle(.plain)
                .opacity(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 ? 0.45 : 1)
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                .accessibilityLabel(replyTo == nil ? "Ask a question" : "Your answer")
            }
            if !hub.signedIn {
                Text("Sign in to Game Center to post. Your Game Center name signs your messages.").font(.caption2).foregroundStyle(VF.textDim)
            }
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 6)
        .background(VF.ink.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(VF.hairline).frame(height: 1) }
    }

    private func send() async {
        guard hub.signedIn, hub.author != nil else { hub.authenticate(); return }
        sending = true
        defer { sending = false }
        do {
            try await community.post(topic: topic, text: text, parent: replyTo?.id, spoiler: spoiler)
            text = ""; replyTo = nil; spoiler = false; focused = false
            await load()
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
