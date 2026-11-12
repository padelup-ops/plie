import CryptoKit
import GameKit
import SwiftUI

// MARK: - La boîte à idées (les 2 000)
//
// Les utilisateurs proposent des idées pour Foldly et votent ; le développeur répond (prévu, fait, pas pour l'instant).
// Serveur : foldly.netlify.app/api/ideas (fonction Netlify). On s'identifie avec son pseudo Game Center ; le serveur ne
// reçoit qu'une empreinte de l'identifiant du joueur, jamais l'identifiant lui-même.
// Règles d'Apple pour le contenu publié par les utilisateurs : règles acceptées avant de publier, filtre, signalement,
// blocage d'un auteur, et modération par le développeur (foldly.netlify.app/idees/admin.html).

struct Idea: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let alias: String
    let folds: Int
    let created: Double
    let status: String
    let reply: String?
    var votes: Int
    var voted: Bool
    let mine: Bool
    let author: String

    var date: Date { Date(timeIntervalSince1970: created / 1000) }
}

enum IdeasRule {
    static let promoKey = "ideasPromoHidden"
    static let rulesKey = "ideasRulesAccepted"
    static let blockedKey = "ideasBlocked"
    static var promoHidden: Bool {
        get { UserDefaults.standard.bool(forKey: promoKey) }
        set { UserDefaults.standard.set(newValue, forKey: promoKey) }
    }
    static var blocked: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: blockedKey) }
    }
}

@MainActor
@Observable
final class IdeasService {
    static let shared = IdeasService()
    private let base = URL(string: "https://foldly.netlify.app/api/ideas")!

    private(set) var ideas: [Idea] = []
    private(set) var loading = false
    var error: String?

    /// Connecté à Game Center (le pseudo sert de nom).
    var signedIn: Bool { GKLocalPlayer.local.isAuthenticated }
    var alias: String { GKLocalPlayer.local.alias }

    /// L'empreinte de l'identifiant Game Center : stable, mais ne révèle pas le joueur.
    var author: String? {
        guard signedIn else { return nil }
        let id = GKLocalPlayer.local.teamPlayerID
        guard !id.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(("foldly.ideas." + id).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func load() async {
        loading = true
        defer { loading = false }
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        if let author { c.queryItems = [URLQueryItem(name: "me", value: author)] }
        do {
            let (data, _) = try await URLSession.shared.data(from: c.url!)
            struct List: Decodable { let ideas: [Idea] }
            ideas = try JSONDecoder().decode(List.self, from: data).ideas
            error = nil
        } catch {
            self.error = String(localized: "Can't reach the ideas right now. Check your connection.")
        }
    }

    private func post(_ path: String, _ body: [String: Any]) async -> (Bool, String?) {
        guard let author else { return (false, "signin") }
        var b = body
        b["author"] = author
        var req = URLRequest(url: path.isEmpty ? base : base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: b)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (false, "network") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code) { return (true, nil) }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        return (false, msg ?? "network")
    }

    /// Envoie une idée. Renvoie un message d'erreur à montrer, ou nil.
    func submit(title: String, body: String, folds: Int) async -> String? {
        let (ok, err) = await post("", ["title": title, "body": body, "alias": alias, "folds": folds,
                                        "lang": Locale.current.language.languageCode?.identifier ?? ""])
        if ok { await load(); return nil }
        switch err {
        case "filtered": return String(localized: "Your idea contains words or links that aren't allowed. Please rephrase it.")
        case "limit": return String(localized: "You can share up to 3 ideas a day. Come back tomorrow!")
        case "short": return String(localized: "Give your idea a title of a few words.")
        case "banned": return String(localized: "You can no longer post ideas.")
        case "signin": return String(localized: "Sign in to Game Center to share an idea.")
        default: return String(localized: "Can't reach the ideas right now. Check your connection.")
        }
    }

    func vote(_ idea: Idea) async {
        guard let i = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        let on = !ideas[i].voted
        ideas[i].voted = on
        ideas[i].votes += on ? 1 : -1
        let (ok, _) = await post(idea.id + "/vote", ["on": on])
        if !ok, let j = ideas.firstIndex(where: { $0.id == idea.id }) {
            ideas[j].voted = !on
            ideas[j].votes += on ? -1 : 1
        }
    }

    func report(_ idea: Idea, reason: String) async {
        _ = await post(idea.id + "/report", ["reason": reason])
        ideas.removeAll { $0.id == idea.id }
    }

    func delete(_ idea: Idea) async {
        let (ok, _) = await post(idea.id + "/delete", [:])
        if ok { ideas.removeAll { $0.id == idea.id } }
    }
}

// MARK: - L'écran

struct IdeasView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var service = IdeasService.shared
    @State private var tab = 0
    @State private var compose = false
    @State private var blocked = IdeasRule.blocked
    @State private var reporting: Idea?
    @State private var signedIn = GKLocalPlayer.local.isAuthenticated

