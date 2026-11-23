// Media.swift — Twinfold
//
// Video and sound in each pane: a small script, in every frame of every page, tells Twinfold when something plays,
// mutes or unmutes the pane on request (iframes included), and can stretch the playing video over the whole pane.

import SwiftUI
import WebKit

enum MediaScript {
    static let handlerName = "twinfoldMedia"

    static let source = #"""
    (function () {
      if (window.__twinfold) return;
      var tf = window.__twinfold = { muted: false, filled: null };
      function post(msg) { try { window.webkit.messageHandlers.twinfoldMedia.postMessage(msg); } catch (e) {} }
      function media() { return Array.prototype.slice.call(document.querySelectorAll('video,audio')); }
      function report() {
        var ms = media();
        var playing = ms.some(function (m) { return !m.paused && !m.ended; });
        var video = ms.some(function (m) { return m.tagName === 'VIDEO' && !m.paused && !m.ended; });
        post({ kind: 'state', playing: playing, video: video, top: window === window.top });
      }
      ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange'].forEach(function (ev) {
        document.addEventListener(ev, function (e) {
          var t = e.target;
          if (ev === 'pause' && t && t.tagName === 'VIDEO') { tf.lastPaused = t; }
          if (tf.muted && t && t.muted === false && (ev === 'play' || ev === 'playing')) t.muted = true;
          report();
        }, true);
      });
      function setMuted(v) {
        tf.muted = v;
        media().forEach(function (m) { m.muted = v; });
        for (var i = 0; i < window.frames.length; i++) {
          try { window.frames[i].postMessage({ __twinfoldMute: v }, '*'); } catch (e) {}
        }
      }
      tf.setMuted = setMuted;
      // iOS lets only one video with sound play at a time: the video stopped by the other pane starts again, muted.
      tf.resumeMuted = function () {
        var v = tf.lastPaused;
        if (!v || !v.isConnected) return false;
        setMuted(true);
        v.muted = true;
        var p = v.play();
        if (p && p.catch) p.catch(function () {});
        return true;
      };
      window.addEventListener('message', function (e) {
        if (e.data && typeof e.data.__twinfoldMute === 'boolean') setMuted(e.data.__twinfoldMute);
      });
      // Le cadre visible de la page (pas 100vh, qui déborde sous la barre d'état sur iPhone).
      var FILL = 'position:fixed!important;left:0!important;top:0!important;width:100%!important;' +
        'height:100%!important;border:0!important;max-width:none!important;max-height:none!important;margin:0!important;' +
        'z-index:2147483647!important;background:#000!important;object-fit:contain!important;transform:none!important';
      // Une vidéo seule : on prend le lecteur qui l'entoure (même taille), pour garder ses boutons par-dessus.
      function player(el) {
        if (el.tagName !== 'VIDEO') return el;
        var r = el.getBoundingClientRect(), best = el, p = el.parentElement;
        while (p && p !== document.body && p !== document.documentElement) {
          var q = p.getBoundingClientRect();
          if (Math.abs(q.width - r.width) > 4 || Math.abs(q.height - r.height) > 4) break;
          best = p; p = p.parentElement;
        }
        return best;
      }
      // Un parent avec transform, filter, contain… enferme un élément « fixed » dans sa propre boîte (le lecteur de
      // YouTube restait petit) ; un parent avec z-index le laisse sous la barre du site. On les neutralise le temps du
      // plein écran, et on remet tout comme avant en sortant.
      var LIFT = 'transform:none!important;filter:none!important;perspective:none!important;contain:none!important;' +
        'will-change:auto!important;backdrop-filter:none!important;-webkit-backdrop-filter:none!important;' +
        'z-index:2147483647!important';
      function lift(el) {
        var list = [], p = el.parentElement;
        while (p) {
          list.push([p, p.getAttribute('style')]);
          p.setAttribute('style', (p.getAttribute('style') || '') + ';' + LIFT);
          p = p.parentElement;
        }
        return list;
      }
      function fill(el) {
        if (tf.filled === el) return true;
        if (tf.filled) unfill();
        el.__twinfoldStyle = el.getAttribute('style');
        el.setAttribute('style', FILL);
        el.__twinfoldLifted = lift(el);
        var dark = document.getElementById('__twinfold_style');
        if (dark) { tf.darkOff = dark.textContent; dark.textContent = ''; }
        tf.filled = el;
        post({ kind: 'fill', filled: true });
        setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 30);
        return true;
      }
      function restore(node, s) { if (s === null || s === undefined) node.removeAttribute('style'); else node.setAttribute('style', s); }
      function unfill() {
        var old = tf.filled;
        if (!old) return false;
        restore(old, old.__twinfoldStyle);
        (old.__twinfoldLifted || []).forEach(function (x) { restore(x[0], x[1]); });
        old.__twinfoldLifted = null;
        var dark = document.getElementById('__twinfold_style');
        if (dark && tf.darkOff !== undefined) { dark.textContent = tf.darkOff; tf.darkOff = undefined; }
        tf.filled = null;
        post({ kind: 'fill', filled: false });
        setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 30);
        return false;
      }
      tf.toggleFill = function () {
        if (tf.filled) return unfill();
        var vs = Array.prototype.slice.call(document.querySelectorAll('video'));
        vs.sort(function (a, b) { return b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight; });
        var v = vs.filter(function (x) { return !x.paused; })[0] || vs[0];
        if (!v) return false;
        return fill(v);
      };
      // Full screen stays in the pane: a page's "full screen" button fills this pane, not the whole display.
      if (window.__twinfoldFullscreenInPane) {
        var V = HTMLVideoElement.prototype;
        // L'ancienne API d'iPhone (YouTube mobile l'utilise) : on remplit le lecteur autour de la vidéo.
        V.webkitEnterFullscreen = V.webkitEnterFullScreen = function () {
          var v = this; askFull.call(player(v), true);
          try { v.dispatchEvent(new Event('webkitbeginfullscreen', { bubbles: true })); } catch (e) {}
        };
        V.webkitExitFullscreen = V.webkitExitFullScreen = function () {
          var v = this; leave();
          try { v.dispatchEvent(new Event('webkitendfullscreen', { bubbles: true })); } catch (e) {}
        };
        try { Object.defineProperty(V, 'webkitSupportsFullscreen', { get: function () { return true; }, configurable: true }); } catch (e) {}
        try { Object.defineProperty(V, 'webkitDisplayingFullscreen', { get: function () { return !!tf.fsEl && (tf.fsEl === this || tf.fsEl.contains(this)); }, configurable: true }); } catch (e) {}
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && tf.filled) { if (tf.fsEl) leave(); else unfill(); } }, true);
        // Sur iPhone, une vidéo sans « playsinline » part en plein écran dès qu'elle démarre : on la garde dans la page.
        function inline(root) {
          var vs = (root.querySelectorAll ? root.querySelectorAll('video') : []);
          for (var i = 0; i < vs.length; i++) { vs[i].setAttribute('playsinline', ''); vs[i].setAttribute('webkit-playsinline', ''); vs[i].playsInline = true; }
          if (root.tagName === 'VIDEO') { root.setAttribute('playsinline', ''); root.playsInline = true; }
        }
        inline(document);
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { inline(document); });
        new MutationObserver(function (ms) {
          ms.forEach(function (m) { m.addedNodes.forEach(function (n) { if (n.nodeType === 1) inline(n); }); });
        }).observe(document, { childList: true, subtree: true });
        // Le plein écran des lecteurs (YouTube, Vimeo, Twitch…) : ils demandent le plein écran de leur cadre. Ce cadre
        // remplit la page (pas tout l'écran), et le site croit être en plein écran : ses propres boutons marchent.
        tf.fsEl = null;
        function fire() {
          ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (n) {
            try { document.dispatchEvent(new Event(n, { bubbles: true })); } catch (e) {}
            if (tf.lastFs) { try { tf.lastFs.dispatchEvent(new Event(n, { bubbles: true })); } catch (e) {} }
          });
          setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 30);
        }
        function askFull(quiet) {
          var el = this.tagName === 'VIDEO' ? player(this) : this;
          fill(el);
          tf.fsEl = el; tf.lastFs = el;
          var vid = el.tagName === 'VIDEO' ? el : el.querySelector('video');
          // La vidéo et les boîtes entre elle et le lecteur prennent toute la place du lecteur.
          tf.stretched = [];
          if (vid && vid !== el) {
            for (var n = vid; n && n !== el; n = n.parentElement) {
              tf.stretched.push([n, n.getAttribute('style')]);
              ['width', 'height', 'max-width', 'max-height'].forEach(function (k) { n.style.setProperty(k, k.indexOf('max') === 0 ? 'none' : '100%', 'important'); });
              n.style.setProperty('left', '0', 'important'); n.style.setProperty('top', '0', 'important');
              n.style.setProperty('transform', 'none', 'important');
            }
            vid.style.setProperty('object-fit', 'contain', 'important');
          }
          if (quiet !== true) fire();
          // Un lecteur dans un cadre (YouTube intégré à un article) : la page autour remplit aussi le cadre.
          if (window !== window.top) { try { window.parent.postMessage({ __twinfoldFs: true }, '*'); } catch (e) {} }
          return Promise.resolve();
        }
        function leave() {
          var el = tf.fsEl;
          (tf.stretched || []).forEach(function (x) { restore(x[0], x[1]); });
          tf.stretched = [];
          var was = !!el;
          unfill(); tf.fsEl = null; fire();
          if (was && window !== window.top) { try { window.parent.postMessage({ __twinfoldFs: false }, '*'); } catch (e) {} }
          return Promise.resolve();
        }
        window.addEventListener('message', function (e) {
          if (!e.data || typeof e.data.__twinfoldFs !== 'boolean') return;
          var fr = Array.prototype.slice.call(document.querySelectorAll('iframe')).filter(function (f) { return f.contentWindow === e.source; })[0];
          if (!fr) return;
          if (e.data.__twinfoldFs) askFull.call(fr); else if (tf.fsEl === fr) leave();
        });
        var E = Element.prototype;
        E.requestFullscreen = askFull; E.webkitRequestFullscreen = askFull; E.webkitRequestFullScreen = askFull;
        document.exitFullscreen = leave; document.webkitExitFullscreen = leave; document.webkitCancelFullScreen = leave;
        var D = Document.prototype;
        [['fullscreenEnabled', function () { return true; }], ['webkitFullscreenEnabled', function () { return true; }],
         ['fullscreenElement', function () { return tf.fsEl; }], ['webkitFullscreenElement', function () { return tf.fsEl; }],
         ['webkitCurrentFullScreenElement', function () { return tf.fsEl; }], ['webkitIsFullScreen', function () { return !!tf.fsEl; }],
         ['fullscreen', function () { return !!tf.fsEl; }]].forEach(function (p) {
          try { Object.defineProperty(document, p[0], { get: p[1], configurable: true }); } catch (e) {}
          try { Object.defineProperty(D, p[0], { get: p[1], configurable: true }); } catch (e) {}
        });
        // Sortir du plein écran depuis Twinfold (bouton « revenir à la page ») : le site l'apprend aussi.
        var oldToggle = tf.toggleFill;
        tf.toggleFill = function () { if (tf.fsEl) { leave(); return false; } return oldToggle(); };
      }
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', report); else report();
    })();
    """#

    /// The script with the current settings in front (full screen in the pane).
    @MainActor static var withSettings: String {
        "window.__twinfoldFullscreenInPane = \(Library.shared.fullscreenInPane);\n" + source
    }

    @MainActor static func install(on controller: WKUserContentController, handler: WKScriptMessageHandler) {
        // Dès le début de la page : les lecteurs (YouTube…) regardent les fonctions de plein écran en se chargeant ;
        // installées à la fin, ils avaient déjà gardé celles d'iOS (le plein écran partait sur tout l'écran).
        controller.addUserScript(WKUserScript(source: withSettings, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(handler, name: handlerName)
    }
}

/// Receives the media reports of every page and hands each one to its tab. One per content controller (a page
/// that opens a window shares its controller with the new one, and a name can only be registered once).
@MainActor
final class MediaRouter: NSObject, WKScriptMessageHandler {
    static let shared = MediaRouter()

    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let tabs = NSMapTable<WKWebView, Tab>.weakToWeakObjects()

    func register(_ tab: Tab) {
        let controller = tab.webView.configuration.userContentController
        if !controllers.contains(controller) {
            controllers.add(controller)
            MediaScript.install(on: controller, handler: self)
        }
        tabs.setObject(tab, forKey: tab.webView)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let webView = message.webView, let tab = tabs.object(forKey: webView) else { return }
        if body["kind"] as? String == "fill" {
            withAnimation(.spring(response: 0.3)) { tab.isFilled = body["filled"] as? Bool ?? false }
            return
        }
        guard body["kind"] as? String == "state" else { return }
        tab.mediaReport(playing: body["playing"] as? Bool ?? false, video: body["video"] as? Bool ?? false,
                        mainFrame: message.frameInfo.isMainFrame)
    }
}
