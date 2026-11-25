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
      // Move the player out of any transformed or shadow-DOM box, so "fixed" really means the page,
      // which is this pane — not the little rectangle the site's player drew.
      function park(el) {
        if (!el || el.__tfPlace || !el.parentNode) return;
        el.__tfPlace = { parent: el.parentNode, next: el.nextSibling };
        var root = document.documentElement || document.body;
        if (root && el.parentNode !== root) root.appendChild(el);
      }
      function unpark(el) {
        if (!el) return;
        var place = el.__tfPlace;
        el.__tfPlace = null;
        if (!place || !place.parent) return;
        try { place.parent.insertBefore(el, place.next); } catch (e) {}
      }
      function surface(el) {
        var n = el;
        while (n && n.getRootNode) {
          var root = n.getRootNode();
          if (root && root.host) n = root.host;
          else break;
        }
        return player(n || el);
      }
      function fill(el) {
        if (tf.filled === el) return true;
        if (tf.filled) unfill();
        el.__twinfoldStyle = el.getAttribute('style');
        el.setAttribute('style', FILL);
        el.__twinfoldLifted = lift(el);
        park(el);
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
        unpark(old);
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
      // Inline playback, so two panes can play at once. Full screen is decided when the button is pressed.
      (function () {
        function inline(root) {
          var vs = (root.querySelectorAll ? root.querySelectorAll('video') : []);
          for (var i = 0; i < vs.length; i++) {
            vs[i].setAttribute('playsinline', '');
            vs[i].setAttribute('webkit-playsinline', '');
            vs[i].playsInline = true;
          }
          if (root.tagName === 'VIDEO') { root.setAttribute('playsinline', ''); root.playsInline = true; }
        }
        inline(document);
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { inline(document); });
        new MutationObserver(function (ms) {
          ms.forEach(function (m) { m.addedNodes.forEach(function (n) { if (n.nodeType === 1) inline(n); }); });
        }).observe(document, { childList: true, subtree: true });
      })();
      // Page-only full screen (the default): the site's own button fills this pane, not both screens.
      // Whole Display calls through to the original functions, and WebKit covers the window.
      (function () {
        var V = HTMLVideoElement.prototype;
        var origEnter = V.webkitEnterFullscreen || V.webkitEnterFullScreen;
        var origExit = V.webkitExitFullscreen || V.webkitExitFullScreen;
        var origRequest = Element.prototype.requestFullscreen || Element.prototype.webkitRequestFullscreen || Element.prototype.webkitRequestFullScreen;
        var origDocExit = document.exitFullscreen || document.webkitExitFullscreen || document.webkitCancelFullScreen;
        function inPane() { return window.__twinfoldFullscreenInPane !== false; }
        function fire() {
          ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (n) {
            try { document.dispatchEvent(new Event(n, { bubbles: true })); } catch (e) {}
          });
        }
        function askFull() {
          if (!inPane()) {
            if (origRequest) return origRequest.apply(this, arguments);
            return Promise.resolve();
          }
          var el = surface(this.tagName === 'VIDEO' ? this : (this.querySelector && this.querySelector('video')) || this);
          fill(el);
          tf.fsEl = el;
          post({ kind: 'fullscreen', on: true });
          fire();
          try { if (el.tagName === 'VIDEO') el.dispatchEvent(new Event('webkitbeginfullscreen', { bubbles: true })); } catch (e) {}
          return Promise.resolve();
        }
        function leave() {
          if (!inPane()) {
            if (origDocExit) return origDocExit.apply(document, arguments);
            return Promise.resolve();
          }
          var el = tf.fsEl;
          tf.fsEl = null;
          unfill();
          post({ kind: 'fullscreen', on: false });
          fire();
          try { if (el && el.tagName === 'VIDEO') el.dispatchEvent(new Event('webkitendfullscreen', { bubbles: true })); } catch (e) {}
          return Promise.resolve();
        }
        V.webkitEnterFullscreen = V.webkitEnterFullScreen = function () {
          if (!inPane() && origEnter) return origEnter.apply(this, arguments);
          return askFull.call(this);
        };
        V.webkitExitFullscreen = V.webkitExitFullScreen = function () {
          if (!inPane() && origExit) return origExit.apply(this, arguments);
          return leave();
        };
        try { Object.defineProperty(V, 'webkitSupportsFullscreen', { get: function () { return true; }, configurable: true }); } catch (e) {}
        try { Object.defineProperty(V, 'webkitDisplayingFullscreen', { get: function () { return !!tf.fsEl; }, configurable: true }); } catch (e) {}
        var E = Element.prototype;
        E.requestFullscreen = E.webkitRequestFullscreen = E.webkitRequestFullScreen = function () { return askFull.call(this); };
        document.exitFullscreen = document.webkitExitFullscreen = document.webkitCancelFullScreen = leave;
        var D = Document.prototype;
        [['fullscreenEnabled', function () { return true; }], ['webkitFullscreenEnabled', function () { return true; }],
         ['fullscreenElement', function () { return tf.fsEl || null; }], ['webkitFullscreenElement', function () { return tf.fsEl || null; }],
         ['webkitIsFullScreen', function () { return !!tf.fsEl; }]].forEach(function (p) {
          try { Object.defineProperty(document, p[0], { get: p[1], configurable: true }); } catch (e) {}
          try { Object.defineProperty(D, p[0], { get: p[1], configurable: true }); } catch (e) {}
        });
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && tf.fsEl) leave(); }, true);
        function labelOf(el) {
          var c = '';
          try { c = (el.className && String(el.className)) || ''; } catch (e) {}
          return ((el.getAttribute && (el.getAttribute('aria-label') || '')) + ' ' + c + ' ' + ((el.getAttribute && el.getAttribute('title')) || '')).toLowerCase();
        }
        function looksFull(el) { return /fullscreen|full-screen|ytp-fullscreen|plein écran|plein ecran/.test(labelOf(el)); }
        document.addEventListener('click', function (e) {
          if (!inPane()) return;
          var t = e.target;
          if (!t || !t.closest) return;
          var b = t.closest('button, [role="button"]');
          if (!b || !looksFull(b)) return;
          if (tf.fsEl) { leave(); e.preventDefault(); e.stopPropagation(); return; }
          setTimeout(function () {
            if (tf.fsEl || !inPane()) return;
            var v = document.querySelector('video');
            if (!v) return;
            var r = v.getBoundingClientRect();
            if (r.width < window.innerWidth * 0.85 || r.height < window.innerHeight * 0.65) askFull.call(v);
          }, 280);
        }, true);
        var root = document.documentElement || document;
        if (root && root.nodeType === 1) {
          new MutationObserver(function (ms) {
            if (!inPane() || tf.fsEl) return;
            for (var i = 0; i < ms.length; i++) {
              var target = ms[i].target;
              if (!target || target.nodeType !== 1 || !looksFull(target)) continue;
              var v = (target.querySelector && target.querySelector('video')) || target;
              askFull.call(v);
              return;
            }
          }).observe(root, { attributes: true, subtree: true, attributeFilter: ['class'] });
        }
      })();
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', report); else report();
    })();
    """#

    /// Read at the moment the button is pressed, so Settings can switch page-only and whole-display without a new script.
    @MainActor static var withSettings: String {
        "window.__twinfoldFullscreenInPane = \(Library.shared.fullscreenPage);\n" + source
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
        if body["kind"] as? String == "fullscreen" {
            Browser.shared.setFullscreen(body["on"] as? Bool ?? false, webView: webView)
            return
        }
        guard body["kind"] as? String == "state" else { return }
        tab.mediaReport(playing: body["playing"] as? Bool ?? false, video: body["video"] as? Bool ?? false,
                        mainFrame: message.frameInfo.isMainFrame)
    }
}
