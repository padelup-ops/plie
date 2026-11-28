import CoreLocation
import SwiftUI
import UIKit

/// Diagnostic des créneaux : teste chaque étape depuis l'iPhone (Playtomic direct et par la page, recherche,
/// Anybuddy) et affiche ce qui répond. Le joueur peut copier le résultat et l'envoyer.
struct DiagnosticView: View {
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [(ok: Bool?, text: String)] = []
    @State private var running = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Screen(title: "Diagnostic", eyebrow: "Créneaux Playtomic et Anybuddy", seasonal: false) {
                Text("Chaque étape est testée depuis ton iPhone. Copie le résultat et envoie-le si les créneaux ne s'affichent pas.")
                    .font(UI.callout()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: l.ok == nil ? "circle.dotted" : (l.ok! ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                .foregroundStyle(l.ok == nil ? UI.muted : (l.ok! ? UI.success : UI.danger))
                            Text(l.text).font(.system(size: 13, design: .monospaced)).foregroundStyle(UI.ink)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                    if running { ProgressView().padding(.top, 4) }
                }
                HStack(spacing: 10) {
                    Button { Task { await run() } } label: { Text(lines.isEmpty ? "Lancer" : "Relancer") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(running)
                    Button {
                        UIPasteboard.general.string = lines.map { ($0.ok == nil ? "• " : ($0.ok! ? "OK " : "ÉCHEC ")) + $0.text }.joined(separator: "\n")
                        copied = true
                    } label: { Text(copied ? "Copié" : "Copier") }
                    .buttonStyle(SecondaryButtonStyle()).disabled(lines.isEmpty || running)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .task { if lines.isEmpty { await run() } }
    }

    private func add(_ ok: Bool?, _ text: String) { lines.append((ok, text)) }

    private func run() async {
        running = true
        copied = false
        lines = []
        defer { running = false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        add(nil, "PadelUp Neo build \(version) · \(Date().formatted(date: .abbreviated, time: .shortened))")

        // 1) Position et clubs proches
        guard let loc = location.location else {
            add(false, "Position inconnue : active la localisation.")
            return
        }
        let city = (try? await CLGeocoder().reverseGeocodeLocation(loc).first?.locality) ?? "?"
        add(true, "Position : \(city)")
        let near = directory.nearest(to: loc, limit: 12, maxKm: 30)
        add(!near.isEmpty, "Clubs à moins de 30 km : \(near.count) · Playtomic reliés : \(near.filter { $0.playtomicTenantID != nil }.count)")
        add(!AnybuddyDirectory.slugs.isEmpty, "Liste Anybuddy embarquée : \(AnybuddyDirectory.slugs.count) clubs")
        let abMatches = near.compactMap { c in (c.anybuddySlug ?? AnybuddyDirectory.match(c)).map { (c, $0) } }
        add(!abMatches.isEmpty, "Reconnus sur Anybuddy : " + (abMatches.isEmpty ? "aucun" : abMatches.prefix(4).map { "\($0.0.displayName) → \($0.1)" }.joined(separator: ", ")))

        // 2) Recherche Playtomic : requête directe, puis navigateur invisible
        var comps = URLComponents(string: "https://playtomic.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: "\(city) france"), URLQueryItem(name: "_rsc", value: "padelup")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.setValue("1", forHTTPHeaderField: "RSC")
        if let r = try? await URLSession.shared.data(for: req) {
            let (data, resp) = r
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let found = PlaytomicWeb.parseClubs(String(decoding: data, as: UTF8.self))
            add(code == 200 && !found.isEmpty, "Recherche Playtomic directe « \(city) » : HTTP \(code), \(data.count / 1024) ko, \(found.count) club(s)")
        } else {
            add(false, "Recherche Playtomic directe : pas de réponse")
        }
        let viaPage = await HiddenBrowser.shared.search(city + " france")
        add(!viaPage.isEmpty, "Recherche Playtomic par le site : \(viaPage.count) club(s)" + (viaPage.isEmpty ? "" : " · " + viaPage.prefix(3).map(\.name).joined(separator: ", ")))

        // 3) Créneaux Playtomic d'un club (direct, puis par la page)
        var tenant = near.first { $0.playtomicTenantID != nil }?.playtomicTenantID
        var tenantName = near.first { $0.playtomicTenantID != nil }?.displayName ?? ""
        if tenant == nil, let first = viaPage.first {
            tenant = first.id.isEmpty ? await HiddenBrowser.shared.tenantID(slug: first.slug) : first.id
            tenantName = first.name
        }
        if let tenant {
            let day = FR.string(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(), "yyyy-MM-dd")
            let path = "/api/clubs/availability?tenant_id=\(tenant)&date=\(day)&sport_id=PADEL"
            if let url = URL(string: "https://playtomic.com" + path), let r = try? await URLSession.shared.data(from: url) {
                let (data, resp) = r
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let blocks = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.count ?? -1
                add(code == 200 && blocks >= 0, "Créneaux Playtomic directs (\(tenantName), demain) : HTTP \(code), \(data.count) octets, \(max(0, blocks)) terrain(s)")
            } else {
                add(false, "Créneaux Playtomic directs : pas de réponse")
            }
            if let page = await HiddenBrowser.shared.pageFetch(origin: PlaytomicWeb.site, path: path) {
                let blocks = (try? JSONSerialization.jsonObject(with: Data(page.body.utf8)) as? [[String: Any]])?.count ?? -1
                add(page.status == 200 && blocks >= 0, "Créneaux Playtomic par la page : HTTP \(page.status), \(page.body.count) car., \(max(0, blocks)) terrain(s)")
            } else {
                add(false, "Créneaux Playtomic par la page : pas de réponse")
            }
        } else {
            add(false, "Aucun club Playtomic trouvé pour tester les créneaux")
        }

        // 4) Anybuddy : la page d'un club reconnu
        if let m = abMatches.first {
            let (club, slug) = m
            let today = Calendar.current.startOfDay(for: Date())
            do {
                let s = try await AnybuddyAPI.slots(slug: slug, day: today)
                add(true, "Anybuddy « \(club.displayName) » aujourd'hui : \(s.count) créneau(x) lu(s) sur la page")
            } catch {
                add(false, "Anybuddy « \(club.displayName) » : \(error.localizedDescription)")
            }
        }
        add(nil, "Fin du diagnostic.")
    }
}
