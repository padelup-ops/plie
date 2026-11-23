import SwiftUI
import UIKit

// MARK: - L'accueil « Atelier » (l'accueil de tout le monde depuis la 1.0.19)
//
// Règles suivies (swiftui-design-skill, licence MIT) : une seule couleur d'accent chaude sur des neutres chauds,
// titres en serif (New York) et texte en SF Pro, grille de 8 points, symboles SF (pas d'emoji), cibles de 44 points,
// du vrai contenu tout de suite (pas de « Bienvenue »), une mise en page asymétrique et UN détail signature :
// la carte « ta main », qui montre ce que le clavier a appris de ta prise en main.

enum Atelier {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ h: UInt32) -> UIColor {
            UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let bg = dyn(0xF5F3EF, 0x151412)
    static let surface = dyn(0xFFFFFF, 0x1F1E1B)
    static let sunk = dyn(0xEBE8E1, 0x2A2925)
    static let ink = dyn(0x1A1917, 0xF2F0EB)
    static let muted = dyn(0x75716A, 0x9C978E)
    static let accent = dyn(0xC4532F, 0xE2774F)     // terre cuite : la seule couleur
    static let accentSoft = dyn(0xF6E4DC, 0x3A2620)
    static let line = dyn(0xE3DFD6, 0x2E2C28)
    // Grille de 8 points.
    static let s1: CGFloat = 8, s2: CGFloat = 16, s3: CGFloat = 24, s4: CGFloat = 32
    static let radius: CGFloat = 16
}

/// Version d'essai (TestFlight) : on peut y montrer des choses en avant-première.
enum KBBuild {
    static let isTest: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}

