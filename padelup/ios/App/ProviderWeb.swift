import SwiftUI
import WebKit

// Connexion aux plateformes (Playtomic, Anybuddy) par leur propre site, ouvert DANS l'app.
//
// Pourquoi : un navigateur Safari intégré (SFSafariViewController) garde ses cookies pour lui, l'app ne sait donc
// jamais que le joueur s'est connecté (c'était le bug Anybuddy). Ici, le site s'ouvre dans une vue web qui partage
// le stockage de l'app (WKWebsiteDataStore.default) : la session reste sur l'iPhone, l'app la voit, et les pages de
// réservation ouvertes ensuite sont déjà connectées. Le mot de passe est tapé sur le site de la plateforme :
// PadelUp ne le voit ni ne l'enregistre jamais.
enum WebAccount {
    static func key(_ p: BotProvider) -> String { "webConnected." + p.rawValue }

    static func isConnected(_ p: BotProvider) -> Bool { UserDefaults.standard.bool(forKey: key(p)) }

    static func domain(_ p: BotProvider) -> String {
        switch p {
        case .playtomic: return "playtomic"
        case .anybuddy: return "anybuddy"
        case .padelup: return "padel-up"
        }
    }

    /// Page d'accueil du compte sur le site de la plateforme.
    static func loginURL(_ p: BotProvider) -> URL {
        switch p {
        case .playtomic: return URL(string: "https://playtomic.com")!
        case .anybuddy: return URL(string: "https://www.anybuddyapp.com/fr/login")!
        case .padelup: return URL(string: "https://padel-up.io")!
        }
    }

