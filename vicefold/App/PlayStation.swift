// PlayStation.swift — Vicefold (Pro)
//
// Ton temps de jeu PlayStation, lu sur ton propre compte. Tu te connectes toi-même sur la vraie page de connexion de
// Sony (dans l'app) : Vicefold ne voit jamais ton mot de passe. Le jeton de connexion reste dans le trousseau de cet
// iPhone et sert seulement à lire ta liste de jeux et leurs heures.
// L'accès passe par l'API qu'utilise l'app PlayStation (non documentée par Sony, comme la bibliothèque open source
// psn-api) : elle peut changer ou cesser de marcher sans prévenir.

import Foundation
import Observation
import Security
import SwiftUI
import WebKit

@MainActor @Observable
final class PlayStation {
    static let shared = PlayStation()

    struct Title: Decodable, Identifiable, Hashable {
        var titleId: String
        var name: String
        var playDuration: String?
        var playCount: Int?
        var lastPlayedDateTime: String?
        var id: String { titleId }
        var hours: Double { PlayStation.hours(playDuration) }
    }

    private(set) var titles: [Title] = []
    private(set) var busy = false
    var error: String?
    var connected: Bool { Keychain.get("psn.refresh") != nil }

    // Les identifiants publics de l'app PlayStation (ceux de psn-api).
    private static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    private static let basic = "MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="
    private static let redirect = "com.scee.psxandroid.scecompcall://redirect"
    private static let scope = "psn:mobile.v2.core psn:clientapp"
    static let signInURL = URL(string: "https://my.playstation.com/")!
    static let ssoURL = URL(string: "https://ca.account.sony.com/api/v1/ssocookie")!