    private var shown: [Idea] {
        let list = service.ideas.filter { !blocked.contains($0.author) }
        switch tab {
        case 1: return list.sorted { $0.created > $1.created }
        case 2: return list.filter { $0.status == "planned" || $0.status == "done" }
        default: return list
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Picker(selection: $tab) {
                        Text("Popular").tag(0)
                        Text("New").tag(1)
                        Text("Planned & done").tag(2)
                    } label: { EmptyView() }
                    .pickerStyle(.segmented)
                    if let e = service.error, service.ideas.isEmpty {
                        Label(e, systemImage: "wifi.slash").font(.subheadline).foregroundStyle(.secondary)
                    } else if service.loading && service.ideas.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if shown.isEmpty {
                        Text(tab == 2 ? "Nothing planned yet: vote for the ideas you want!" : "No ideas yet. Be the first!")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    }
                    ForEach(shown) { idea in
                        IdeaRow(idea: idea, canVote: signedIn) {
                            if signedIn { Task { await service.vote(idea) } } else { signIn() }
                        } onReport: {
                            reporting = idea
                        } onBlock: {
                            blocked.insert(idea.author)
                            IdeasRule.blocked = blocked
                        } onDelete: {
                            Task { await service.delete(idea) }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await service.load() }
            .background(Color.dfBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    if signedIn { compose = true } else { signIn() }
                } label: {
                    Label { Text(signedIn ? "Share an idea" : "Sign in with Game Center to post") } icon: { Image(systemName: signedIn ? "plus" : "gamecontroller.fill") }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Color.dfAccent))
                        .foregroundStyle(Color.dfOnAccent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: 520)
            }
            .navigationTitle(Text("Ideas"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $compose) {
                NewIdeaView(folds: model.stats.totalCloses).presentationDetents([.large])
            }
            .confirmationDialog(Text("Report this idea?"), isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible) {
                if let idea = reporting {
                    Button("Offensive or inappropriate", role: .destructive) { Task { await service.report(idea, reason: "offensive") } }
                    Button("Spam or advertising", role: .destructive) { Task { await service.report(idea, reason: "spam") } }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text("It disappears for you right away, and we review it within 24 hours.")
            }
            .task { await service.load() }
            .onReceive(NotificationCenter.default.publisher(for: .gameCenterSignedIn)) { _ in
                signedIn = true
                Task { await service.load() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your ideas.")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            Text("Our community.")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Color.dfAccent)
            Text("Thank you for 2,000 downloads! Suggest what Foldly should do next and vote for the ideas you like. I read every one and answer here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private func signIn() {
        GameCenter.shared.signIn()
    }
}

struct IdeaRow: View {
    let idea: Idea
    let canVote: Bool
    var onVote: () -> Void
    var onReport: () -> Void
    var onBlock: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: onVote) {
                VStack(spacing: 2) {
                    Image(systemName: idea.voted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                        .font(.body.weight(.bold))
                    Text("\(idea.votes)").font(.subheadline.weight(.bold)).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(idea.voted ? Color.dfOnAccent : Color.dfAccent)
                .frame(width: 48, height: 58)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(idea.voted ? Color.dfAccent : Color.dfAccent.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(idea.voted ? "Remove my vote" : "Vote"))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: idea.voted)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(idea.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Menu {
                        if idea.mine {
                            Button("Delete my idea", systemImage: "trash", role: .destructive, action: onDelete)
                        } else {
                            Button("Report", systemImage: "exclamationmark.bubble", action: onReport)
                            Button("Block this person", systemImage: "hand.raised", action: onBlock)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
                if !idea.body.isEmpty {
                    Text(idea.body).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text(idea.alias).font(.caption.weight(.semibold))
                    if idea.folds > 0 {
                        Text(String(format: NSLocalizedString("%@ folds in total", comment: ""), idea.folds.formatted()))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.dfFill))
                    }
                    Text(idea.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                if let label = statusLabel {
                    Label { label } icon: { Image(systemName: statusIcon) }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(statusColor.opacity(0.14)))
                }
                if let reply = idea.reply, !reply.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.bubble.fill").font(.subheadline).foregroundStyle(Color.dfAccent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Foldly").font(.caption.weight(.bold))
                            Text(reply).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.dfFill))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.dfCard))
    }

    private var statusLabel: Text? {
        switch idea.status {
        case "planned": return Text("Planned")
        case "done": return Text("Done")
        case "declined": return Text("Not for now")
        default: return nil
        }
    }
    private var statusIcon: String {
        switch idea.status {
        case "planned": return "hammer.fill"
        case "done": return "checkmark.seal.fill"
        default: return "moon.zzz.fill"
        }
    }
    private var statusColor: Color {
        switch idea.status {
        case "planned": return .orange
        case "done": return .green
        default: return .secondary
        }
    }
}

struct NewIdeaView: View {
    let folds: Int
    @Environment(\.dismiss) private var dismiss
    @AppStorage(IdeasRule.rulesKey) private var accepted = false
    @State private var title = ""
    @State private var details = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your idea in a few words", text: $title)
                        .focused($focus)
                        .onChange(of: title) { _, v in if v.count > 90 { title = String(v.prefix(90)) } }
                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: details) { _, v in if v.count > 600 { details = String(v.prefix(600)) } }
                } footer: {
                    Text(String(format: NSLocalizedString("Posted as %@, with your fold total.", comment: ""), IdeasService.shared.alias))
                }
                Section {
                    Toggle(isOn: $accepted) {
                        Text("I'll be kind: no insults, hate, spam or personal information. Ideas that break these rules are removed and their authors blocked.")
                            .font(.footnote)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(Text("New idea"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Post") { send() }
                            .disabled(!accepted || title.trimmingCharacters(in: .whitespaces).count < 4)
                    }
                }
            }
            .onAppear { focus = true }
        }
    }

    private func send() {
        sending = true
        Task {
            let e = await IdeasService.shared.submit(title: title, body: details, folds: folds)
            sending = false
            if let e { error = e } else { dismiss() }
        }
    }
}

// MARK: - La carte d'accueil

struct IdeasPromo: View {
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your ideas. Our community.").font(.headline)
                    Text("For the 2,000 downloads: suggest what Foldly should do next, and vote for the best ideas.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.dfFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Not now"))
            }
            Button(action: onOpen) {
                Label { Text("See the ideas") } icon: { Image(systemName: "arrow.up.right") }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dfAccent)
            .foregroundStyle(Color.dfOnAccent)
        }
    }
}
