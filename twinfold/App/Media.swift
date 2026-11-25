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
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', report); else report();
    })();
    """#

    /// Installed before any page script, in every frame. Page seule never calls the system video player.
    static let pageFullscreen = #"""
    (function () {
      if (window.__twinfoldPageFullscreen) return;
      window.__twinfoldPageFullscreen = true;
      function inPane() { return window.__twinfoldFullscreenInPane !== false; }
      function post(msg) { try { window.webkit.messageHandlers.twinfoldMedia.postMessage(msg); } catch (e) {} }
      var STYLE = 'position:fixed!important;inset:0!important;left:0!important;top:0!important;right:0!important;bottom:0!important;' +
        'width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;margin:0!important;' +
        'transform:none!important;z-index:2147483647!important;background:#000!important;object-fit:contain!important;';
      var originals = {};
      function capture(proto, name) {
        try {
          var d = Object.getOwnPropertyDescriptor(proto, name);
          if (d && typeof d.value === 'function') originals[name] = d.value;
        } catch (e) {}
      }
      function callNative(name, target, args) {
        var fn = originals[name];
        if (typeof fn === 'function') return fn.apply(target, args || []);
      }
      function inlineVideo(v) {
        if (!v || v.nodeType !== 1 || v.tagName !== 'VIDEO') return;
        try {
          v.setAttribute('playsinline', '');
          v.setAttribute('webkit-playsinline', '');
          v.playsInline = true;
        } catch (e) {}
        ['webkitEnterFullscreen', 'webkitEnterFullScreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen', 'requestFullscreen'].forEach(function (name) {
          try {
            Object.defineProperty(v, name, {
              configurable: true,
              get: function () { return function () { return inPane() ? enter(v) : callNative(name, v, arguments); }; },
              set: function () {}
            });
          } catch (e) {}
        });
        try {
          Object.defineProperty(v, 'webkitSetPresentationMode', {
            configurable: true,
            get: function () {
              return function (mode) {
                if (inPane() && mode === 'fullscreen') return enter(v);
                if (inPane() && (mode === 'inline' || mode === 'picture-in-picture') && box) return leave();
                return callNative('webkitSetPresentationMode', v, [mode]);
              };
            },
            set: function () {}
          });
        } catch (e) {}
      }
      function scan(root) {
        if (!root || root.nodeType !== 1) return;
        inlineVideo(root);
        if (!root.querySelectorAll) return;
        var list = root.querySelectorAll('video');
        for (var i = 0; i < list.length; i++) inlineVideo(list[i]);
      }
      var box = null, saved = null, place = null;
      function containerOf(video) {
        var best = video, p = video.parentElement, hops = 0;
        var r = video.getBoundingClientRect ? video.getBoundingClientRect() : { width: 0, height: 0 };
        while (p && p !== document.body && p !== document.documentElement && hops < 8) {
          var q = p.getBoundingClientRect ? p.getBoundingClientRect() : r;
          if (q.width > r.width + 120 || q.height > r.height + 120) break;
          best = p; p = p.parentElement; hops++;
        }
        return best;
      }
      function enter(video) {
        if (!video) return Promise.resolve();
        if (box) return Promise.resolve();
        if (video.tagName === 'VIDEO') inlineVideo(video);
        var target = video.tagName === 'VIDEO' ? containerOf(video) : video;
        saved = target.getAttribute('style');
        place = { parent: target.parentNode, next: target.nextSibling };
        target.setAttribute('style', STYLE);
        if (video !== target) {
          video.__tfStyle = video.getAttribute('style');
          video.setAttribute('style', (video.getAttribute('style') || '') + ';width:100%!important;height:100%!important;object-fit:contain!important;');
        }
        var root = document.documentElement || document.body;
        if (root && target.parentNode !== root) {
          try { root.appendChild(target); } catch (e) {}
        }
        box = target;
        box.__tfVideo = video;
        post({ kind: 'fullscreen', on: true });
        try { document.dispatchEvent(new Event('fullscreenchange', { bubbles: true })); } catch (e) {}
        try { video.dispatchEvent(new Event('webkitbeginfullscreen', { bubbles: true })); } catch (e) {}
        return Promise.resolve();
      }
      function leave() {
        var target = box, video = target && target.__tfVideo;
        box = null;
        if (target) {
          if (saved == null) target.removeAttribute('style'); else target.setAttribute('style', saved);
          if (place && place.parent) { try { place.parent.insertBefore(target, place.next); } catch (e) {} }
        }
        if (video && video !== target) {
          if (video.__tfStyle == null) video.removeAttribute('style'); else video.setAttribute('style', video.__tfStyle);
        }
        saved = null; place = null;
        post({ kind: 'fullscreen', on: false });
        try { document.dispatchEvent(new Event('fullscreenchange', { bubbles: true })); } catch (e) {}
        try { if (video) video.dispatchEvent(new Event('webkitendfullscreen', { bubbles: true })); } catch (e) {}
        return Promise.resolve();
      }
      function hook(proto, name, fn) {
        capture(proto, name);
        try {
          Object.defineProperty(proto, name, { configurable: true, writable: true, value: fn });
        } catch (e) {
          try { proto[name] = fn; } catch (e2) {}
        }
      }
      var V = (typeof HTMLVideoElement !== 'undefined') ? HTMLVideoElement.prototype : null;
      var E = Element.prototype;
      if (V) {
        ['webkitEnterFullscreen', 'webkitEnterFullScreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen', 'requestFullscreen'].forEach(function (name) {
          hook(V, name, function () { return inPane() ? enter(this) : callNative(name, this, arguments); });
        });
        hook(V, 'webkitExitFullscreen', function () { return inPane() ? leave() : callNative('webkitExitFullscreen', this, arguments); });
        hook(V, 'webkitExitFullScreen', function () { return inPane() ? leave() : callNative('webkitExitFullScreen', this, arguments); });
        hook(V, 'webkitSetPresentationMode', function (mode) {
          if (inPane() && mode === 'fullscreen') return enter(this);
          if (inPane() && box && mode !== 'fullscreen') return leave();
          return callNative('webkitSetPresentationMode', this, arguments);
        });
        try {
          Object.defineProperty(V, 'webkitSupportsFullscreen', { configurable: true, get: function () { return true; } });
          Object.defineProperty(V, 'webkitDisplayingFullscreen', { configurable: true, get: function () { return !!box; } });
        } catch (e) {}
      }
      ['requestFullscreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen'].forEach(function (name) {
        hook(E, name, function () {
          if (!inPane()) return callNative(name, this, arguments);
          var video = this.tagName === 'VIDEO' ? this : (this.querySelector && this.querySelector('video'));
          return enter(video || this);
        });
      });
      hook(document, 'exitFullscreen', function () { return inPane() ? leave() : callNative('exitFullscreen', document, arguments); });
      hook(document, 'webkitExitFullscreen', function () { return inPane() ? leave() : callNative('webkitExitFullscreen', document, arguments); });
      hook(document, 'webkitCancelFullScreen', function () { return inPane() ? leave() : callNative('webkitCancelFullScreen', document, arguments); });
      document.addEventListener('keydown', function (e) { if ((e.key === 'Escape' || e.key === 'Esc') && box && inPane()) leave(); }, true);
      document.addEventListener('click', function (e) {
        if (!inPane() || !box) return;
        var t = e.target;
        if (!t || !t.closest) return;
        var b = t.closest('button, [role="button"]');
        if (!b) return;
        var label = ((b.getAttribute('aria-label') || '') + ' ' + (b.className || '')).toLowerCase();
        if (label.indexOf('exit') !== -1 || label.indexOf('quitter') !== -1 || label.indexOf('close full') !== -1) {
          leave(); e.preventDefault(); e.stopPropagation();
        }
      }, true);
      scan(document);
      var obsRoot = document.documentElement || document;
      try {
        new MutationObserver(function (ms) {
          for (var i = 0; i < ms.length; i++) {
            var nodes = ms[i].addedNodes;
            if (!nodes) continue;
            for (var j = 0; j < nodes.length; j++) if (nodes[j].nodeType === 1) scan(nodes[j]);
          }
        }).observe(obsRoot, { childList: true, subtree: true });
      } catch (e) {}
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { scan(document); });
      var origCreate = document.createElement;
      document.createElement = function (name) {
        var el = origCreate.apply(document, arguments);
        if (String(name).toLowerCase() === 'video') inlineVideo(el);
        return el;
      };
    })();
    """#

    /// Read at the moment the button is pressed, so Settings can switch page-only and whole-display without a new script.
    @MainActor static var withSettings: String {
        "window.__twinfoldFullscreenInPane = \(Library.shared.fullscreenPage);\n" + source
    }

    @MainActor static var pageFullscreenScript: String {
        "window.__twinfoldFullscreenInPane = \(Library.shared.fullscreenPage);\n" + pageFullscreen
    }

    @MainActor static func install(on controller: WKUserContentController, handler: WKScriptMessageHandler) {
        // Before any site script, in every frame (YouTube's player included): Page seule must not reach AVPlayer.
        let early = WKUserScript(source: pageFullscreenScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(early)
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