struct AtelierHome: View {
    @Environment(SettingsModel.self) private var model
    @Environment(Store.self) private var store
    @Binding var showPro: Bool
    @AppStorage("setupDone") private var setupDone = false
    /// La recherche : un réglage ou une question, on trouve tout de suite où c'est.
    @State private var search = ""
    /// Une version plus récente sur l'App Store : une carte en haut pour mettre à jour.
    @State private var update: String? = KBVersion.updateAvailable
    @State private var learn = KBVault.loadLearn()
    @State private var tryText = ""
    @FocusState private var tryFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Atelier.s3) {
                header
                if let update { updateCard(update) }
                searchField
                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    results
                } else {
                    HStack(alignment: .top, spacing: Atelier.s2) {
                        setupTile
                        proTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    settingsGrid
                    help
                    hand
                    tryField
                    RecapRow()
                        .padding(Atelier.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .atelierCard()
                    Label("Foldboard never sends what you type anywhere. The keyboard has no internet access, and there is no account and no ads.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(Atelier.muted)
                }
            }
            .padding(.horizontal, Atelier.s2)
            .padding(.top, Atelier.s1)
            .padding(.bottom, Atelier.s4)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenDuo()
        .background(Atelier.bg.ignoresSafeArea())
        .tint(Atelier.accent)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { learn = KBVault.loadLearn() }
        .task { await refreshUpdate() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            learn = KBVault.loadLearn()
            Task { await refreshUpdate() }
        }
    }

    // MARK: En haut : le nom, petit, et la date.

    private var header: some View {
        HStack(alignment: .center, spacing: Atelier.s2) {
            Image("Logo")
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Foldboard")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(Atelier.ink)
                Text("The keyboard made for iPhone Duo")
                    .font(.footnote)
                    .foregroundStyle(Atelier.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Atelier.s2)
    }

    // MARK: Le détail signature : ta main

    private var hand: some View {
        let goal = LearningRow.goal
        let progress = Double(min(learn.all, goal)) / Double(goal)
        return VStack(alignment: .leading, spacing: Atelier.s2) {
            Text("Your hand")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Atelier.accent)
            HStack(alignment: .firstTextBaseline, spacing: Atelier.s1) {
                if let a = learn.accuracy {
                    Text(a, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 64, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(Atelier.ink)
                    Text("right side on its own")
                        .font(.subheadline)
                        .foregroundStyle(Atelier.muted)
                } else {
                    Text(verbatim: "\(learn.all)")
                        .font(.system(size: 64, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(Atelier.ink)
                    Text("habits learned")
                        .font(.subheadline)
                        .foregroundStyle(Atelier.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Une règle graduée : 25 habitudes, et le clavier te connaît.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<goal, id: \.self) { i in
                            Rectangle()
                                .fill(Atelier.line)
                                .frame(width: 1, height: i % 5 == 0 ? 12 : 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Capsule()
                        .fill(Atelier.accent)
                        .frame(width: max(4, g.size.width * progress), height: 4)
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
                .frame(height: 12, alignment: .bottom)
            }
            .frame(height: 12)
            HStack(spacing: Atelier.s2) {
                level("Duo closed", learn.closed)
                Rectangle().fill(Atelier.line).frame(width: 1, height: 32)
                level("Duo open", learn.open)
                Spacer(minLength: 0)
            }
            Text("Each time you type, or move the keyboard to the other side, Foldboard learns how you hold your Duo. The more you use it, the less you need to.")
                .font(.footnote)
                .foregroundStyle(Atelier.muted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { GripSetup().fullScreenDuo() } label: {
                Label { Text("Teach your thumbs · 30 s") } icon: { Image(systemName: "touchid") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Atelier.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(Atelier.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
        .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
    }

    private func level(_ name: LocalizedStringKey, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(Atelier.muted)
            Text(n == 0 ? LocalizedStringKey("Not yet") : (n < 10 ? LocalizedStringKey("Learning") : LocalizedStringKey("Knows you well")))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(n >= 10 ? Atelier.accent : Atelier.ink)
        }
    }

    // MARK: Deux tuiles : l'installation et Pro

    private var setupTile: some View {
        NavigationLink {
            SetupView(done: $setupDone).fullScreenDuo()
        } label: {
            tile(icon: setupDone ? "checkmark" : "keyboard.badge.ellipsis",
                 title: Text("Add Foldboard to your keyboards"),
                 detail: setupDone ? Text("Done") : Text("1 minute, 3 steps"),
                 filled: !setupDone)
        }
        .buttonStyle(.plain)
    }

    private var proTile: some View {
        Button { showPro = true } label: {
            tile(icon: store.access.purchased ? "checkmark.seal" : "sparkle",
                 title: Text(proTitle),
                 detail: Text(proDetail),
                 filled: false)
        }
        .buttonStyle(.plain)
    }

    private func tile(icon: String, title: Text, detail: Text, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(filled ? Color.white : Atelier.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? Atelier.accent : Atelier.accentSoft))
            Spacer(minLength: Atelier.s1)
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Atelier.ink)
                .fixedSize(horizontal: false, vertical: true)
            detail
                .font(.caption)
                .foregroundStyle(Atelier.muted)
                .lineLimit(3)
        }
        .padding(Atelier.s2)
        .frame(maxWidth: .infinity, minHeight: 136, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
        .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
        .contentShape(Rectangle())
    }

    private var proTitle: LocalizedStringKey {
        if store.access.purchased { return "Foldboard Pro is unlocked" }
        if store.isPro { return "Free trial in progress" }
        if store.access.trialOver() { return "Your free trial is over" }
        return "Try everything free for 3 days"
    }

    private var proDetail: String {
        if store.access.purchased { return NSLocalizedString("Thank you!", comment: "") }
        if store.isPro, let end = store.access.trialEnd {
            return String(format: NSLocalizedString("Until %@", comment: ""), end.formatted(date: .abbreviated, time: .shortened))
        }
        if store.access.trialOver() { return NSLocalizedString("Unlock Foldboard Pro to keep two hands, follow-your-hand, colors and phrases.", comment: "") }
        return NSLocalizedString("Two hands, follow-your-hand, colors, fonts, sounds and your phrases.", comment: "")
    }

    // MARK: Essayer

    private var tryField: some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            sectionTitle(Text("Try it"))
            HStack(alignment: .top, spacing: Atelier.s1) {
                TextField("Type here to try Foldboard", text: $tryText, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($tryFocus)
                    .foregroundStyle(Atelier.ink)
                if !tryText.isEmpty {
                    Button { tryText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Atelier.muted).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, Atelier.s2)
            .padding(.vertical, 12)
            .frame(minHeight: 88, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.sunk))
            .onTapGesture { tryFocus = true }
            Text("Tap the field, then hold the globe key and pick Foldboard.")
                .font(.caption)
                .foregroundStyle(Atelier.muted)
        }
    }

    // MARK: Mise à jour

    private func refreshUpdate() async {
        await UpdateCheck.run()
        update = KBVersion.updateAvailable
    }

    private func updateCard(_ v: String) -> some View {
        Link(destination: UpdateCheck.storeURL) {
            HStack(spacing: Atelier.s2) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Atelier.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Atelier.ink)
                    Text(String(format: NSLocalizedString("Foldboard %@ is out, with the latest fixes.", comment: ""), v))
                        .font(.caption)
                        .foregroundStyle(Atelier.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("Update")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Atelier.accent))
            }
            .padding(Atelier.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.accentSoft))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Recherche

    private var searchField: some View {
        HStack(spacing: Atelier.s1) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Atelier.muted)
            TextField("Search a setting or a question", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Atelier.ink)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Atelier.muted)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Atelier.sunk))
    }

    /// Les réglages et les questions qui correspondent, à la place de l'accueil pendant qu'on cherche.
    @ViewBuilder private var results: some View {
        let found = SettingsEntry.search(search)
        let questions = FAQ.search(search)
        if found.isEmpty && questions.isEmpty {
            Text("No result")
                .font(.subheadline)
                .foregroundStyle(Atelier.muted)
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: Atelier.s1) {
                sectionTitle(Text("Settings"))
                VStack(spacing: 0) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { divider }
                        row(e.page.icon, Text(verbatim: e.title), Text(e.page.title)) { e.page.destination }
                    }
                }
                .atelierCard()
            }
        }
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: Atelier.s1) {
                sectionTitle(Text("Questions and answers"))
                VStack(spacing: 0) {
                    ForEach(Array(questions.enumerated()), id: \.element.id) { i, q in
                        if i > 0 { divider }
                        row("questionmark.bubble", Text(verbatim: q.question), nil) { FAQView(open: q.id).fullScreenDuo() }
                    }
                }
                .atelierCard()
            }
        }
    }

    // MARK: Réglages : une grille de six cartes, chacune dit ce qu'on y trouve

    private var settingsGrid: some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            sectionTitle(Text("Settings"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Atelier.s2), GridItem(.flexible(), spacing: Atelier.s2)],
                      spacing: Atelier.s2) {
                ForEach(SettingsPage.grid, id: \.self) { p in
                    NavigationLink { p.destination } label: { pageTile(p) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func pageTile(_ p: SettingsPage) -> some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            Image(systemName: p.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Atelier.accent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Atelier.accentSoft))
            Spacer(minLength: 0)
            Text(p.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Atelier.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(p.subtitle)
                .font(.caption)
                .foregroundStyle(Atelier.muted)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(Atelier.s2)
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: .infinity, alignment: .topLeading)
        .atelierCard()
        .contentShape(Rectangle())
    }

    // MARK: Aide : les questions d'abord

    private var help: some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            sectionTitle(Text("Help"))
            VStack(spacing: 0) {
                link("questionmark.bubble", "Questions and answers", "The questions people ask most") { FAQView().fullScreenDuo() }
                divider
                link("hand.tap", "How it works") { PlaceTutorial().fullScreenDuo() }
                divider
                link("play.rectangle", "Guided tour") { KeyboardTourScreen() }
                divider
                link("sparkles", "What's new") { WhatsNewView().fullScreenDuo() }
                divider
                link("rectangle.topthird.inset.filled", "The keyboard buttons") { ButtonsGuide().fullScreenDuo() }
            }
            .atelierCard()
        }
    }

    private var divider: some View {
        Rectangle().fill(Atelier.line).frame(height: 1).padding(.leading, 56)
    }

    private func link<D: View>(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        row(icon, Text(title), subtitle.map { Text($0) }, dest)
    }

    private func row<D: View>(_ icon: String, _ title: Text, _ subtitle: Text?, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: Atelier.s2) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Atelier.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.body)
                        .foregroundStyle(Atelier.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        subtitle.font(.footnote).foregroundStyle(Atelier.muted)
                    }
                }
                .padding(.vertical, subtitle == nil ? 0 : 6)
                Spacer(minLength: Atelier.s1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Atelier.muted.opacity(0.6))
            }
            .padding(.horizontal, Atelier.s2)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ t: Text) -> some View {
        t.font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(Atelier.ink)
    }
}

/// Une fois toutes les 6 heures au plus, l'app demande à l'App Store le numéro de la dernière version (rien n'est
/// envoyé : ni texte tapé, ni identifiant). Le clavier, lui, ne va jamais sur internet : il lit ce que l'app a noté.
enum UpdateCheck {
    static let appID = "6832556606"
    static let storeURL = URL(string: "itms-apps://apps.apple.com/app/id6832556606")!

    static func run() async {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        guard now - d.double(forKey: "foldboard.updateCheck") > 6 * 3600 else { return }
        let session = URLSession(configuration: .ephemeral)
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        for c in (country == "us" ? ["us"] : [country, "us"]) {
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appID)&country=\(c)") else { continue }
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            guard let (data, _) = try? await session.data(for: req),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]],
                  let v = results.first?["version"] as? String, !v.isEmpty else { continue }
            KBVault.saveLatestVersion(v)
            d.set(now, forKey: "foldboard.updateCheck")
            return
        }
    }
}
