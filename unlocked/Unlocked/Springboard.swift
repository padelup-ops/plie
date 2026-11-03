import SwiftUI

// MARK: - Le système du faux téléphone : barre d'état, écran verrouillé, code, accueil, ouverture des applis

/// L'heure du jeu : 8 h 12 au premier lancement, puis elle avance avec le vrai temps.
enum GameClock {
    private static let key = "unlocked.clockStart"

    static var start: Date {
        if let d = UserDefaults.standard.object(forKey: key) as? Date { return d }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    static func minutes(at date: Date) -> Int {
        let elapsed = Int(date.timeIntervalSince(start) / 60)
        return (8 * 60 + 12 + max(0, elapsed)) % (24 * 60)
    }

    static func text(at date: Date) -> String {
        let m = minutes(at: date)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

// MARK: Barre d'état

struct StatusBar: View {
    var dark = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            HStack {
                Text(GameClock.text(at: ctx.date))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 90)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "cellularbars", variableValue: 0.5)
                    Text("4G").font(.system(size: 15, weight: .semibold))
                    BatteryIcon(level: 0.23)
                }
                .frame(width: 100)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(dark ? Color.black : Color.white)
            .padding(.horizontal, 14)
        }
        .accessibilityHidden(true)
    }
}

struct BatteryIcon: View {
    let level: Double

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(lineWidth: 1).opacity(0.45).frame(width: 25, height: 12)
                RoundedRectangle(cornerRadius: 2.5).frame(width: max(3, 21 * level), height: 8).padding(.leading, 2)
            }
            RoundedRectangle(cornerRadius: 1).frame(width: 1.5, height: 4).opacity(0.45)
        }
    }
}

/// Place la barre d'état dans la zone du haut (à côté de l'encoche ou de la Dynamic Island).
struct StatusBarOverlay: ViewModifier {
    var dark = false
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { g in
                StatusBar(dark: dark)
                    .frame(height: max(24, g.safeAreaInsets.top))
                    .offset(y: g.safeAreaInsets.top > 30 ? 2 : 0)
                    .ignoresSafeArea()
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func statusBar(dark: Bool = false) -> some View { modifier(StatusBarOverlay(dark: dark)) }
}

// MARK: Icône d'appli

struct AppIconImage: View {
    let app: AppKind
    var size: CGFloat = 62

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: app.colors, startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay { glyph }
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    @ViewBuilder private var glyph: some View {
        switch app {
        case .calendar:
            VStack(spacing: -2) {
                Text(T("LUN.", "MON")).font(.system(size: size * 0.16, weight: .semibold)).foregroundStyle(.red)
                Text("3").font(.system(size: size * 0.5, weight: .light)).foregroundStyle(.black)
            }
        case .photos:
            ZStack {
                ForEach(0..<8) { i in
                    Capsule()
                        .fill([Color.orange, .yellow, .green, .teal, .blue, .indigo, .purple, .pink][i].opacity(0.85))
                        .frame(width: size * 0.2, height: size * 0.38)
                        .offset(y: -size * 0.15)
                        .rotationEffect(.degrees(Double(i) * 45))
                        .blendMode(.multiply)
                }
            }
        case .notes:
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 1.0, green: 0.8, blue: 0.2)).frame(height: size * 0.24)
                ZStack {
                    Color.white
                    VStack(spacing: size * 0.1) {
                        ForEach(0..<3) { _ in Rectangle().fill(Color(white: 0.85)).frame(height: 1) }
                    }
                    .padding(.horizontal, size * 0.12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        default:
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(app == .weather ? .multicolor : .monochrome)
        }
    }
}

struct AppIcon: View {
    @Environment(GameState.self) private var state
    let app: AppKind
    var label = true