    /// Après la connexion dans la page de Sony : le jeton « npsso » devient un jeton d'accès.
    func connect(npsso: String) async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            let code = try await authorize(npsso: npsso)
            try await token(["code": code, "redirect_uri": Self.redirect, "grant_type": "authorization_code", "token_format": "jwt"])
            await refreshTitles()
        } catch {
            self.error = String(localized: "PlayStation sign-in didn't work. Try again in a moment.")
        }
    }

    func disconnect() {
        Keychain.delete("psn.refresh"); Keychain.delete("psn.access")
        UserDefaults.standard.removeObject(forKey: "psn.expires")
        titles = []
        Progress.shared.edit { $0.psnHours = nil; $0.psnUpdated = nil }
    }

    func refreshTitles() async {
        guard connected else { return }
        busy = true
        defer { busy = false }
        do {
            let access = try await accessToken()
            var all: [Title] = []
            var offset = 0
            repeat {
                var req = URLRequest(url: URL(string: "https://m.np.playstation.com/api/gamelist/v2/users/me/titles?categories=ps4_game,ps5_native_game&limit=200&offset=\(offset)")!)
                req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
                let (d, r) = try await URLSession.shared.data(for: req)
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                struct Page: Decodable { var titles: [Title]; var nextOffset: Int? }
                let p = try JSONDecoder().decode(Page.self, from: d)
                all += p.titles
                offset = p.nextOffset ?? 0
            } while offset > 0 && all.count < 2000
            titles = all
            if let gta = gtaTitle {
                Progress.shared.edit { $0.psnHours = gta.hours; $0.psnUpdated = Date() }
            }
        } catch {
            self.error = String(localized: "Couldn't read your PlayStation play time.")
        }
    }

    /// Le jeu choisi par l'utilisateur, sinon celui qui ressemble à GTA VI.
    var gtaTitle: Title? {
        if let id = UserDefaults.standard.string(forKey: "psn.title"), let t = titles.first(where: { $0.titleId == id }) { return t }
        return titles.first { t in
            let n = t.name.lowercased()
            return n.contains("grand theft auto vi") || n.contains("gta vi") || n.contains("grand theft auto 6")
        }
    }

    func choose(_ t: Title) {
        UserDefaults.standard.set(t.titleId, forKey: "psn.title")
        Progress.shared.edit { $0.psnHours = t.hours; $0.psnUpdated = Date() }
    }

    static func hours(_ iso: String?) -> Double {
        guard var s = iso, s.hasPrefix("PT") || s.hasPrefix("P") else { return 0 }
        s = s.replacingOccurrences(of: "P", with: "").replacingOccurrences(of: "T", with: "")
        var total = 0.0, num = ""
        for ch in s {
            if ch.isNumber || ch == "." { num.append(ch); continue }
            let v = Double(num) ?? 0
            switch ch {
            case "D": total += v * 24
            case "H": total += v
            case "M": total += v / 60
            case "S": total += v / 3600
            default: break
            }
            num = ""
        }
        return total
    }

    // MARK: Jetons

    private func authorize(npsso: String) async throws -> String {
        var c = URLComponents(string: "https://ca.account.sony.com/api/authz/v3/oauth/authorize")!
        c.queryItems = [URLQueryItem(name: "access_type", value: "offline"), URLQueryItem(name: "client_id", value: Self.clientID),
                        URLQueryItem(name: "redirect_uri", value: Self.redirect), URLQueryItem(name: "response_type", value: "code"),
                        URLQueryItem(name: "scope", value: Self.scope)]
        var req = URLRequest(url: c.url!)
        req.setValue("npsso=\(npsso)", forHTTPHeaderField: "Cookie")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        let (_, r) = try await session.data(for: req)
        guard let loc = (r as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              let code = URLComponents(string: loc)?.queryItems?.first(where: { $0.name == "code" })?.value else { throw URLError(.userAuthenticationRequired) }
        return code
    }

    private func token(_ form: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://ca.account.sony.com/api/authz/v3/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Basic \(Self.basic)", forHTTPHeaderField: "Authorization")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)
        let (d, r) = try await URLSession.shared.data(for: req)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
        struct Tok: Decodable { var access_token: String; var refresh_token: String?; var expires_in: Double }
        let t = try JSONDecoder().decode(Tok.self, from: d)
        Keychain.set("psn.access", t.access_token)
        if let rt = t.refresh_token { Keychain.set("psn.refresh", rt) }
        UserDefaults.standard.set(Date().addingTimeInterval(t.expires_in - 60).timeIntervalSince1970, forKey: "psn.expires")
    }

    private func accessToken() async throws -> String {
        if let a = Keychain.get("psn.access"), Date().timeIntervalSince1970 < UserDefaults.standard.double(forKey: "psn.expires") { return a }
        guard let rt = Keychain.get("psn.refresh") else { throw URLError(.userAuthenticationRequired) }
        try await token(["refresh_token": rt, "grant_type": "refresh_token", "scope": Self.scope, "token_format": "jwt"])
        guard let a = Keychain.get("psn.access") else { throw URLError(.userAuthenticationRequired) }
        return a
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}

enum Keychain {
    static func set(_ key: String, _ value: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}

/// La page de connexion de Sony. Une fois connecté, on lit le jeton « npsso » sur la page de Sony prévue pour ça.
struct PSNSignIn: UIViewRepresentable {
    var done: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.navigationDelegate = context.coordinator
        v.load(URLRequest(url: PlayStation.signInURL))
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let done: (String?) -> Void
        var finished = false
        init(done: @escaping (String?) -> Void) { self.done = done }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished, let url = webView.url else { return }
            if url.host() == PlayStation.ssoURL.host() && url.path() == PlayStation.ssoURL.path() {
                webView.evaluateJavaScript("document.body.innerText") { [weak self] r, _ in
                    guard let self, let s = r as? String, let d = s.data(using: .utf8),
                          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
                    if let npsso = j["npsso"] as? String, !npsso.isEmpty { self.finished = true; self.done(npsso) }
                }
                return
            }
            // Connecté (on est revenu sur le site PlayStation) : on va chercher le jeton.
            if url.host()?.contains("playstation.com") == true {
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    if cookies.contains(where: { $0.name == "npsso" || $0.name.lowercased().contains("isloggedin") }) {
                        DispatchQueue.main.async { webView.load(URLRequest(url: PlayStation.ssoURL)) }
                    }
                }
            }
        }
    }
}
