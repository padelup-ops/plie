import Combine
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
        // Le paiement des réservations se fait sur app.playtomic.com, qui a sa propre connexion : c'est là qu'on se connecte.
        case .playtomic: return URL(string: "https://app.playtomic.com/login")!
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
    let popups = PopupController()
}

// MARK: - Fenêtres ouvertes par la page (connexion Apple, Google, 3-D Secure)

/// Une fenêtre que la page ouvre (« Continuer avec Apple », vérification bancaire…) doit rester une VRAIE fenêtre
/// fille, reliée à la page qui l'a ouverte (window.opener) : c'est par là que la connexion revient. L'ouvrir à la place
/// de la page (comme avant) cassait la connexion : la page de connexion ne revenait jamais.
@MainActor
final class PopupController: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    struct Page: Identifiable {
        let id = UUID()
        let webView: WKWebView
    }

    @Published var page: Page?
    @Published var host = ""
    /// Pages ouvertes dans des fenêtres (pour le journal).
    private(set) var visited: [String] = []

    var onGoogle: Bool { host.contains("google.") }

    /// À rendre tel quel à WebKit depuis createWebViewWith : il y charge lui-même la page demandée.
    func open(with configuration: WKWebViewConfiguration) -> WKWebView {
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 760), configuration: configuration)
        w.uiDelegate = self
        w.navigationDelegate = self
        host = ""
        page = Page(webView: w)
        return w
    }

    func close() { page = nil }

    func webViewDidClose(_ webView: WKWebView) {
        if page?.webView === webView { page = nil }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        host = webView.url?.host ?? ""
        if let u = webView.url { visited.append((u.host ?? "") + u.path); if visited.count > 20 { visited.removeFirst() } }
    }

    /// Une fenêtre ouverte depuis la fenêtre : dans la même.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

private struct PopupWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// Présente les fenêtres de la page par-dessus, avec « Fermer ». Elles se referment seules une fois la connexion faite.
struct PopupWindows: ViewModifier {
    @ObservedObject var controller: PopupController

    func body(content: Content) -> some View {
        content.sheet(item: $controller.page) { page in
            NavigationStack {
                PopupWebView(webView: page.webView)
                    .ignoresSafeArea(edges: .bottom)
                    .safeAreaInset(edge: .top) {
                        if controller.onGoogle {
                            Text("Google refuse souvent sa connexion à l'intérieur d'une autre app. Si ça bloque, ferme cette fenêtre et choisis Apple ou ton e-mail.")
                                .font(UI.caption()).foregroundStyle(UI.ink)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(UI.raised)
                        }
                    }
                    .navigationTitle(controller.host)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { controller.close() }.fontWeight(.semibold)
                        }
                    }
            }
            .tint(UI.court)
        }
    }
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

        /// Fenêtres ouvertes par la page (connexion Apple ou Google, paiement) : de vraies fenêtres, par-dessus.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            model.popups.open(with: configuration)
        }
    }
}

/// Feuille « site de la plateforme » : connexion au compte, ou page déjà connectée.
/// (Les réservations passent par BookingFlowSheet, avec l'assistant.)
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
                .modifier(PopupWindows(controller: model.popups))
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

// MARK: - L'assistant de réservation (sur la page, avec le compte du joueur)

/// Fait à la place du joueur les gestes qu'il ferait sur la page Playtomic ou Anybuddy, et VÉRIFIE chaque étape.
///
/// 1. Playtomic, créneau exact connu : on ouvre directement la page de paiement de ce créneau (club, terrain, heure,
///    durée), comme le bouton « Réserver » du site. Rien à cliquer.
/// 2. Sinon (ou si ce lien ne mène pas au paiement) : la page du club. À chaque tour l'assistant regarde ce qui est à
///    l'écran (fenêtre ouverte ? heures ? terrains ? bouton pour avancer ?) et fait le geste suivant : ouvrir le bon
///    terrain, toucher l'heure, la durée, avancer. Un terrain sans l'heure voulue est refermé, on essaie le suivant.
/// Il S'ARRÊTE au paiement : jamais de clic sur « Payer » ni sur une page de paiement. C'est le joueur qui valide.
/// Chaque geste est noté dans un journal (sans mot de passe ni saisie) pour corriger si une page change.
@MainActor
final class BookingAssistant: ObservableObject {
    @Published var status = ""
    @Published var working = false
    @Published var done = false
    /// 0 page ouverte · 1 créneau · 2 durée · 3 étapes · 4 paiement atteint
    @Published var stage = 0
    @Published var reachedPayment = false
    @Published var needsLogin = false
    @Published var failed = false
    @Published var steps = ["J'ouvre la page du club", "Je touche ton créneau", "Je choisis la durée", "J'avance jusqu'au paiement"]
    private(set) var trace: [String] = []
    private var started = false
    private var task: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private weak var webView: WKWebView?
    private var t0 = Date()