    var body: some View {
        let locked = app.chapter > state.chapter
        let badge = app == .messages ? state.story.conversations.filter { state.unread($0.id) }.count
            : (app == .phone ? state.story.voicemails.filter { v in (v.requires.map { state.has($0) } ?? true) && !state.has("heard_" + v.id) }.count : 0)
        Button {
            if locked {
                if state.needsPurchase { state.showPaywall = true } else { state.lockedAppAlert = app }
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                state.launch(app)
            }
        } label: {
            VStack(spacing: 5) {
                AppIconImage(app: app)
                    .overlay {
                        if locked {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.45))
                            Image(systemName: "lock.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 && !locked {
                            Text("\(badge)")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(minWidth: 24, minHeight: 24)
                                .background(Capsule().fill(Color(red: 1, green: 0.23, blue: 0.19)))
                                .offset(x: 8, y: -8)
                        }
                    }
                if label {
                    Text(app.title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(IconPressStyle())
        .accessibilityLabel(locked ? app.title + ", " + T("verrouillée", "locked") : app.title)
    }
}

struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.15 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Écran verrouillé

struct LockScreen: View {
    @Environment(GameState.self) private var state
    @State private var drag: CGFloat = 0
    @State private var showPad = UserDefaults.standard.string(forKey: "shot") == "pad"
    @State private var torch = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                ArtView(art: state.story.wallpaper)
                    .scaleEffect(1.05 + min(0.1, -drag / 3000))
                    .ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.top, 10)
                    TimelineView(.periodic(from: .now, by: 15)) { ctx in
                        VStack(spacing: -8) {
                            Text(T("lundi 3 novembre", "Monday, November 3"))
                                .font(.system(size: 21, weight: .semibold))
                                .opacity(0.9)
                            Text(GameClock.text(at: ctx.date))
                                .font(.system(size: 104, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .tracking(-2)
                        }
                    }
                    .padding(.top, 8)

                    Spacer()

                    // Les notifications, en pile, en bas
                    VStack(spacing: 8) {
                        HStack {
                            Text(T("Centre de notifications", "Notification Center"))
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .opacity(0.85)
                        ForEach(state.story.lockNotifications) { m in
                            NotificationCard(message: m, contact: state.story.contact(m.thread), when: m.time)
                        }
                        Text(T("+ 10 autres notifications", "+ 10 more notifications"))
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.7)
                    }
                    .padding(.horizontal, 10)

                    HStack {
                        LockButton(symbol: torch ? "flashlight.on.fill" : "flashlight.off.fill", on: torch) { torch.toggle() }
                        Spacer()
                        VStack(spacing: 8) {
                            Text(T("Balayez vers le haut pour ouvrir", "Swipe up to open"))
                                .font(.system(size: 15, weight: .medium))
                                .opacity(0.85)
                            Capsule().fill(Color.white).frame(width: 140, height: 5)
                        }
                        Spacer()
                        LockButton(symbol: "camera.fill", on: false) {}
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .foregroundStyle(.white)
                .offset(y: min(0, drag))
                .opacity(1 + Double(min(0, drag)) / 400)

                if showPad {
                    PasscodeScreen(close: { withAnimation(.spring(duration: 0.35)) { showPad = false; drag = 0 } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in if !showPad { drag = min(0, v.translation.height) } }
                    .onEnded { v in
                        guard !showPad else { return }
                        if v.translation.height < -110 || v.predictedEndTranslation.height < -250 {
                            withAnimation(.spring(duration: 0.35)) { showPad = true }
                        }
                        withAnimation(.spring(duration: 0.35)) { drag = 0 }
                    }
            )
            .accessibilityAction(named: T("Déverrouiller", "Unlock")) { withAnimation { showPad = true } }
        }
    }
}

struct LockButton: View {
    let symbol: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 50, height: 50)
                .background(Circle().fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)))
                .foregroundStyle(on ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }
}

/// Une notification au style du système : icône Messages, nom, heure, texte.
struct NotificationCard: View {
    let message: Message
    let contact: Contact
    let when: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(contact: contact, size: 38)
                AppIconImage(app: .messages, size: 17).offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(contact.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(when).font(.system(size: 13)).opacity(0.6)
                }
                Text(message.text).font(.system(size: 15)).lineLimit(2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .environment(\.colorScheme, .light)
        .foregroundStyle(.black)
    }
}

// MARK: Code

struct PasscodeScreen: View {
    @Environment(GameState.self) private var state
    let close: () -> Void
    @State private var code = ""
    @State private var shake: CGFloat = 0
    @State private var hint = -1

    private let keys: [(String, String)] = [("1", ""), ("2", "A B C"), ("3", "D E F"), ("4", "G H I"), ("5", "J K L"), ("6", "M N O"),
                                             ("7", "P Q R S"), ("8", "T U V"), ("9", "W X Y Z")]

    var body: some View {
        ZStack {
            ArtView(art: state.story.wallpaper).blur(radius: 30).ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer().frame(height: 60)
                Image(systemName: "lock.fill").font(.system(size: 20, weight: .semibold))
                Text(T("Saisissez le code", "Enter Passcode"))
                    .font(.system(size: 20, weight: .regular))
                    .padding(.top, 14)
                HStack(spacing: 22) {
                    ForEach(0..<state.story.passcode.count, id: \.self) { i in
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 1.3)
                            .background(Circle().fill(i < code.count ? Color.white : Color.clear))
                            .frame(width: 13, height: 13)
                    }
                }
                .offset(x: shake)
                .padding(.top, 20)
                Text(hint >= 0 ? state.story.lockHints[hint] : " ")
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(height: 40)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)

