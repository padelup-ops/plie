import SwiftUI

// MARK: - Le faux téléphone : écran verrouillé, accueil, applis

private let ink = Color(red: 0.07, green: 0.07, blue: 0.1)

// MARK: Écran verrouillé

struct LockScreen: View {
    @Environment(GameState.self) private var state
    @State private var showPad = false
    @State private var hintIndex = -1

    var body: some View {
        ZStack {
            ArtView(art: state.story.wallpaper).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 18, weight: .semibold)).padding(.top, 24)
                Text(T("lundi 3 novembre", "Monday, November 3"))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("8:12")
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, -10)

                VStack(spacing: 8) {
                    ForEach(state.story.lockNotifications) { m in
                        NotificationRow(message: m, contact: state.story.contact(m.thread))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()

                if hintIndex >= 0 {
                    Text(state.story.lockHints[hintIndex])
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 30)
                        .transition(.opacity)
                }

                HStack(spacing: 14) {
                    Button {
                        withAnimation { hintIndex = min(hintIndex + 1, state.story.lockHints.count - 1) }
                    } label: {
                        Label(T("Indice", "Hint"), systemImage: "lightbulb.fill")
                            .font(.system(.callout, design: .rounded, weight: .bold))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Button {
                        showPad = true
                    } label: {
                        Label(T("Déverrouiller", "Unlock"), systemImage: "lock.open.fill")
                            .font(.system(.callout, design: .rounded, weight: .bold))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Color.white, in: Capsule())
                            .foregroundStyle(ink)
                    }
                }
                .padding(.bottom, 30)
            }
            .foregroundStyle(.white)

            if showPad {
                PasscodePad(close: { showPad = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showPad)
    }
}

struct NotificationRow: View {
    let message: Message
    let contact: Contact

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(contact: contact, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contact.name).font(.system(.subheadline, weight: .bold))
                    Spacer()
                    Text(message.time).font(.caption).opacity(0.7)
                }
                Text(message.text).font(.subheadline).lineLimit(2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }
}