    /// Outils communs : visibilité, texte d'un élément, page de paiement / connexion.
    static let commonJS = #"""
    function visible(el) {
      if (!el || !el.getBoundingClientRect) return false;
      var r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) return false;
      var st = window.getComputedStyle(el);
      return st.visibility !== 'hidden' && st.display !== 'none' && parseFloat(st.opacity || '1') > 0.05;
    }
    function label(el) {
      if (!el || !el.tagName) return '';
      if (el.tagName === 'INPUT') {
        var ty = (el.type || '').toLowerCase();
        return ((ty === 'submit' || ty === 'button') ? el.value : el.getAttribute('aria-label')) || '';
      }
      return (el.getAttribute('aria-label') || el.innerText || '').replace(/\s+/g, ' ').trim();
    }
    function buttonish(el) {
      if (!el || !el.tagName) return false;
      var role = el.getAttribute('role') || '';
      return el.tagName === 'BUTTON' || el.tagName === 'A' || el.tagName === 'INPUT' || role === 'button' || role === 'link';
    }
    // Le bouton qui paie ou confirme définitivement : jamais touché.
    function isFinalPay(t, el) {
      if (!buttonish(el) || !t || t.length > 70) return false;
      return /^(payer|pay|pagar)\b|^(valider|réserver|confirmer) et payer|^confirmer (la |ma )?réservation|^confirm (booking|reservation)|^place order|^finaliser/i.test(t)
        || (/\b(payer|pay now|pagar)\b/i.test(t) && /\d/.test(t));
    }
    function findPay(scope) {
      var els = (scope || document).querySelectorAll('button, a, input[type="submit"], [role="button"]');
      for (var i = 0; i < els.length; i++) { var e = els[i]; if (visible(e) && isFinalPay(label(e), e)) return e; }
      return null;
    }
    function topLayer() {
      var ds = document.querySelectorAll('[role="dialog"], [role="alertdialog"], [aria-modal="true"], dialog[open]');
      var best = null;
      for (var i = 0; i < ds.length; i++) if (visible(ds[i]) && label(ds[i]).length > 2) best = ds[i];
      return best;
    }
    function onPayPath() { return /(^|\/)(payments?|paiement|checkout|cart|panier|commande|order|summary|recap|booking-summary)(\/|$)/.test(location.pathname.toLowerCase()); }
    function pageState() {
      var text = document.body ? document.body.innerText.replace(/\s+/g, ' ') : '';
      var path = location.pathname.toLowerCase();
      var price = /\d+([.,]\d{1,2})?\s*(€|eur\b|chf|mad|dh\b|dzd|tnd)|€\s*\d+/i.test(text);
      var pw = document.querySelector('input[type="password"]');
      if ((pw && visible(pw)) || /(^|\/)(login|signin|sign-in|signup|register|auth|connexion|inscription)(\/|$)/.test(path)) return { state: 'login' };
      var iframe = document.querySelector('iframe[src*="stripe"], iframe[name^="__privateStripe"], iframe[src*="adyen"], iframe[src*="checkout"], iframe[src*="payment"], iframe[src*="mangopay"]');
      var btn = findPay(document);
      if (btn || (onPayPath() && (price || iframe)) || (iframe && price)) return { state: 'payment', label: btn ? label(btn).slice(0, 40) : '' };
      if (!price && /(n'est plus disponible|plus disponible|indisponible|not available|no longer available|introuvable|page not found|une erreur|something went wrong|expiré|expired)/i.test(text)) return { state: 'error' };
      if (text.length < 60 || onPayPath()) return { state: 'loading' };
      return { state: 'page' };
    }
    """#

    static let stateJS = commonJS + "\nreturn pageState();"

    /// Un tour : regarder la page, faire UN geste, dire lequel. Arguments : time, duration, resource, attempt.
    static let stepJS = commonJS + #"""
    var P = window.__padelup || (window.__padelup = { tried: {}, picked: '', pickedAt: -99, dur: false, row: false, rowAt: -99 });
    function seen(k) { return P.tried[k] || 0; }
    function bump(k) { P.tried[k] = seen(k) + 1; return P.tried[k]; }
    function mark(el) { try { el.scrollIntoView({ block: 'center' }); el.style.outline = '3px solid #D6F04A'; el.style.outlineOffset = '2px'; } catch (e) {} }
    function modal(el) { return el.getAttribute('role') === 'dialog' || el.getAttribute('aria-modal') === 'true' || el.tagName === 'DIALOG'; }
    function clickable(el) {
      var hops = 0;
      while (el && el !== document.body && hops < 8) {
        var role = el.getAttribute('role') || '';
        if (el.tagName === 'BUTTON' || el.tagName === 'A' || /^(button|option|radio|tab|link|menuitem|gridcell|checkbox)$/.test(role)
            || el.onclick || el.getAttribute('tabindex') === '0') return el;
        if (window.getComputedStyle(el).cursor === 'pointer') {
          // Le curseur « main » se transmet aux enfants : on remonte jusqu'à l'élément qui le porte vraiment.
          var top = el, up = el.parentElement, k = 0;
          while (up && up !== document.body && k < 6 && !modal(up) && window.getComputedStyle(up).cursor === 'pointer') {
            top = up;
            if (up.tagName === 'BUTTON' || up.tagName === 'A' || /^(button|option|radio|tab|link)$/.test(up.getAttribute('role') || '')) break;
            up = up.parentElement; k++;
          }
          return top;
        }
        el = el.parentElement; hops++;
      }
      return null;
    }
    // Un vrai toucher : certains sites réagissent à l'appui (pointerdown), d'autres au clic. Au 2e essai, les deux.
    function press(el, hard) {
      mark(el);
      if (hard) {
        var r = el.getBoundingClientRect();
        var o = { bubbles: true, cancelable: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, pointerId: 1, isPrimary: true, pointerType: 'touch' };
        try { el.dispatchEvent(new PointerEvent('pointerdown', o)); } catch (e) {}
        try { el.dispatchEvent(new MouseEvent('mousedown', o)); } catch (e) {}
        try { el.dispatchEvent(new PointerEvent('pointerup', o)); } catch (e) {}
        try { el.dispatchEvent(new MouseEvent('mouseup', o)); } catch (e) {}
      }
      el.click();
    }
    function selectedish(el) {
      for (var i = 0, x = el; i < 3 && x && x.getAttribute; i++, x = x.parentElement) {
        if (x.getAttribute('aria-selected') === 'true' || x.getAttribute('aria-pressed') === 'true' || x.getAttribute('aria-checked') === 'true'
            || x.getAttribute('data-state') === 'checked' || x.getAttribute('data-selected') === 'true') return true;
      }
      return false;
    }
    function off(el) { return el.disabled || el.getAttribute('aria-disabled') === 'true'; }
    function minutes(h, m) { return parseInt(h, 10) * 60 + parseInt(m, 10); }
    // La première heure du jour dans un texte (« 19:30 », « 19h30 »), pas une durée (« 1h30 »).
    function firstTime(t) {
      var m = t.match(/(\d{1,2}):(\d{2})|(?:^|\D)([5-9]|1\d|2[0-3])\s*h\s*(\d{2})/);
      if (!m) return null;
      return m[1] ? minutes(m[1], m[2]) : minutes(m[3], m[4]);
    }
    function out(state, did, note) { return { state: state, did: did || '', note: note || '' }; }

    var tp = time.split(':'), H = parseInt(tp[0], 10), M = tp[1], target = minutes(tp[0], tp[1]);
    var reStart = new RegExp('^\\D{0,3}0?' + H + '\\s*[:hH]\\s*' + M + '(?!\\d)');
    var reAny = new RegExp('(^|\\D)0?' + H + '\\s*[:hH]\\s*' + M + '(?!\\d)');
    var reDur = null;
    if (duration) {
      var dh = Math.floor(duration / 60), dm = duration % 60;
      reDur = new RegExp('(^|\\D)(' + duration + '\\s*min|' + (dm === 0 ? (dh + '\\s*h(?!\\s*\\d)|' + dh + '\\s*heures?') : (dh + '\\s*h\\s*' + dm + '|' + dh + ':' + dm + '\\s*h')) + ')', 'i');
    }
    var NOT_SLOT = /(\d+\s*options?\b|partir de|jusqu|ouvert|horaires|opening|fermé)/i;
    var SEL = 'button, a, input[type="submit"], input[type="button"], [role="button"], [role="option"], [role="radio"], [role="tab"], [role="link"], [role="gridcell"], [role="menuitem"], label, li, [tabindex]';

    // 0) Bandeau cookies.
    var sels = ['#didomi-notice-agree-button', '#axeptio_btn_acceptAll', '#onetrust-accept-btn-handler', '[data-testid="uc-accept-all-button"]', '#tarteaucitronPersonalize2'];
    for (var k = 0; k < sels.length; k++) {
      var cb = document.querySelector(sels[k]);
      if (cb && visible(cb) && bump('consent' + k) < 3) { cb.click(); return out('act', 'consent', 'cookies acceptés'); }
    }
    var cbs = document.querySelectorAll('button, [role="button"]');
    for (var q = 0; q < cbs.length; q++) {
      var ct = label(cbs[q]);
      if (/^(tout accepter|accepter tout|accepter et fermer|accept all|j'accepte|ok, j'accepte|autoriser tous les cookies)$/i.test(ct) && visible(cbs[q]) && bump('consent:' + ct) < 3) {
        cbs[q].click(); return out('act', 'consent', 'cookies : ' + ct);
      }
    }

    // 1) Arrivé ? Paiement ou connexion : on s'arrête là.
    var ps = pageState();
    if (ps.state === 'payment') { var pb = findPay(document); if (pb) mark(pb); return out('payment', '', ps.label || ''); }
    if (ps.state === 'login') return out('login', '', 'connexion demandée');
    if (onPayPath()) return out('idle', '', 'page de paiement en chargement');

    var dlg = topLayer();
    var root = dlg || document.body;

    // Nom du terrain voulu (lu dans les données de la page à partir de son identifiant), s'il est connu.
    if (P.court === undefined) {
      P.court = '';
      if (resource) {
        var html = document.documentElement.innerHTML.replace(/\\"/g, '"');
        var at = html.indexOf(resource);
        while (at >= 0 && !P.court) {
          var aft = html.slice(at, at + 900).match(/"name"\s*:\s*"([^"]{2,80})"/);
          if (aft) P.court = aft[1];
          at = html.indexOf(resource, at + 1);
        }
      }
    }
    var court = P.court || '';

    // 2) Les heures à l'écran (dans la fenêtre ouverte s'il y en a une).
    function slotCands() {
      var els = root.querySelectorAll(SEL + ', div, span, p, time');
      var got = [], res = [];
      for (var i = 0; i < els.length; i++) {
        var e = els[i];
        var al = e.getAttribute('aria-label') || '', raw = e.textContent || '';
        if (!((al && reAny.test(al)) || (raw.length <= 200 && reAny.test(raw)))) continue;
        if (!visible(e)) continue;
        var t = label(e);
        if (!t || t.length > 90 || !reAny.test(t) || NOT_SLOT.test(t)) continue;
        var c = clickable(e);
        if (!c || got.indexOf(c) >= 0) continue;
        got.push(c);
        var ctl = label(c);
        if (ctl.length > 140 || NOT_SLOT.test(ctl) || isFinalPay(ctl, c) || off(c)) continue;
        var score = 0;
        if (reStart.test(ctl) || reStart.test(t)) score += 3;
        var first = firstTime(ctl);
        if (first !== null && first !== target) score -= 6;   // « 18:00 - 19:30 » : finit à l'heure voulue
        if (reDur && reDur.test(ctl)) score += 3;
        if (court && ctl.indexOf(court) >= 0) score += 2;
        if (dlg) score += 1;
        if (/disabled|unavailable|indisponible|complet/i.test(String(c.className) + ' ' + ctl)) score -= 8;
        res.push({ el: c, t: ctl, score: score, sel: selectedish(c) });
      }
      res.sort(function (a, b) { return b.score - a.score || a.t.length - b.t.length; });
      return res;
    }
    function findShort(re, maxLen) {
      var els = root.querySelectorAll(SEL + ', div, span');
      var best = null, bl = 1e9;
      for (var i = 0; i < els.length; i++) {
        var e = els[i], raw = e.textContent || '';
        if (raw.length > 120 && !(e.getAttribute('aria-label') || '')) continue;
        var t = label(e);
        if (!t || t.length > maxLen || !re.test(t) || NOT_SLOT.test(t) || !visible(e)) continue;
        var ft = firstTime(t);
        if (ft !== null && ft !== target) continue;   // la durée d'un AUTRE créneau
        var c = clickable(e);
        if (!c || off(c) || isFinalPay(label(c), c) || selectedish(c)) continue;
        if (t.length < bl) { best = c; bl = t.length; }
      }
      return best;
    }
    // Le bouton qui fait avancer vers le paiement (jamais celui qui paie, jamais un lien vers une autre partie du site).
    function findCTA() {
      var els = root.querySelectorAll('button, a, [role="button"], input[type="submit"]');
      var best = null, bs = -1e9;
      for (var i = 0; i < els.length; i++) {
        var e = els[i];
        if (!visible(e) || off(e)) continue;
        var t = label(e);
        if (!t || t.length > 60 || isFinalPay(t, e)) continue;
        if (!/^(réserver|reserver|continuer|suivant|book|reserve|continue|next|choisir|sélectionner|select)\b/i.test(t)) continue;
        if (e.tagName === 'A') {
          var href = e.getAttribute('href') || '';
          if (href && href !== '#' && !/(payment|paiement|checkout|book|reserv|cart|panier)/i.test(href)) continue;
        }
        var n = seen('cta:' + t);
        if (n >= 3) continue;
        var s = (dlg && dlg.contains(e) ? 5 : 0) + (/\d/.test(t) ? 2 : 0) - n * 4;
        if (s > bs) { best = e; bs = s; }
      }
      return best;
    }

    var cands = slotCands();
    var isSel = cands.some(function (c) { return c.sel; });
    var waited = attempt - P.pickedAt;

    // 3) Heure déjà choisie : la durée, puis le bouton pour avancer.
    if (P.picked || isSel) {
      if (reDur && !P.dur) {
        var d = findShort(reDur, 60);
        if (d) { P.dur = true; press(d, false); return out('act', 'duration', 'durée : ' + label(d).slice(0, 40)); }
      }
      var go = findCTA();
      if (go) { var gn = bump('cta:' + label(go)); press(go, gn > 1); return out('act', 'next', 'bouton : ' + label(go).slice(0, 40)); }
      if (waited < 5) return out('idle', '', '');
    }

    // 4) Toucher l'heure.
    var fresh = cands.filter(function (c) {
      return c.score >= 0 && !c.sel && seen('t:' + c.t) < 2 && (c.t !== P.picked || waited >= 5);
    });
    if (fresh.length) {
      var c = fresh[0];
      var tn = bump('t:' + c.t);
      press(c.el, tn > 1);
      P.picked = c.t; P.pickedAt = attempt; P.dur = !!(reDur && reDur.test(c.t));
      return out('act', 'time', 'heure : ' + c.t.slice(0, 50));
    }

    function closeLayer(d) {
      var xs = d.querySelectorAll('button, [role="button"]'), x = null;
      for (var j = 0; j < xs.length; j++) {
        var xl = (xs[j].getAttribute('aria-label') || xs[j].innerText || '').trim();
        if (/^(fermer|close|retour|back|annuler|cancel|plus tard|non merci|×|✕)$/i.test(xl) && visible(xs[j])) { x = xs[j]; break; }
      }
      if (x) x.click(); else document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
    }
    // 5) Fenêtre d'un terrain ouverte sans l'heure voulue : la refermer pour essayer le suivant.
    if (dlg && P.row && attempt - P.rowAt >= 6) {
      P.row = false;
      if (P.rowKey) P.tried[P.rowKey] = 9;
      closeLayer(dlg);
      return out('act', 'close', 'ce terrain n\'a pas ' + time);
    }
    if (dlg && P.row) return out('idle', '', '');
    // Une fenêtre qui n'est pas celle d'un terrain (publicité, « télécharge l'app ») : la fermer.
    if (dlg && !P.row && seen('popup') < 2) { bump('popup'); closeLayer(dlg); return out('act', 'close', 'fenêtre fermée'); }

    // 6) Playtomic liste d'abord les terrains (« 12 options · À partir de 04:30 jusqu'à 21:00 ») : ouvrir le bon.
    var rows = document.querySelectorAll('button, a, [role="button"], li, div');
    var best = null, bscore = -1e9, bkey = '', keys = {};
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i], rraw = r.textContent || '';
      if (rraw.length > 400 || !/\d+\s*options?/i.test(rraw) || !visible(r)) continue;
      if ((rraw.match(/\d+\s*options?/gi) || []).length > 1) continue;   // la liste entière, pas une ligne
      var cl = clickable(r), cr = cl || r;
      var rt = label(cr);
      if (rt.length > 300 || !/\d+\s*options?/i.test(rt)) continue;
      // Clé stable : le nom et la plage horaire (le texte change quand la ligne se déplie).
      var head = rt.match(/^.*?\d+\s*options?.*?\d{1,2}[:h]\d{2}\D+?\d{1,2}[:h]\d{2}/i);
      var key = 'row:' + (head ? head[0] : rt).slice(0, 120);
      keys[key] = 1;
      var rn = seen(key);
      if (rn >= 2) continue;
      var rr = rt.match(/(\d{1,2})[:h](\d{2})\D+?(\d{1,2})[:h](\d{2})/);
      var covers = rr ? (minutes(rr[1], rr[2]) <= target && target <= minutes(rr[3], rr[4])) : true;
      var sc = (covers ? 10 : 0) + (court && rt.indexOf(court) >= 0 ? 20 : 0) + (cl ? 0 : -5) - rn * 15 - rt.length / 1000;
      if (sc > bscore) { best = cr; bscore = sc; bkey = key; }
    }
    if (best) {
      var bn = bump(bkey);
      P.row = true; P.rowAt = attempt; P.rowKey = bkey;
      press(best, bn > 1);
      return out('act', 'row', 'terrain : ' + label(best).slice(0, 60));
    }

    // Tous les terrains ouverts, l'heure n'y est pas : elle vient sans doute d'être prise.
    var nrows = Object.keys(keys).length;
    if (nrows > 0 && !cands.length) return out('missing', '', time + ' introuvable sur les ' + nrows + ' terrain(s)');

    // 7) Rien de tout ça : un bouton « Réserver » ou « Voir les créneaux » de temps en temps, sinon descendre.
    if (attempt === 6 || attempt === 18) {
      var els2 = document.querySelectorAll('button, [role="button"], a');
      for (var z = 0; z < els2.length; z++) {
        var zt = label(els2[z]);
        if (/^(réserver|reserver|book|voir les créneaux|disponibilités)/i.test(zt) && zt.length < 40 && visible(els2[z]) && !isFinalPay(zt, els2[z])
            && !(els2[z].tagName === 'A' && /^\/(search|clubs\/?$)/.test(els2[z].getAttribute('href') || ''))) {
          press(els2[z], false); return out('act', 'cta', 'bouton : ' + zt);
        }
      }
    }
    window.scrollBy(0, 500);
    return out('idle', 'scroll', cands.length ? (cands.length + ' heure(s) vues, aucune utilisable') : '');
    """#

    /// Ce que voit l'assistant quand il coince (pour le journal) : éléments touchables, sans les saisies.
    static let snapshotJS = commonJS + #"""
    var dlg = topLayer(), root = dlg || document.body, lines = [];
    lines.push('URL ' + location.host + location.pathname + (dlg ? ' · fenêtre ouverte' : ''));
    var els = root.querySelectorAll('button, a, [role], label, li, [tabindex]');
    for (var i = 0; i < els.length && lines.length < 70; i++) {
      var e = els[i];
      if (!visible(e)) continue;
      var t = label(e).replace(/\S+@\S+/g, '<e-mail>').replace(/\d{6,}/g, '<n>').slice(0, 80);
      if (!t) continue;
      var role = e.getAttribute('role');
      lines.push(e.tagName.toLowerCase() + (role ? '[' + role + ']' : '') + (window.getComputedStyle(e).cursor === 'pointer' ? '*' : '') + ' ' + t);
    }
    return lines.join('\n');
    """#

    // MARK: Déroulé

    func run(target: BookingTarget?, clubURL: URL, payURL: URL?, in webView: WKWebView) {
        guard !started else { return }
        started = true
        self.webView = webView
        t0 = Date()
        working = true
        task = Task { [weak self] in
            guard let self else { return }
            if let payURL, target != nil {
                self.steps = ["J'ouvre ta page de paiement", "Je vérifie ton créneau", "Je prépare le paiement", "Paiement prêt"]
                self.status = "J'ouvre ta page de paiement…"
                self.log("lien direct : " + (payURL.host ?? "") + payURL.path)
                await self.load(payURL)
                self.stage = 1
                let (state, label) = await self.waitState(seconds: 15)
                self.log("lien direct → " + state)
                if Task.isCancelled { return }
                if state == "payment" { self.paid(label); return }
                if state == "login" { self.loginNeeded(reload: payURL); return }
                self.steps = ["J'ouvre la page du club", "Je touche ton créneau", "Je choisis la durée", "J'avance jusqu'au paiement"]
                self.stage = 0
                self.status = "Je passe par la page du club…"
            }
            await self.load(clubURL)
            if Task.isCancelled { return }
            self.stage = 1
            guard let target else { self.finish("", done: false); return }
            await self.walk(target)
        }
    }

    private func walk(_ target: BookingTarget) async {
        status = "Je cherche \(target.time) sur la page…"
        let end = Date().addingTimeInterval(40)
        var attempt = 0
        while Date() < end, !Task.isCancelled {
            attempt += 1
            let r = await js(Self.stepJS, ["time": target.time, "duration": target.duration ?? 0,
                                           "resource": target.direct?.resourceID ?? "", "attempt": attempt])
            let state = r["state"] as? String ?? ""
            let did = r["did"] as? String ?? ""
            let note = r["note"] as? String ?? ""
            if !note.isEmpty { log((did.isEmpty ? state : did) + " · " + note) }
            if state == "payment" { paid(note); return }
            if state == "login" { loginNeeded(reload: nil); return }
            if state == "missing" {
                log(await snapshot())
                failed = true
                finish("\(target.time) n'apparaît plus sur la page : il vient sans doute d'être pris. Choisis un autre créneau ici.", done: false)
                return
            }
            switch did {
            case "row": status = "J'ouvre le terrain…"
            case "close": status = note.hasPrefix("fenêtre") ? "Je ferme une fenêtre…" : "Pas \(target.time) sur ce terrain, j'essaie le suivant…"
            case "time": stage = max(stage, 2); status = "Je touche \(target.time)…"
            case "duration": stage = max(stage, 3); status = "Je choisis \(target.duration ?? 0) min…"
            case "next": stage = max(stage, 3); status = "J'avance vers le paiement…"
            default: break
            }
            let acted = !did.isEmpty && did != "scroll"
            try? await Task.sleep(nanoseconds: acted ? 750_000_000 : 350_000_000)
        }
        guard !Task.isCancelled else { return }
        log(await snapshot())
        failed = true
        finish("Je n'arrive pas au paiement tout seul : termine ici. Le journal est prêt (bouton ci-contre).", done: false)
    }

    // MARK: Outils

    private func js(_ source: String, _ args: [String: Any] = [:]) async -> [String: Any] {
        guard let webView else { return [:] }
        return ((try? await webView.callAsyncJavaScript(source, arguments: args, contentWorld: .page)) as? [String: Any]) ?? [:]
    }

    private func load(_ url: URL) async {
        guard let webView else { return }
        webView.load(URLRequest(url: url))
        try? await Task.sleep(nanoseconds: 300_000_000)
        let end = Date().addingTimeInterval(20)
        while webView.isLoading, Date() < end, !Task.isCancelled { try? await Task.sleep(nanoseconds: 150_000_000) }
    }

    private func pageState() async -> (String, String) {
        let r = await js(Self.stateJS)
        return ((r["state"] as? String) ?? "loading", (r["label"] as? String) ?? "")
    }

    /// Attend que la page se décide : paiement, connexion, erreur, ou une page ordinaire stable 5 s.
    private func waitState(seconds: Double) async -> (String, String) {
        let end = Date().addingTimeInterval(seconds)
        var last = ("loading", ""), errors = 0
        var pageSince: Date? = nil
        while Date() < end, !Task.isCancelled {
            last = await pageState()
            switch last.0 {
            case "payment", "login": return last
            case "error": errors += 1; if errors >= 3 { return last }
            case "page":
                if pageSince == nil { pageSince = Date() }
                if let s = pageSince, Date().timeIntervalSince(s) > 5 { return last }
            default: pageSince = nil
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return last
    }

    private func snapshot() async -> String {
        guard let webView else { return "" }
        return ((try? await webView.callAsyncJavaScript(Self.snapshotJS, arguments: [:], contentWorld: .page)) as? String) ?? ""
    }

    private func log(_ line: String) {
        trace.append(String(format: "%.1fs ", Date().timeIntervalSince(t0)) + line)
        if trace.count > 200 { trace.removeFirst() }
    }

    private func paid(_ label: String) {
        stage = 4
        reachedPayment = true
        needsLogin = false
        failed = false
        finish("Tout est prêt : vérifie puis touche « \(label.isEmpty ? "Payer" : label) ».", done: true)
    }

    /// La plateforme demande de se connecter : la page s'affiche. Une fois connecté, on revient au paiement du créneau.
    private func loginNeeded(reload: URL?) {
        needsLogin = true
        stage = max(stage, 1)
        log("connexion demandée")
        finish("Connecte-toi une fois ici (Apple ou e-mail) : ensuite j'arrive direct au paiement.", done: false)
        watcher?.cancel()
        watcher = Task { [weak self] in
            var reloads = 0
            for _ in 0..<600 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, let wv = self.webView else { return }
                if wv.isLoading { continue }
                let (state, label) = await self.pageState()
                if state == "payment" { self.paid(label); return }
                if state == "page", let reload, reloads < 2, let p = WebAccount.owns(reload),
                   await WebAccount.detect(p, in: wv) {
                    reloads += 1
                    self.log("connecté → retour au paiement")
                    self.status = "Connecté ! J'ouvre ta page de paiement…"
                    await self.load(reload)
                }
            }
        }
    }

    private func finish(_ text: String, done: Bool) {
        status = text
        self.done = done
        working = false
    }

    func stop(_ reason: String = "Je te laisse la main : termine ici.") {
        task?.cancel()
        if working { finish(reason, done: false) }
    }

    func cancelAll() {
        task?.cancel()
        watcher?.cancel()
        working = false
    }
}

// MARK: - Réservation préparée en coulisses, page de paiement directement

/// Journal technique : les appels que fait la page (méthode, chemin, noms des paramètres, sans leurs valeurs) et les
/// pages visitées. Aucun mot de passe, aucun contenu. Sert à amener l'app directement au paiement.
enum NetRecorder {
    static let script = #"""
    (function(){
      if (window.__padelupNet) return;
      window.__padelupNet = [];
      function clean(u) {
        try {
          var x = new URL(u, location.href);
          if (!/playtomic|anybuddy/.test(x.host)) return null;
          var keys = []; x.searchParams.forEach(function(v, k){ keys.push(k); });
          return x.host + x.pathname + (keys.length ? '?' + keys.join('&') : '');
        } catch (e) { return null; }
      }
      function add(m, u, s) { var c = clean(u); if (!c) return; var l = window.__padelupNet; l.push(m + ' ' + c + (s ? ' → ' + s : '')); if (l.length > 300) l.shift(); }
      var f = window.fetch;
      if (f) window.fetch = function(input, init) {
        var u = typeof input === 'string' ? input : (input && input.url) || '';
        var m = (init && init.method) || (input && input.method) || 'GET';
        return f.apply(this, arguments).then(function(r){ add(m.toUpperCase(), u, r.status); return r; });
      };
      var o = XMLHttpRequest.prototype.open, sd = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m, u) { this.__p = [m, u]; return o.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function() { var x = this; x.addEventListener('loadend', function(){ if (x.__p) add(String(x.__p[0]).toUpperCase(), x.__p[1], x.status); }); return sd.apply(this, arguments); };
      add('PAGE', location.href, '');
    })();
    """#

    static func install(in config: WKWebViewConfiguration) {
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    @MainActor
    static func dump(_ webView: WKWebView) async -> String {
        let lines = (try? await webView.evaluateJavaScript("(window.__padelupNet || []).join('\\n')") as? String) ?? ""
        return "Page : " + (webView.url.map { ($0.host ?? "") + $0.path } ?? "?") + "\n" + lines
    }
}

/// Un navigateur invisible ouvre la réservation avec la session du joueur (page de paiement directe, ou page du club
/// parcourue par l'assistant). Quand il atteint le paiement, CE MÊME navigateur s'affiche : le joueur arrive
/// directement sur la page de paiement. S'il coince, la page s'affiche là où il en est.
@MainActor
final class BookingPreparer: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let assistant = BookingAssistant()
    let popups = PopupController()
    let target: BookingTarget?
    @Published var showPage = false
    private var timeout: Task<Void, Never>?

    /// Pages visitées pendant la préparation (le journal de la page repart à zéro à chaque nouvelle page).
    private(set) var visited: [String] = []

    init(request: BookingRequest) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        NetRecorder.install(in: config)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        target = request.target
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // En coulisses : posé sous l'interface, invisible, pour un rendu complet comme dans Safari.
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        window?.insertSubview(webView, at: 0)
        if let target {
            let pay = WebAccount.owns(request.url) == .playtomic ? target.direct.map(PlaytomicWeb.paymentURL) : nil
            assistant.run(target: target, clubURL: request.url, payURL: pay, in: webView)
        } else {
            webView.load(URLRequest(url: request.url))
            showPage = true
        }
        // Filet de sécurité : on montre la page quoi qu'il arrive.
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 75_000_000_000)
            self?.reveal(reason: "Je n'ai pas trouvé la suite à temps : termine ici, la page est prête.")
        }
    }

    func reveal(reason: String = "Je te laisse la main : termine ici.") {
        timeout?.cancel()
        assistant.stop(reason)
        withAnimation(.snappy(duration: 0.35)) { showPage = true }
    }

    func cancel() {
        timeout?.cancel()
        assistant.cancelAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    /// Le journal à coller pour corriger : pages, gestes de l'assistant, ce qu'il voyait, appels de la page.
    func journal() async -> String {
        let net = await NetRecorder.dump(webView)
        return "PadelUp · journal de réservation\nPages : " + visited.joined(separator: " > ")
            + (popups.visited.isEmpty ? "" : "\nFenêtres : " + popups.visited.joined(separator: " > "))
            + "\n\nAssistant :\n" + assistant.trace.joined(separator: "\n") + "\n\n" + net
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let u = webView.url { visited.append((u.host ?? "") + u.path); if visited.count > 30 { visited.removeFirst() } }
    }

    /// Fenêtres ouvertes par la page (connexion Apple ou Google, 3-D Secure) : de vraies fenêtres, par-dessus.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        popups.open(with: configuration)
    }
}

/// Affiche un navigateur déjà existant (celui qui a préparé la réservation).
struct ExistingWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        webView.removeFromSuperview()
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// La feuille « Réserver » : préparation en coulisses, puis directement la page de paiement.
struct BookingFlowSheet: View {
    let request: BookingRequest
    @StateObject private var preparer: BookingPreparer
    @Environment(\.dismiss) private var dismiss

    init(request: BookingRequest) {
        self.request = request
        _preparer = StateObject(wrappedValue: BookingPreparer(request: request))
    }

    var body: some View {
        NavigationStack {
            Group {
                if preparer.showPage {
                    ExistingWebView(webView: preparer.webView)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .top) { PaymentBanner(assistant: preparer.assistant, copyJournal: copyJournal) }
                } else {
                    PreparingView(assistant: preparer.assistant, request: request) { preparer.reveal() }
                }
            }
            .modifier(PopupWindows(controller: preparer.popups))
            .navigationTitle(preparer.showPage ? (WebAccount.owns(request.url)?.name ?? "Réservation") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if preparer.showPage {
                        HStack(spacing: 4) {
                            Button { preparer.webView.goBack() } label: { Image(systemName: "chevron.left") }
                            Menu {
                                Button { copyJournal() } label: { Label("Copier le journal technique", systemImage: "doc.on.doc") }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(preparer.showPage ? "Terminé" : "Annuler") {
                        if let p = WebAccount.owns(request.url) { Task { await WebAccount.refresh(p, webView: preparer.webView) } }
                        preparer.cancel()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(UI.court)
        .onDisappear { preparer.cancel() }
        .onReceive(preparer.assistant.$working.dropFirst()) { working in
            // L'assistant a fini (paiement atteint, ou il a besoin de toi) : la page apparaît.
            if !working && preparer.assistant.stage > 0 { preparer.reveal() }
        }
    }

    private func copyJournal() {
        Task { UIPasteboard.general.string = await preparer.journal() }
    }
}

/// Pendant la préparation : le billet du créneau et les étapes qui se cochent.
struct PreparingView: View {
    @ObservedObject var assistant: BookingAssistant
    let request: BookingRequest
    var showNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "En coulisses · " + (WebAccount.owns(request.url)?.name ?? "réservation"))
                Text("Je prépare ta réservation.").font(UI.display(30)).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let t = request.target {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(t.time).font(UI.scoreHeavy(72)).foregroundStyle(UI.ink)
                    if let d = t.duration { Text("\(d) min").font(UI.title(20)).foregroundStyle(UI.muted) }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(assistant.steps.indices, id: \.self) { i in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(i < assistant.stage ? UI.ball : (i == assistant.stage ? UI.raised : Color.clear))
                            Circle().strokeBorder(i < assistant.stage ? UI.onBall.opacity(0.3) : UI.rule, lineWidth: 1)
                            if i < assistant.stage {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(UI.onBall)
                            } else if i == assistant.stage {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(width: 30, height: 30)
                        Text(assistant.steps[i]).font(.system(size: 17, weight: i == assistant.stage ? .semibold : .regular))
                            .foregroundStyle(i <= assistant.stage ? UI.ink : UI.faint)
                    }
                    .animation(.snappy, value: assistant.stage)
                }
            }
            if !assistant.status.isEmpty {
                Text(assistant.status).font(UI.caption()).foregroundStyle(UI.muted).contentTransition(.opacity)
            }
            Spacer()
            Text("Rien n'est payé sans toi : je m'arrête au paiement et tu confirmes.").font(UI.caption()).foregroundStyle(UI.muted)
            Button("Voir la page maintenant", action: showNow).buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, UI.margin)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PageBackground(seasonal: false))
    }
}

/// Le bandeau au-dessus de la page révélée : « tout est prêt, paie », « connecte-toi », ou « à toi de finir ».
struct PaymentBanner: View {
    @ObservedObject var assistant: BookingAssistant
    var copyJournal: () -> Void
    @State private var copied = false

    init(assistant: BookingAssistant, copyJournal: @escaping () -> Void = {}) {
        self.assistant = assistant
        self.copyJournal = copyJournal
    }

    var body: some View {
        Group {
            if !assistant.status.isEmpty { banner }
        }
        .sensoryFeedback(.success, trigger: assistant.reachedPayment)
    }

    private var icon: String {
        if assistant.reachedPayment { return "creditcard.fill" }
        if assistant.needsLogin { return "person.crop.circle.badge.checkmark" }
        return "hand.point.up.left.fill"
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(assistant.reachedPayment ? UI.onBall : UI.ink)
            Text(assistant.reachedPayment ? "C'est prêt : vérifie et paie." : assistant.status)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(assistant.reachedPayment ? UI.onBall : UI.ink)
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            if assistant.failed && !assistant.reachedPayment {
                Button {
                    copyJournal()
                    copied = true
                } label: {
                    Text(copied ? "Copié" : "Journal").font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(UI.court)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(assistant.reachedPayment ? UI.ball : UI.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 12).padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
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