    static func owns(_ url: URL) -> BotProvider? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("playtomic") { return .playtomic }
        if host.contains("anybuddy") { return .anybuddy }
        return nil
    }

    static func setConnected(_ p: BotProvider, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key(p))
        NotificationCenter.default.post(name: .webAccountChanged, object: nil)
    }

    // MARK: Détection de la session

    /// Nom de cookie ou de clé de stockage qui ressemble à une session (et pas à un traceur ou un consentement).
    static func looksLikeSession(name: String, value: String) -> Bool {
        let n = name.lowercased()
        let noise = ["_ga", "_gid", "_fbp", "ajs_", "amplitude", "mp_", "intercom", "didomi", "axeptio", "optanon", "consent",
                     "cookie", "hubspot", "__hs", "_hj", "crisp", "segment", "datadog", "_dd", "sentry", "lang", "locale", "theme",
                     "csrf", "xsrf", "callback", "state", "nonce", "pkce", "cf_", "__cf", "aws", "visitor", "device"]
        if noise.contains(where: { n.contains($0) }) { return false }
        if isJWT(value) { return true }
        let words = ["token", "session", "auth", "jwt", "access", "refresh", "logged", "sid"]
        return words.contains(where: { n.contains($0) }) && value.count >= 16
    }

    static func isJWT(_ value: String) -> Bool {
        let v = value.removingPercentEncoding ?? value
        return v.range(of: #"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, options: .regularExpression) != nil
    }

    /// Cookies (y compris HttpOnly) et stockage local de la page : le joueur est-il connecté ?
    @MainActor
    static func detect(_ p: BotProvider, in webView: WKWebView?) async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies().filter { $0.domain.lowercased().contains(domain(p)) }
        if cookies.contains(where: { looksLikeSession(name: $0.name, value: $0.value) }) { return true }
        guard let webView, let host = webView.url?.host?.lowercased(), host.contains(domain(p)) else { return false }
        let js = """
        (function(){var out=[];function grab(s){try{for(var i=0;i<s.length;i++){var k=s.key(i);out.push([k,String(s.getItem(k)||'').slice(0,4000)]);}}catch(e){}}
        grab(window.localStorage);grab(window.sessionStorage);return JSON.stringify(out);})()
        """
        guard let raw = try? await webView.evaluateJavaScript(js) as? String,
              let pairs = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String]] else { return false }
        return pairs.contains { pair in
            guard pair.count == 2 else { return false }
            if looksLikeSession(name: pair[0], value: pair[1]) { return true }
            // Valeur JSON contenant un jeton (ex. {"user":…,"accessToken":"…"})
            return pair[1].contains("ccess") && pair[1].contains("oken") && pair[1].count > 40
        }
    }

    /// À la fermeture de la feuille : une session repérée pendant la navigation compte aussi (la dernière page peut
    /// être celle d'un autre site, Google ou la banque).
    @MainActor
    static func refresh(_ p: BotProvider, webView: WKWebView? = nil, seen: Bool = false) async {
        let found = await detect(p, in: webView)
        setConnected(p, found || seen)
    }

    @MainActor
    static func disconnect(_ p: BotProvider) async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                               for: records.filter { $0.displayName.lowercased().contains(domain(p)) })
        setConnected(p, false)
    }

    /// En-tête Cookie pour lire les disponibilités avec la session du joueur (tarifs membre…).
    @MainActor
    static func cookieHeader(domain: String) async -> String? {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies().filter { $0.domain.contains(domain) }
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

extension Notification.Name {
    static let webAccountChanged = Notification.Name("PadelUpWebAccountChanged")
}

// MARK: - La vue web (même stockage que l'app)

@MainActor
final class WebPageModel: ObservableObject {
    @Published var title = ""
    @Published var loading = true
    @Published var signedIn = false
    @Published var canGoBack = false
    weak var webView: WKWebView?
}

struct AccountWebView: UIViewRepresentable {
    let url: URL
    let provider: BotProvider?
    @ObservedObject var model: WebPageModel

    func makeCoordinator() -> Coordinator { Coordinator(provider: provider, model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        model.webView = view
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let provider: BotProvider?
        let model: WebPageModel

        init(provider: BotProvider?, model: WebPageModel) {
            self.provider = provider
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.loading = false
            model.title = webView.title ?? ""
            model.canGoBack = webView.canGoBack
            guard let provider else { return }
            // La connexion est repérée dès que le site a posé sa session (pas besoin d'attendre « Terminé »).
            Task { @MainActor in
                let ok = await WebAccount.detect(provider, in: webView)
                if ok != self.model.signedIn { self.model.signedIn = ok }
                if ok { WebAccount.setConnected(provider, true) }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model.loading = false }

        /// Fenêtres « nouvel onglet » (connexion Google, paiement) : ouvertes dans la même vue.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

/// Feuille « site de la plateforme » : connexion au compte, ou page de réservation déjà connectée.
struct ProviderWebSheet: View {
    var provider: BotProvider?
    var url: URL
    var title: String = ""
    var onClose: () -> Void = {}
    @StateObject private var model = WebPageModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AccountWebView(url: url, provider: provider, model: model)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.loading { ProgressView().progressViewStyle(.linear).tint(UI.court).frame(maxWidth: .infinity) }
                }
                .safeAreaInset(edge: .bottom) {
                    // Si la session du site n'est pas repérée automatiquement, le joueur peut le confirmer lui-même.
                    if let provider, !model.signedIn, !WebAccount.isConnected(provider) {
                        HStack(spacing: 12) {
                            Text("Connecté sur \(provider.name) ?").font(UI.callout()).foregroundStyle(UI.muted)
                            Spacer()
                            Button("Oui, c'est bon") {
                                WebAccount.setConnected(provider, true)
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(LinkButtonStyle())
                        }
                        .padding(.horizontal, UI.margin).padding(.vertical, 12)
                        .background(.bar)
                    }
                }
                .navigationTitle(title.isEmpty ? (provider?.name ?? model.title) : title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.canGoBack {
                            Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        if model.signedIn {
                            HStack(spacing: 6) {
                                Text(provider?.name ?? "").font(.system(size: 16, weight: .semibold))
                                Stamp(text: "Connecté")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Terminé") {
                            Task {
                                if let provider { await WebAccount.refresh(provider, webView: model.webView, seen: model.signedIn) }
                                onClose()
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .tint(UI.court)
    }
}

// MARK: - Choisir son club directement sur le site Playtomic

/// Le site Playtomic s'ouvre dans l'app (recherche, ou carte de leurs clubs) ; dès que le joueur ouvre la page d'un
/// club, l'app reconnaît le club (identifiant lu dans la page ou dans ses appels de disponibilités) et propose de le
/// choisir. C'est la voie la plus sûre : c'est leur propre site qui fait la recherche.
@MainActor
final class PlaytomicPickerModel: ObservableObject {
    @Published var club: PlaytomicClub? = nil
    @Published var loading = true
    weak var webView: WKWebView?
    private var probe: Task<Void, Never>?

    static let detectJS = #"""
    (function(){
      var m = location.pathname.match(/\/clubs\/([^\/?#]+)/);
      if (!m) return null;
      var slug = decodeURIComponent(m[1]);
      var id = null;
      try {
        var urls = performance.getEntriesByType('resource').map(function(e){ return e.name; });
        for (var i = 0; i < urls.length && !id; i++) {
          var t = urls[i].match(/tenant_id=([0-9a-fA-F-]{36})/);
          if (t) id = t[1];
        }
      } catch (e) {}
      var h = document.documentElement.innerHTML.replace(/\\"/g, '"');
      if (!id) {
        var k = h.indexOf('"slug":"' + slug + '"');
        if (k > 0) {
          var seg = h.substring(Math.max(0, k - 1500), k);
          var all = seg.match(/"(?:tenant_)?id":"[0-9a-fA-F-]{36}"/g);
          if (all && all.length) id = all[all.length - 1].match(/[0-9a-fA-F-]{36}/)[0];
        }
      }
      if (!id) {
        var t2 = h.match(/"tenant_id":"([0-9a-fA-F-]{36})"/);
        if (t2) id = t2[1];
      }
      var h1 = document.querySelector('h1');
      var name = (h1 && h1.innerText) || (document.title || '').split('|')[0].split(' - ')[0];
      return JSON.stringify({ id: id, slug: slug, name: (name || '').trim() });
    })()
    """#

    func pageChanged() {
        probe?.cancel()
        club = nil
        guard let webView, webView.url?.path.contains("/clubs/") == true else { return }
        // La page charge ses disponibilités juste après l'affichage : on regarde plusieurs fois.
        probe = Task { [weak self] in
            for _ in 0..<10 {
                guard let self, !Task.isCancelled, let webView = self.webView else { return }
                if let raw = try? await webView.evaluateJavaScript(Self.detectJS) as? String,
                   let o = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                   let id = o["id"] as? String, let slug = o["slug"] as? String {
                    let name = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
                    self.club = PlaytomicClub(id: id.lowercased(), name: name, slug: slug, countryCode: "", street: "", postalCode: "")
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

struct PlaytomicPickerWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: PlaytomicPickerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        model.webView = view
        // Le site change de page sans recharger (Next.js) : on suit l'adresse.
        let m = model
        context.coordinator.observation = view.observe(\.url, options: [.new]) { _, _ in
            Task { @MainActor in m.pageChanged() }
        }
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: PlaytomicPickerModel
        var observation: NSKeyValueObservation?

        init(model: PlaytomicPickerModel) { self.model = model }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { model.loading = true }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.loading = false
            model.pageChanged()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model.loading = false }
    }
}

struct PlaytomicPickerSheet: View {
    var query: String
    var onPick: (PlaytomicClub) -> Void
    @StateObject private var model = PlaytomicPickerModel()
    @Environment(\.dismiss) private var dismiss

    private var url: URL {
        var comps = URLComponents(string: "https://playtomic.com/search")!
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { comps.queryItems = [URLQueryItem(name: "q", value: q)] }
        return comps.url ?? PlaytomicWeb.site
    }

    var body: some View {
        NavigationStack {
            PlaytomicPickerWebView(url: url, model: model)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.loading { ProgressView().progressViewStyle(.linear).tint(UI.court).frame(maxWidth: .infinity) }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let club = model.club {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Eyebrow(text: "Club repéré")
                                    Text(club.name).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                                }
                                Spacer()
                                Button("Choisir") {
                                    onPick(club)
                                    dismiss()
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .frame(width: 120)
                            }
                        } else {
                            Text("Ouvre la page de ton club : l'app la reconnaît toute seule.")
                                .font(UI.callout()).foregroundStyle(UI.muted)
                        }
                    }
                    .padding(.horizontal, UI.margin).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
                .navigationTitle("Choisir sur Playtomic")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
                }
        }
        .tint(UI.court)
    }
}