struct PasscodePad: View {
    @Environment(GameState.self) private var state
    let close: () -> Void
    @State private var code = ""
    @State private var shake = 0.0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Text(T("Saisir le code", "Enter Passcode")).font(.system(size: 20, weight: .semibold))
                HStack(spacing: 18) {
                    ForEach(0..<4) { i in
                        Circle()
                            .strokeBorder(.white, lineWidth: 1.5)
                            .background(Circle().fill(i < code.count ? Color.white : .clear))
                            .frame(width: 14, height: 14)
                    }
                }
                .offset(x: shake)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(82), spacing: 22), count: 3), spacing: 18) {
                    ForEach(keys, id: \.self) { k in
                        if k.isEmpty {
                            Color.clear.frame(width: 78, height: 78)
                        } else {
                            Button { press(k) } label: {
                                Text(k)
                                    .font(.system(size: k == "⌫" ? 26 : 34, weight: .regular))
                                    .frame(width: 78, height: 78)
                                    .background(Circle().fill(Color.white.opacity(k == "⌫" ? 0 : 0.18)))
                            }
                            .accessibilityLabel(k == "⌫" ? T("Effacer", "Delete") : k)
                        }
                    }
                }
                .padding(.top, 10)
                Spacer()
                Button(T("Annuler", "Cancel"), action: close)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
    }

    private func press(_ k: String) {
        if k == "⌫" { if !code.isEmpty { code.removeLast() }; return }
        guard code.count < 4 else { return }
        code += k
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if code.count == 4 {
            if state.tryCode(code) {
                close()
            } else {
                withAnimation(.default) { shake = 14 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { withAnimation(.default) { shake = -14 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { withAnimation(.default) { shake = 0 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { code = "" }
            }
        }
    }
}

// MARK: Écran d'accueil

struct HomeScreen: View {
    @Environment(GameState.self) private var state
    @State private var askReset = false

    var body: some View {
        ZStack {
            ArtView(art: state.story.wallpaper).ignoresSafeArea().blur(radius: 18)
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(T("Chapitre \(state.chapter)", "Chapter \(state.chapter)"))
                        .font(.system(.footnote, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Menu {
                        Button(T("Recommencer l'histoire", "Restart the story"), systemImage: "arrow.counterclockwise", role: .destructive) { askReset = true }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill").font(.system(size: 26))
                    }
                    .accessibilityLabel(T("Options", "Options"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 26) {
                    ForEach(AppKind.allCases) { app in
                        AppIcon(app: app, locked: app.chapter > state.chapter, badge: badge(app)) {
                            if app.chapter > state.chapter {
                                if state.needsPurchase { state.showPaywall = true } else { state.lockedAppAlert = app }
                            } else {
                                state.openApp = app
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 30)

                Spacer()

                Text(T("Ce téléphone appartient à \(state.story.owner).", "This phone belongs to \(state.story.owner)."))
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .opacity(0.8)
                    .padding(.bottom, 24)
            }
            .foregroundStyle(.white)
        }
        .alert(T("Pas encore", "Not yet"), isPresented: Binding(get: { state.lockedAppAlert != nil }, set: { if !$0 { state.lockedAppAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(T("Cette appli s'ouvrira au chapitre \(state.lockedAppAlert?.chapter ?? 2).", "This app opens in chapter \(state.lockedAppAlert?.chapter ?? 2)."))
        }
        .confirmationDialog(T("Tout recommencer ?", "Start over?"), isPresented: $askReset, titleVisibility: .visible) {
            Button(T("Recommencer", "Restart"), role: .destructive) { state.reset() }
        }
    }

    private func badge(_ app: AppKind) -> Int {
        guard app == .messages else { return 0 }
        return state.story.conversations.filter { state.unread($0.id) }.count
    }
}

struct AppIcon: View {
    let app: AppKind
    let locked: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: app.colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: app.symbol)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(app == .calendar ? Color.red : .white)
                        )
                        .overlay {
                            if locked {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.45))
                                Image(systemName: "lock.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                    if badge > 0 && !locked {
                        Text("\(badge)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Circle().fill(Color.red))
                            .offset(x: 6, y: -6)
                    }
                }
                Text(app.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? app.title + ", " + T("verrouillée", "locked") : app.title)
    }
}

struct Avatar: View {
    let contact: Contact
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [contact.color.opacity(0.85), contact.color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Text(contact.initials).font(.system(size: size * 0.42, weight: .semibold, design: .rounded)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

// MARK: Une appli ouverte

struct AppContainer: View {
    @Environment(GameState.self) private var state
    let app: AppKind

    var body: some View {
        NavigationStack {
            Group {
                switch app {
                case .messages: MessagesApp()
                case .photos: PhotosApp()
                case .notes: NotesApp()
                case .phone: PhoneApp()
                case .calendar: CalendarApp()
                default: Text(T("Bientôt", "Soon"))
                }
            }
            .navigationTitle(app.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.stopVoice()
                        state.openApp = nil
                    } label: {
                        Label(T("Accueil", "Home"), systemImage: "house.fill")
                    }
                }
            }
        }
    }
}

// MARK: Messages

struct MessagesApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        List(state.threadOrder, id: \.self) { id in
            if let conv = state.story.conversations.first(where: { $0.id == id }) {
                let contact = state.story.contact(conv.contact)
                NavigationLink(value: id) {
                    HStack(spacing: 12) {
                        Circle().fill(state.unread(id) ? Color.blue : .clear).frame(width: 9, height: 9)
                        Avatar(contact: contact)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(contact.name).font(.system(.body, weight: .semibold))
                                Spacer()
                                Text(state.lastMessage(in: id)?.time ?? "").font(.footnote).foregroundStyle(.secondary)
                            }
                            Text(preview(state.lastMessage(in: id)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { ThreadView(thread: $0) }
    }

    private func preview(_ m: Message?) -> String {
        guard let m else { return "" }
        if m.photo != nil && m.text.isEmpty { return T("Photo", "Photo") }
        return m.text
    }
}

struct ThreadView: View {
    @Environment(GameState.self) private var state
    let thread: String

    var body: some View {
        let messages = state.messages(in: thread)
        let choices = state.choices(in: thread)
        let contactID = state.story.conversations.first { $0.id == thread }?.contact ?? thread
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(messages) { m in
                            Bubble(message: m).id(m.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    state.markRead(thread)
                }
            }

            if !choices.isEmpty {
                VStack(spacing: 8) {
                    Text(T("Répondre", "Reply"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(choices) { c in
                        Button { state.send(c) } label: {
                            Text(c.text)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.12)))
                                .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(.bar)
            }
        }
        .navigationTitle(state.story.contact(contactID).name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            state.openThread = thread
            state.markRead(thread)
            state.set("read_thread_" + thread)
        }
        .onDisappear { if state.openThread == thread { state.openThread = nil } }
    }
}

struct Bubble: View {
    @Environment(GameState.self) private var state
    let message: Message

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 50) }
            VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 4) {
                if let pid = message.photo, let p = state.story.photos.first(where: { $0.id == pid }) {
                    ArtView(art: p.art)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 18).fill(message.fromMe ? Color.blue : Color(.systemGray5)))
                        .foregroundStyle(message.fromMe ? Color.white : Color.primary)
                }
                Text(message.time).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if !message.fromMe { Spacer(minLength: 50) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: Photos

struct PhotosApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        ScrollView {
            if let album = state.story.hiddenAlbum, state.chapter >= 2 {
                NavigationLink(value: "album") {
                    HStack(spacing: 12) {
                        Image(systemName: state.albumOpen ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title).font(.body.weight(.semibold))
                            Text(state.albumOpen ? T("\(album.photos.count) photos", "\(album.photos.count) photos") : T("Verrouillé", "Locked"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: state.albumOpen ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(state.story.photos) { p in
                    NavigationLink(value: p.id) {
                        ArtView(art: p.art)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    }
                    .accessibilityLabel(p.date + ", " + p.place)
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            if id == "album" {
                HiddenAlbumView()
            } else if let p = (state.story.photos + (state.story.hiddenAlbum?.photos ?? [])).first(where: { $0.id == id }) {
                PhotoDetail(photo: p)
            }
        }
    }
}

struct PhotoDetail: View {
    @Environment(GameState.self) private var state
    let photo: PhotoItem
    @State private var flipped = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                ArtView(art: photo.art)
                    .overlay {
                        if let c = photo.car {
                            GeometryReader { g in
                                let spotted = state.has("car_" + photo.id)
                                GreyCar(plate: state.story.hiddenAlbum?.plate ?? "", showPlate: spotted)
                                    .frame(width: g.size.width * 0.3, height: g.size.width * 0.15)
                                    .position(x: c.x * g.size.width, y: c.y * g.size.height)
                                    .onTapGesture { state.spotCar(on: photo) }
                                    .accessibilityLabel(T("Une voiture grise", "A grey car"))
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                    .opacity(flipped ? 0 : 1)
                // Le dos de la photo, écrit à la main
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.97, green: 0.95, blue: 0.9))
                    .overlay(
                        Text(photo.back ?? "")
                            .font(.custom("Noteworthy-Bold", size: 24))
                            .foregroundStyle(Color(red: 0.2, green: 0.25, blue: 0.5))
                            .multilineTextAlignment(.center)
                            .padding(24)
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    )
                    .opacity(flipped ? 1 : 0)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .padding(.horizontal, 20)
            .onTapGesture { flip() }
            .accessibilityAddTraits(.isButton)

            VStack(spacing: 4) {
                Text(photo.date).font(.headline)
                Text(photo.place).font(.subheadline).foregroundStyle(.secondary)
                if photo.car != nil && state.has("car_" + photo.id) {
                    Text(T("Plaque relevée : \(state.story.hiddenAlbum?.plate ?? "") (\(state.carsSpotted)/\(state.carsTotal))",
                           "Plate noted: \(state.story.hiddenAlbum?.plate ?? "") (\(state.carsSpotted)/\(state.carsTotal))"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            if photo.back != nil {
                Button { flip() } label: {
                    Label(flipped ? T("Voir la photo", "See the photo") : T("Retourner la photo", "Turn the photo over"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func flip() {
        guard photo.back != nil else { return }
        withAnimation(.spring(duration: 0.6)) { flipped.toggle() }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        state.set("seen_back_" + photo.id)
    }
}

// MARK: Notes

struct NotesApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        let notes = state.story.notes
            .filter { n in n.requires.map { state.has($0) } ?? true }
            .sorted { $0.pinned && !$1.pinned }
        List(notes) { n in
            NavigationLink(value: n.id) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        if n.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption) }
                        Text(n.title).font(.body.weight(.semibold))
                    }
                    Text(n.date + "  " + n.body.replacingOccurrences(of: "\n", with: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationDestination(for: String.self) { id in
            if let n = state.story.notes.first(where: { $0.id == id }) { NoteDetail(note: n) }
        }
    }
}

struct NoteDetail: View {
    @Environment(GameState.self) private var state
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(note.date).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Text(note.title).font(.title2.weight(.bold))
                Text(note.body).font(.body)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 1.0, green: 0.99, blue: 0.94))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Laisser le temps de lire avant la fin du chapitre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { state.set("read_" + note.id) }
        }
    }
}

// MARK: Téléphone

struct PhoneApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        List {
            Section(T("Messagerie", "Voicemail")) {
                ForEach(state.story.voicemails) { v in
                    VoicemailRow(voicemail: v)
                }
            }
            Section(T("Contacts", "Contacts")) {
                ForEach(state.story.contacts) { c in
                    HStack(spacing: 12) {
                        Avatar(contact: c, size: 36)
                        Text(c.name)
                        Spacer()
                        Image(systemName: "phone.fill").foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

struct VoicemailRow: View {
    @Environment(GameState.self) private var state
    let voicemail: Voicemail
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { open.toggle() }
            } label: {
                HStack {
                    if !state.has("heard_" + voicemail.id) { Circle().fill(Color.blue).frame(width: 8, height: 8) }
                    VStack(alignment: .leading) {
                        Text(state.story.contact(voicemail.contact).name).font(.body.weight(.semibold))
                        Text(voicemail.date).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "0:%02d", voicemail.seconds)).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            if open {
                HStack {
                    Button {
                        state.play(voicemail)
                    } label: {
                        Label(T("Écouter", "Play"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        state.stopVoice()
                    } label: {
                        Label(T("Stop", "Stop"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Text(voicemail.transcript)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Bannière et fin de chapitre

struct BannerView: View {
    @Environment(GameState.self) private var state
    let message: Message

    var body: some View {
        Button {
            state.banner = nil
            state.openApp = .messages
        } label: {
            NotificationRow(message: message, contact: state.story.contact(state.story.conversations.first { $0.id == message.thread }?.contact ?? message.thread))
                .environment(\.colorScheme, .dark)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

struct ChapterEndCard: View {
    @Environment(GameState.self) private var state
    let number: Int

    var body: some View {
        let chapter = state.story.chapters[max(0, min(number - 1, state.story.chapters.count - 1))]
        let last = number >= state.story.chapters.count
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(last ? T("FIN", "THE END") : T("FIN DU CHAPITRE \(number)", "END OF CHAPTER \(number)"))
                    .font(.system(.footnote, design: .rounded, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text(chapter.title)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(chapter.endText)
                    .multilineTextAlignment(.center)
                    .font(.system(.body, design: .rounded))
                if state.needsPurchase && number == state.story.freeChapters {
                    Button {
                        state.showChapterEnd = nil
                        state.showPaywall = true
                    } label: {
                        Text(T("Lire la suite", "Keep reading"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Color.white))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                    Button(T("Plus tard", "Later")) { state.showChapterEnd = nil }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        state.showChapterEnd = nil
                    } label: {
                        Text(T("Continuer", "Continue"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Color.white))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.12)))
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}