                Spacer()

                VStack(spacing: 16) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 26) {
                            ForEach(0..<3) { col in
                                let k = keys[row * 3 + col]
                                KeyButton(digit: k.0, letters: k.1) { press(k.0) }
                            }
                        }
                    }
                    HStack(spacing: 26) {
                        Button {
                            withAnimation { hint = min(hint + 1, state.story.lockHints.count - 1) }
                        } label: {
                            Text(T("Indice", "Hint")).font(.system(size: 17)).frame(width: 80, height: 80)
                        }
                        KeyButton(digit: "0", letters: "") { press("0") }
                        Button {
                            if code.isEmpty { close() } else { code.removeLast() }
                        } label: {
                            Text(code.isEmpty ? T("Annuler", "Cancel") : T("Supprimer", "Delete")).font(.system(size: 17)).frame(width: 80, height: 80)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 40)
            }
            .foregroundStyle(.white)
        }
    }

    private func press(_ k: String) {
        guard code.count < state.story.passcode.count else { return }
        code += k
        if code.count == state.story.passcode.count {
            let attempt = code
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if state.tryCode(attempt) {
                    close()
                } else {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 18 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = -18 } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { shake = 0 } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { code = "" }
                }
            }
        }
    }
}

struct KeyButton: View {
    let digit: String
    let letters: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: -2) {
                Text(digit).font(.system(size: 36, weight: .regular))
                if !letters.isEmpty {
                    Text(letters).font(.system(size: 10, weight: .bold)).tracking(1.5)
                }
            }
            .frame(width: 80, height: 80)
            .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(digit)
    }
}

struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.45 : 0)))
            .animation(.easeOut(duration: configuration.isPressed ? 0.02 : 0.35), value: configuration.isPressed)
    }
}

// MARK: Accueil

struct HomeScreen: View {
    @Environment(GameState.self) private var state
    @State private var askReset = false

    private let grid: [AppKind] = [.calendar, .maps, .weather, .mail, .settings]
    private let dock: [AppKind] = [.phone, .messages, .photos, .notes]

    var body: some View {
        ZStack {
            ArtView(art: state.story.wallpaper).ignoresSafeArea()
            Color.black.opacity(0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 18)
                // Un widget : le chapitre en cours (appui long pour recommencer)
                StoryWidget()
                    .contextMenu {
                        Button(T("Recommencer l'histoire", "Restart the story"), systemImage: "arrow.counterclockwise", role: .destructive) { askReset = true }
                    }
                    .padding(.horizontal, 26)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 24) {
                    ForEach(grid) { AppIcon(app: $0) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    Text(T("Rechercher", "Search")).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 14)

                HStack(spacing: 0) {
                    ForEach(dock) { AppIcon(app: $0, label: false).frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.ultraThinMaterial))
                .environment(\.colorScheme, .dark)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
        }
        .statusBar()
        .alert(T("Pas encore", "Not yet"), isPresented: Binding(get: { state.lockedAppAlert != nil }, set: { if !$0 { state.lockedAppAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(T("Cette appli s'ouvrira au chapitre \(state.lockedAppAlert?.chapter ?? 2).", "This app opens in chapter \(state.lockedAppAlert?.chapter ?? 2)."))
        }
        .confirmationDialog(T("Tout recommencer ?", "Start over?"), isPresented: $askReset, titleVisibility: .visible) {
            Button(T("Recommencer", "Restart"), role: .destructive) { state.reset() }
        }
    }
}

/// Le widget de l'accueil : l'enquête en cours.
struct StoryWidget: View {
    @Environment(GameState.self) private var state

    var body: some View {
        let n = state.chapter
        let ch = state.story.chapters[max(0, min(n - 1, state.story.chapters.count - 1))]
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(T("ENQUÊTE", "CASE")).font(.system(size: 12, weight: .bold)).foregroundStyle(.red)
                Text(T("Chapitre \(n)", "Chapter \(n)")).font(.system(size: 13, weight: .semibold)).opacity(0.7)
                Text(ch.title).font(.system(size: 22, weight: .bold))
                Spacer(minLength: 0)
                Text(T("Ce téléphone appartient à \(state.story.owner).", "This phone belongs to \(state.story.owner)."))
                    .font(.system(size: 12, weight: .medium)).opacity(0.65)
            }
            Spacer()
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
        }
        .padding(16)
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

// MARK: Une appli ouverte (plein écran, on balaie le bas vers le haut pour revenir)

struct AppScreen: View {
    @Environment(GameState.self) private var state
    let app: AppKind
    @State private var drag: CGFloat = 0
    @State private var path: [String] = []

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                NavigationStack(path: $path) {
                    content
                        .navigationDestination(for: String.self) { destination($0) }
                }
                .tint(tint)
                .statusBar(dark: !darkApp)

                // La barre d'accueil
                Capsule()
                    .fill(darkApp ? Color.white : Color.black)
                    .frame(width: 134, height: 5)
                    .padding(.bottom, 8)
                    .frame(width: g.size.width, height: 34, alignment: .bottom)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { v in drag = min(0, v.translation.height) }
                            .onEnded { v in
                                if v.translation.height < -50 || v.predictedEndTranslation.height < -150 {
                                    state.goHome()
                                }
                                withAnimation(.spring(duration: 0.3)) { drag = 0 }
                            }
                    )
                    .ignoresSafeArea()
                    .accessibilityLabel(T("Accueil", "Home"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { state.goHome() }
            }
            .background(darkApp ? Color.black : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: drag < 0 ? 40 : 0, style: .continuous))
            .scaleEffect(1 + drag / 1600)
            .offset(y: drag / 3)
        }
        .environment(\.colorScheme, darkApp ? .dark : .light)
        .onAppear { openPending() }
        .onChange(of: state.pendingThread) { _, _ in openPending() }
    }

