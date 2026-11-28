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

// MARK: - Le site Playtomic dans un navigateur invisible (recherche et identification automatiques)

/// Le site Playtomic affiche ses résultats avec JavaScript, après le chargement : une simple requête n'y voit rien.
/// Ici, un vrai navigateur (WebKit, invisible, avec la session du joueur) charge la page comme Safari le ferait,
/// attend l'affichage, puis lit ce qui est à l'écran : les liens vers les pages des clubs. C'est la même navigation
/// qu'une personne, au même rythme, depuis son iPhone : aucune protection n'est contournée.
@MainActor
final class HiddenBrowser: NSObject, WKNavigationDelegate {
    static let shared = HiddenBrowser()
    private var webView: WKWebView?
    private var waiting: CheckedContinuation<Void, Never>?
    private var tail: Task<Void, Never>? = nil

    /// Une page à la fois, dans l'ordre des demandes (plusieurs clubs peuvent être cherchés à la suite).
    private func serial<T>(_ op: @escaping @MainActor () async -> T) async -> T {
        let previous = tail
        let task = Task { @MainActor () -> T in
            await previous?.value
            return await op()
        }
        tail = Task { @MainActor in _ = await task.value }
        return await task.value
    }

    /// Ce que la page affiche : un club par lien « /clubs/<slug> », avec le texte du lien (nom, ville).
    static let listJS = #"""
    (function(){
      var out = [], seen = {};
      var links = document.querySelectorAll('a[href*="/clubs/"]');
      for (var i = 0; i < links.length; i++) {
        var href = links[i].getAttribute('href') || '';
        var m = href.match(/\/clubs\/([^\/?#]+)/);
        if (!m) continue;
        var slug = decodeURIComponent(m[1]);
        if (seen[slug]) continue;
        seen[slug] = 1;
        var lines = (links[i].innerText || '').split('\n').map(function(s){ return s.trim(); }).filter(function(s){ return s.length > 1; });
        out.push({ slug: slug, name: lines[0] || '', detail: lines.slice(1, 3).join(' · ') });
      }
      return JSON.stringify(out.slice(0, 30));
    })()
    """#

    private func view() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        w.navigationDelegate = self
        w.alpha = 0.01
        w.isUserInteractionEnabled = false
        // Posé sous l'interface, invisible : une page attachée à l'écran s'affiche comme dans Safari (rendu complet).
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        window?.insertSubview(w, at: 0)
        webView = w
        return w
    }

    private func load(_ url: URL) async {
        let w = view()
        finished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiting = c
            w.load(URLRequest(url: url, timeoutInterval: 25))
            // Filet de sécurité : on n'attend jamais plus de 25 s.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finished()
            }
        }
    }

    private func finished() {
        waiting?.resume()
        waiting = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finished() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finished() }

    /// Recherche par le site : clubs affichés (slug, nom, ville). L'identifiant se lit ensuite sur la page du club.
    func search(_ text: String) async -> [PlaytomicClub] {
        await serial { await self.searchNow(text) }
    }

    private func searchNow(_ text: String) async -> [PlaytomicClub] {
        var comps = URLComponents(string: "https://playtomic.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: text)]
        guard let url = comps.url else { return [] }
        await load(url)
        // Les résultats arrivent après l'affichage : on regarde pendant une dizaine de secondes au plus.
        for _ in 0..<20 {
            if let w = webView {
                // 1) Données de la page (si les clubs y sont, avec leur identifiant).
                if let html = try? await w.evaluateJavaScript("document.documentElement.innerHTML") as? String {
                    let parsed = PlaytomicWeb.parseClubs(html)
                    if !parsed.isEmpty { return parsed }
                }
                // 2) Ce qui est affiché à l'écran.
                if let raw = try? await w.evaluateJavaScript(Self.listJS) as? String,
                   let rows = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: String]], !rows.isEmpty {
                    return rows.compactMap { r in
                        guard let slug = r["slug"], !slug.isEmpty else { return nil }
                        let name = (r["name"] ?? "").isEmpty ? slug.replacingOccurrences(of: "-", with: " ").capitalized : r["name"]!
                        return PlaytomicClub(id: "", name: name, slug: slug, countryCode: "", street: r["detail"] ?? "", postalCode: "")
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return []
    }

    /// Appel fait PAR la page elle-même (même origine, mêmes cookies, mêmes en-têtes qu'un navigateur) : c'est ainsi
    /// que le site lit ses propres créneaux. Sert quand une requête directe de l'app n'aboutit pas.
    func pageFetch(origin: URL, path: String) async -> (status: Int, body: String)? {
        await serial { await self.pageFetchNow(origin: origin, path: path) }
    }

    private func pageFetchNow(origin: URL, path: String) async -> (status: Int, body: String)? {
        if webView?.url?.host != origin.host { await load(origin) }
        guard let w = webView else { return nil }
        let js = "const r = await fetch(u, {credentials: 'include', headers: {'Accept': 'application/json'}}); return JSON.stringify({s: r.status, b: await r.text()});"
        guard let raw = try? await w.callAsyncJavaScript(js, arguments: ["u": path], contentWorld: .page) as? String,
              let o = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return nil }
        return ((o["s"] as? NSNumber)?.intValue ?? 0, o["b"] as? String ?? "")
    }

    enum PageSlots { case slots([(time: String, price: Double?, count: Int)]), none, captcha, failed(String) }

    /// Créneaux d'un club Anybuddy tels que sa page les affiche (boutons « 19:30, dès 36 €, 2 choix disponibles »).
    /// Si Anybuddy demande une vérification (captcha), on s'arrête : jamais de contournement.
    static let anybuddyJS = #"""
    (function(){
      var body = document.body ? document.body.innerText : '';
      if (document.querySelector('iframe[src*="captcha"], iframe[src*="turnstile"], iframe[src*="challenges"], iframe[src*="recaptcha"]')) {
        return JSON.stringify({ captcha: true });
      }
      var out = [], seen = {};
      var els = document.querySelectorAll('[aria-label]');
      for (var i = 0; i < els.length; i++) {
        var l = els[i].getAttribute('aria-label') || '';
        var m = l.match(/^(\d{1,2})[:h](\d{2})\s*,\s*d[èe]s\s*([0-9]+(?:[.,][0-9]+)?)/i);
        if (!m) continue;
        var t = (m[1].length < 2 ? '0' : '') + m[1] + ':' + m[2];
        if (seen[t]) continue;
        seen[t] = 1;
        var c = l.match(/(\d+)\s*choix/);
        out.push({ t: t, p: m[3].replace(',', '.'), c: c ? parseInt(c[1]) : 1 });
      }
      if (!out.length) {
        var bs = document.querySelectorAll('button, a, [role="button"]');
        for (var j = 0; j < bs.length; j++) {
          var tx = (bs[j].innerText || '').trim();
          var mm = tx.match(/^(\d{1,2})[:h](\d{2})\b[\s\S]{0,40}?(\d+(?:[.,]\d+)?)\s*€/);
          if (!mm) continue;
          var t2 = (mm[1].length < 2 ? '0' : '') + mm[1] + ':' + mm[2];
          if (seen[t2]) continue;
          seen[t2] = 1;
          out.push({ t: t2, p: mm[3].replace(',', '.'), c: 1 });
        }
      }
      var empty = /aucun (terrain|créneau)|plus de créneau|complet/i.test(body);
      return JSON.stringify({ slots: out, empty: empty, text: body.substring(0, 4000) });
    })()
    """#

    func anybuddySlots(slug: String, day: Date) async -> PageSlots {
        await serial { await self.anybuddySlotsNow(slug: slug, day: day) }
    }

    private func anybuddySlotsNow(slug: String, day: Date) async -> PageSlots {
        let dayKey = FR.string(day, "yyyy-MM-dd", tz: TimeZone(identifier: "Europe/Paris") ?? .current)
        guard let url = URL(string: "https://www.anybuddyapp.com/fr/club/\(slug)?date=\(dayKey)&activity=padel") else { return .failed("adresse") }
        await load(url)
        let isToday = Calendar.current.isDateInToday(day)
        let dayWords = [FR.string(day, "d MMMM"), FR.string(day, "d MMM"), FR.string(day, "EEEE d")].map { $0.lowercased() }
        for _ in 0..<24 {
            if let w = webView, let raw = try? await w.evaluateJavaScript(Self.anybuddyJS) as? String,
               let o = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
                if o["captcha"] as? Bool == true { return .captcha }
                let text = (o["text"] as? String ?? "").lowercased()
                // Pour un autre jour qu'aujourd'hui, on vérifie que la page affiche bien ce jour-là (sinon on ne dit rien).
                let rightDay = isToday || dayWords.contains { text.contains($0) }
                let rows = (o["slots"] as? [[String: Any]] ?? []).compactMap { r -> (time: String, price: Double?, count: Int)? in
                    guard let t = r["t"] as? String else { return nil }
                    return (t, (r["p"] as? String).flatMap { Double($0) }, (r["c"] as? NSNumber)?.intValue ?? 1)
                }
                if !rows.isEmpty { return rightDay ? .slots(rows) : .failed("jour non confirmé") }
                if o["empty"] as? Bool == true && rightDay { return .none }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return .failed("aucun créneau lisible sur la page")
    }

    /// Identifiant (tenant) d'un club : lu sur sa page, dans les appels de disponibilités qu'elle fait elle-même.
    func tenantID(slug: String) async -> String? {
        await serial { await self.tenantIDNow(slug: slug) }
    }

    private func tenantIDNow(slug: String) async -> String? {
        guard let url = URL(string: "https://playtomic.com/clubs/\(slug)") else { return nil }
        await load(url)
        for _ in 0..<16 {
            if let w = webView, let raw = try? await w.evaluateJavaScript(PlaytomicPickerModel.detectJS) as? String,
               let o = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], let id = o["id"] as? String {
                return id.lowercased()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }
}
