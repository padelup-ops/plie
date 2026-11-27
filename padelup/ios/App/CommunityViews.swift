import SwiftUI

// Communauté : chercher un 4e, conseils, tournois, matériel. Publications, « j'aime », réponses.

struct CommunityView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var category: PostCategory? = nil
    @State private var posts: [APIPost] = []
    @State private var loaded = false
    @State private var error: String? = nil
    @State private var compose = false
    @State private var open: APIPost? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Communauté", eyebrow: "Joueurs PadelUp", seasonal: false, accessory: {
                RoundIconButton(systemImage: "square.and.pencil", filled: true) { compose = true }.accessibilityLabel("Publier")
            }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { category = nil } label: { Chip(text: "Tout", active: category == nil) }.buttonStyle(.plain)
                        ForEach(PostCategory.allCases) { c in
                            Button { category = c } label: { Chip(text: c.label, active: category == c) }.buttonStyle(.plain)
                        }
                    }
                }
                if let error { EmptyNote(title: "Communauté indisponible.", message: error) }
                if loaded && posts.isEmpty && error == nil {
                    EmptyNote(title: "Rien ici pour l'instant.", message: "Lance la discussion : cherche un 4e, partage un conseil, annonce un tournoi.",
                              actionTitle: "Publier") { compose = true }
                }
                VStack(spacing: 0) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { i, p in
                        Button { open = p } label: { PostRow(post: p) }.buttonStyle(.plain)
                        if i < posts.count - 1 { Hairline() }
                    }
                }
            }
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .task(id: category) { await load() }
        .sheet(isPresented: $compose) { ComposePostView { Task { await load() } } }
        .sheet(item: $open) { p in PostDetailView(post: p) { Task { await load() } } }
    }

    private func load() async {
        if ShotMode.current != nil { posts = ShotMode.demoPosts(); loaded = true; return }
        guard server.isLoggedIn else { loaded = true; return }
        do { posts = try await server.posts(category: category); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct PostRow: View {
    var post: APIPost
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(name: post.authorInfo?.username ?? "?", size: 30)
                Text(post.authorInfo?.username ?? "Joueur").font(.system(size: 14, weight: .semibold)).foregroundStyle(UI.ink)
                if let d = post.date { Text(FR.relative(d)).font(UI.small()).foregroundStyle(UI.faint) }
                Spacer()
                if let c = post.category, let cat = PostCategory(rawValue: c), cat != .general {
                    Stamp(text: cat.label, style: cat == .looking_for_players ? .ball : .outline)
                }
            }
            Text(post.title).font(UI.title(18)).foregroundStyle(UI.ink).multilineTextAlignment(.leading)
            Text(post.content).font(UI.callout()).foregroundStyle(UI.ink.opacity(0.85)).lineLimit(compact ? 2 : 4).multilineTextAlignment(.leading)
            HStack(spacing: 16) {
                Label("\(post.likeCount ?? 0)", systemImage: post.isLiked == true ? "heart.fill" : "heart")
                Label("\(post.replyCount ?? 0)", systemImage: "bubble.left")
                if let city = post.city, !city.isEmpty { Label(city, systemImage: "mappin") }
            }
            .font(UI.score(14)).foregroundStyle(UI.muted)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct PostDetailView: View {
    @State var post: APIPost
    var onChange: () -> Void = {}
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var replies: [APIReply] = []
    @State private var draft = ""
    @State private var liked = false
    @State private var likes = 0

    var body: some View {
        NavigationStack {
            Screen(title: post.title, eyebrow: [post.authorInfo?.username, post.categoryDisplay].compactMap { $0 }.joined(separator: " · "), seasonal: false) {
                Text(post.content).font(UI.body()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Button {
                        Task {
                            if let l = try? await server.toggleLike(post.id) { liked = l; likes += l ? 1 : -1; onChange() }
                        }
                    } label: { Label("\(likes)", systemImage: liked ? "heart.fill" : "heart") }
                    .buttonStyle(LinkButtonStyle(color: liked ? UI.clay : UI.ink))
                    if let city = post.city, !city.isEmpty { Label(city, systemImage: "mappin").font(UI.callout()).foregroundStyle(UI.muted) }
                }
                Block(title: "Réponses", meta: "\(replies.count)") {
                    VStack(alignment: .leading, spacing: 14) {
                        if replies.isEmpty { Text("Sois le premier à répondre.").font(UI.callout()).foregroundStyle(UI.muted) }
                        ForEach(replies) { r in
                            HStack(alignment: .top, spacing: 10) {
                                Avatar(name: r.authorInfo?.username ?? "?", size: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.authorInfo?.username ?? "Joueur").font(.system(size: 14, weight: .semibold)).foregroundStyle(UI.ink)
                                    Text(r.content).font(UI.callout()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            InputField(title: "Répondre", text: $draft)
                            Button {
                                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                draft = ""
                                Task {
                                    try? await server.reply(post.id, content: text)
                                    replies = (try? await server.replies(post.id)) ?? replies
                                    onChange()
                                }
                            } label: {
                                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(UI.onCourt)
                                    .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.court))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Envoyer")
                        }
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .task {
            liked = post.isLiked ?? false
            likes = post.likeCount ?? 0
            if ShotMode.current != nil { replies = post.replies ?? []; return }
            replies = (try? await server.replies(post.id)) ?? (post.replies ?? [])
        }
    }
}

struct ComposePostView: View {
    var onPosted: () -> Void = {}
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var category: PostCategory = .looking_for_players
    @State private var title = ""
    @State private var content = ""
    @State private var city = ""
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Publier", seasonal: false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PostCategory.allCases) { c in
                            Button { category = c } label: { Chip(text: c.label, active: category == c) }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(spacing: 10) {
                    InputField(title: category == .looking_for_players ? "Ex. : cherche un 4e jeudi 19 h" : "Titre", text: $title)
                    TextField("Ton message", text: $content, axis: .vertical)
                        .lineLimit(4...10)
                        .font(UI.body())
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.raised))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
                    InputField(title: "Ville (facultatif)", text: $city, systemImage: "mappin")
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await server.createPost(title: title.trimmingCharacters(in: .whitespaces), content: content, category: category, city: city)
                            onPosted()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text("Publier") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .onAppear { if city.isEmpty { city = server.me?.profile?.location ?? "" } }
    }
}
