// GameCenter.swift — Vicefold
//
// Les amis passent par Game Center : pas de compte à créer. On ne se connecte qu'en ouvrant la communauté (pas
// de bannière au lancement), puis on publie son 100 % dans un classement que seuls les amis voient ensemble.
// Le pseudo Game Center signe les messages de l'entraide ; l'auteur est une empreinte, jamais l'identifiant.

import CryptoKit
import GameKit
import SwiftUI

struct VFFriend: Identifiable, Hashable {
    var id: String
    var name: String
    var percent: Int?
    var isMe = false
}

@MainActor @Observable
final class GameCenterHub {
    static let shared = GameCenterHub()
    static let board = "vicefold.leonida"
    private static let usedKey = "vicefold.gameCenterUsed"

    private(set) var signedIn = false
    private(set) var alias = ""
    private(set) var friends: [VFFriend] = []
    private(set) var friendsDenied = false
    private(set) var loading = false
    private(set) var failed = false

    /// L'auteur de ses messages : une empreinte de l'identifiant Game Center.
    private(set) var author: String?

    /// Déjà venu dans la communauté : on se reconnecte en silence au lancement suivant.
    var used: Bool { UserDefaults.standard.bool(forKey: Self.usedKey) }

    private init() {
        if ShotMode.route != nil {
            signedIn = true; alias = "Alex"; author = String(repeating: "a", count: 64)
            friends = Self.demo
        }
    }

    func authenticate() {
        guard ShotMode.route == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.usedKey)
        if GKLocalPlayer.local.isAuthenticated { refresh(); return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let vc { Self.top()?.present(vc, animated: true); return }
                self.failed = error != nil && !GKLocalPlayer.local.isAuthenticated
                self.refresh()
            }
        }
    }

    private func refresh() {
        let me = GKLocalPlayer.local
        signedIn = me.isAuthenticated
        guard signedIn else { return }
        alias = me.alias
        let digest = SHA256.hash(data: Data(("vicefold:" + me.teamPlayerID).utf8))
        author = digest.map { String(format: "%02x", $0) }.joined()
        report(Progress.shared.parts(ContentStore.shared.content).total)
        Task { await loadFriends() }
    }

    /// Ton 100 % dans le classement des amis (seulement s'il a changé).
    func report(_ total: Double) {
        guard signedIn, ShotMode.route == nil else { return }
        let score = Int((total * 100).rounded())
        let key = "vicefold.lastScore"
        guard UserDefaults.standard.object(forKey: key) as? Int != score else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.board])
                UserDefaults.standard.set(score, forKey: key)
            } catch {}
        }
    }

    func loadFriends() async {
        guard signedIn, ShotMode.route == nil else { return }
        loading = true
        defer { loading = false }
        let me = GKLocalPlayer.local
        var list: [String: VFFriend] = [:]
        // La liste d'amis (iOS demande la permission la première fois).
        if let players = try? await me.loadFriends() {
            for p in players { list[p.teamPlayerID] = VFFriend(id: p.teamPlayerID, name: p.displayName) }
            friendsDenied = false
        } else if let s = try? await me.loadFriendsAuthorizationStatus(), s == .denied || s == .restricted {
            friendsDenied = true
        }
        // Leur 100 % : le classement vu par les amis.
        if let board = try? await GKLeaderboard.loadLeaderboards(IDs: [Self.board]).first,
           let result = try? await board.loadEntries(for: .friendsOnly, timeScope: .allTime, range: NSRange(location: 1, length: 100)) {
            let (mine, entries) = (result.0, result.1)
            for e in entries {
                list[e.player.teamPlayerID, default: VFFriend(id: e.player.teamPlayerID, name: e.player.displayName)].percent = e.score
            }
            if let mine { list[mine.player.teamPlayerID, default: VFFriend(id: mine.player.teamPlayerID, name: mine.player.displayName)].percent = mine.score }
        }
        let myID = me.teamPlayerID
        list[myID, default: VFFriend(id: myID, name: me.displayName)].isMe = true
        if list[myID]?.percent == nil { list[myID]?.percent = Int((Progress.shared.parts(ContentStore.shared.content).total * 100).rounded()) }
        friends = list.values.sorted { ($0.percent ?? -1, $1.name) > ($1.percent ?? -1, $0.name) }
    }

    /// La feuille d'Apple pour inviter un ami Game Center.
    func addFriends() {
        guard signedIn, let vc = Self.top() else { authenticate(); return }
        try? GKLocalPlayer.local.presentFriendRequestCreator(from: vc)
    }

    static func top() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var vc = scene?.keyWindow?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    static let demo: [VFFriend] = [
        VFFriend(id: "d1", name: "Mia_VC", percent: 62),
        VFFriend(id: "me", name: "Alex", percent: 45, isMe: true),
        VFFriend(id: "d2", name: "KeysRunner", percent: 38),
        VFFriend(id: "d3", name: "Port Gellhorn Pete", percent: 21),
        VFFriend(id: "d4", name: "Lucia fan #1", percent: nil),
    ]
}