    private var darkApp: Bool { app == .weather }

    private var tint: Color {
        switch app {
        case .notes: return Color(red: 0.89, green: 0.64, blue: 0.0)
        case .calendar: return .red
        case .phone, .messages: return .blue
        default: return .blue
        }
    }

    private func openPending() {
        guard let t = state.pendingThread else { return }
        state.pendingThread = nil
        path = [t]
    }

    @ViewBuilder private var content: some View {
        switch app {
        case .messages: MessagesApp().navigationTitle(app.title)
        case .photos: PhotosApp().navigationTitle(T("Photothèque", "Library"))
        case .notes: NotesApp().navigationTitle(app.title)
        case .phone: PhoneApp()
        case .calendar: CalendarApp().navigationTitle(T("Novembre", "November"))
        case .maps: MapsApp().navigationTitle(T("Trajets", "Trips"))
        case .weather: WeatherApp().toolbar(.hidden, for: .navigationBar)
        case .settings: SettingsApp().navigationTitle(app.title)
        case .mail: Text(T("Aucun e-mail", "No Mail")).foregroundStyle(.secondary).navigationTitle(app.title)
        }
    }

    /// Les écrans de détail, pour toutes les applis (une seule pile de navigation par appli).
    @ViewBuilder private func destination(_ id: String) -> some View {
        switch app {
        case .messages: ThreadView(thread: id)
        case .photos:
            if id == "album" {
                HiddenAlbumView()
            } else if let p = (state.story.photos + (state.story.hiddenAlbum?.photos ?? [])).first(where: { $0.id == id }) {
                PhotoDetail(photo: p)
            }
        case .notes:
            if let n = state.story.notes.first(where: { $0.id == id }) { NoteDetail(note: n) }
        case .calendar:
            if let e = state.story.events.first(where: { $0.id == id }) { EventDetail(event: e) }
        case .maps:
            if let t = state.story.trips.first(where: { $0.id == id }) { TripDetail(trip: t) }
        case .settings:
            switch id {
            case "battery": BatteryView()
            case "location": LocationView()
            default:
                if let u = state.story.usage.first(where: { "app_" + $0.id == id }) { AppUsageDetail(usage: u) }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: Bannière (une notification qui descend du haut)

struct BannerView: View {
    @Environment(GameState.self) private var state
    let message: Message
    @State private var drag: CGFloat = 0

    var body: some View {
        let contact = state.story.contact(state.story.conversations.first { $0.id == message.thread }?.contact ?? message.thread)
        NotificationCard(message: message, contact: contact, when: T("maintenant", "now"))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .padding(.horizontal, 8)
            .offset(y: min(0, drag))
            .onTapGesture {
                state.banner = nil
                state.pendingThread = message.thread
                state.launch(.messages)
            }
            .gesture(
                DragGesture()
                    .onChanged { v in drag = v.translation.height }
                    .onEnded { v in
                        if v.translation.height < -30 { state.banner = nil }
                        withAnimation(.spring) { drag = 0 }
                    }
            )
            .accessibilityAddTraits(.isButton)
    }
}
