// GameView.swift — Hexfold
//
// La vue web plein écran du jeu : pas de zoom ni de rebond de page, pas de menu « copier » sur un appui long (le
// jeu en a besoin pour ses propres appuis longs), le son même avec le bouton silencieux.

import AVFoundation
import SwiftUI
import WebKit

struct GameView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        GameServer.shared.start()
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        // Pas de sélection de texte ni de loupe : les appuis longs sont pour le jeu.
        let css = "html,body{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;overscroll-behavior:none;" +
                  "touch-action:none;background:#000;margin:0;height:100%;overflow:hidden}"
        let js = "var s=document.createElement('style');s.textContent='\(css)';document.documentElement.appendChild(s);" +
                 "document.addEventListener('gesturestart',function(e){e.preventDefault()},{passive:false});"
        config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.isInspectable = true
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        // Le serveur démarre en un instant : on charge juste après.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { web.load(URLRequest(url: GameServer.shared.baseURL)) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var web: WKWebView?

        // Le serveur pas encore prêt (premier lancement) : on réessaie.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { webView.load(URLRequest(url: GameServer.shared.baseURL)) }
        }

        // iOS a fermé le moteur web (mémoire) : on relance le jeu (la partie enregistrée reste).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.load(URLRequest(url: GameServer.shared.baseURL))
        }

        // Les liens externes (wiki, Discord, GitHub) s'ouvrent dans Safari.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.host != "127.0.0.1", action.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
