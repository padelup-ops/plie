import SwiftUI

// MARK: - Les applis du téléphone, au style iOS : Messages, Photos, Notes, Téléphone

let bubbleBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
let bubbleGrey = Color(red: 0.91, green: 0.91, blue: 0.92)

// MARK: Messages

struct MessagesApp: View {
    @Environment(GameState.self) private var state
    @State private var search = ""

    var body: some View {
        List {
            ForEach(state.threadOrder.filter(matches), id: \.self) { id in
                if let conv = state.story.conversations.first(where: { $0.id == id }) {
                    let contact = state.story.contact(conv.contact)
                    let last = state.lastMessage(in: id)
                    NavigationLink(value: id) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(state.unread(id) ? bubbleBlue : .clear).frame(width: 10, height: 10).padding(.top, 20)
                                .padding(.leading, -12)
                            Avatar(contact: contact, size: 50)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(contact.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Text(last.map(shortTime) ?? "").font(.system(size: 15)).foregroundStyle(.secondary)
                                }
                                Text(preview(last))
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: T("Rechercher", "Search"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Text(T("Modifier", "Edit")).foregroundStyle(bubbleBlue) }
            ToolbarItem(placement: .topBarTrailing) { Image(systemName: "square.and.pencil").foregroundStyle(bubbleBlue) }
        }
    }

    private func matches(_ id: String) -> Bool {
        guard !search.isEmpty, let conv = state.story.conversations.first(where: { $0.id == id }) else { return true }
        return state.story.contact(conv.contact).name.localizedCaseInsensitiveContains(search)
            || state.messages(in: id).contains { $0.text.localizedCaseInsensitiveContains(search) }
    }

    private func preview(_ m: Message?) -> String {
        guard let m else { return "" }
        if m.photo != nil && m.text.isEmpty { return T("1 photo", "1 Photo") }
        return m.text
    }
}

/// « Ven. 17:52 » → « Ven. », « 07:58 » → « 07:58 » (comme la liste de Messages).
func shortTime(_ m: Message) -> String {
    let parts = m.time.split(separator: " ")
    return parts.count > 1 ? String(parts[0]) : m.time
}

struct ThreadView: View {
    @Environment(GameState.self) private var state
    let thread: String

    var body: some View {
        let messages = state.messages(in: thread)
        let choices = state.choices(in: thread)
        let contactID = state.story.conversations.first { $0.id == thread }?.contact ?? thread
        let contact = state.story.contact(contactID)
        let lastMine = messages.lastIndex { $0.fromMe }
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        Text(T("Message texte", "Text Message"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                            let prev = i > 0 ? messages[i - 1] : nil
                            let next = i + 1 < messages.count ? messages[i + 1] : nil
                            if prev == nil || prev!.time.split(separator: " ").first != m.time.split(separator: " ").first || m.time == T("maintenant", "now") && prev!.time != m.time {
                                TimeSeparator(time: m.time)
                            }
                            Bubble(message: m, tail: next == nil || next!.fromMe != m.fromMe, gapAbove: prev != nil && prev!.fromMe != m.fromMe)
                                .id(m.id)
                            if i == lastMine && i == messages.count - 1 {
                                Text(T("Distribué", "Delivered"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.trailing, 6)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    state.markRead(thread)
                }
            }

            InputBar(choices: choices) { state.send($0) }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Avatar(contact: contact, size: 38)
                    HStack(spacing: 2) {
                        Text(contact.name).font(.system(size: 11, weight: .regular))
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .padding(.top, 6)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "video").foregroundStyle(bubbleBlue)
            }
        }
        .onAppear {
            state.openThread = thread
            state.markRead(thread)
            state.set("read_thread_" + thread)
        }
        .onDisappear { if state.openThread == thread { state.openThread = nil } }
    }
}

struct TimeSeparator: View {
    let time: String

    var body: some View {
        let parts = time.split(separator: " ", maxSplits: 1)
        Group {
            if parts.count == 2 {
                Text(String(parts[0])).fontWeight(.semibold) + Text(" " + String(parts[1]))
            } else {
                Text(time).fontWeight(.semibold)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

struct Bubble: View {
    @Environment(GameState.self) private var state
    let message: Message
    let tail: Bool
    let gapAbove: Bool

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 60) }
            VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 2) {
                if let pid = message.photo, let p = state.story.photos.first(where: { $0.id == pid }) {
                    ArtView(art: p.art)
                        .frame(width: 210, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 17))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(
                            BubbleShape(fromMe: message.fromMe, tail: tail)
                                .fill(message.fromMe ? bubbleBlue : bubbleGrey)
                        )
                        .foregroundStyle(message.fromMe ? Color.white : Color.black)
                        .textSelection(.enabled)
                }
            }
            if !message.fromMe { Spacer(minLength: 60) }
        }
        .padding(.top, gapAbove ? 8 : 0)
        .padding(.bottom, tail ? 4 : 0)
        .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: message.fromMe ? .bottomTrailing : .bottomLeading).combined(with: .opacity), removal: .opacity))
    }
}

/// Une bulle avec sa petite queue, comme dans Messages.
struct BubbleShape: Shape {
    let fromMe: Bool
    let tail: Bool

    func path(in r: CGRect) -> Path {
        let radius: CGFloat = min(18, r.height / 2)
        var p = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        guard tail else { return p }
        var t = Path()
        if fromMe {
            t.move(to: CGPoint(x: r.maxX - 12, y: r.maxY - 16))
            t.addCurve(to: CGPoint(x: r.maxX + 5, y: r.maxY), control1: CGPoint(x: r.maxX - 4, y: r.maxY - 2), control2: CGPoint(x: r.maxX + 2, y: r.maxY))
            t.addCurve(to: CGPoint(x: r.maxX - 14, y: r.maxY - 2), control1: CGPoint(x: r.maxX - 4, y: r.maxY + 1), control2: CGPoint(x: r.maxX - 10, y: r.maxY))
        } else {
            t.move(to: CGPoint(x: r.minX + 12, y: r.maxY - 16))
            t.addCurve(to: CGPoint(x: r.minX - 5, y: r.maxY), control1: CGPoint(x: r.minX + 4, y: r.maxY - 2), control2: CGPoint(x: r.minX - 2, y: r.maxY))
            t.addCurve(to: CGPoint(x: r.minX + 14, y: r.maxY - 2), control1: CGPoint(x: r.minX + 4, y: r.maxY + 1), control2: CGPoint(x: r.minX + 10, y: r.maxY))
        }
        p.addPath(t)
        return p
    }
}

/// La barre de saisie. Le joueur ne tape pas : il choisit une des réponses proposées.
struct InputBar: View {
    let choices: [ReplyChoice]
    let send: (ReplyChoice) -> Void
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            if open && !choices.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(choices) { c in
                        Button {
                            open = false
                            send(c)
                        } label: {
                            Text(c.text)
                                .font(.system(size: 16))
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(BubbleShape(fromMe: true, tail: false).stroke(bubbleBlue, lineWidth: 1.2))
                                .foregroundStyle(bubbleBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.systemGray5)))
                Button {
                    withAnimation(.spring(duration: 0.3)) { open.toggle() }
                } label: {
                    HStack {
                        Text(choices.isEmpty ? T("Message", "Message") : (open ? T("Choisis une réponse", "Pick a reply") : T("Répondre…", "Reply…")))
                            .foregroundStyle(choices.isEmpty ? Color(.placeholderText) : bubbleBlue)
                        Spacer()
                        Image(systemName: choices.isEmpty ? "mic" : "arrow.up.circle.fill")
                            .font(.system(size: choices.isEmpty ? 17 : 26))
                            .foregroundStyle(choices.isEmpty ? Color(.secondaryLabel) : bubbleBlue)
                    }
                    .font(.system(size: 17))
                    .padding(.leading, 12).padding(.trailing, 4)
                    .frame(height: 36)
                    .background(Capsule().stroke(Color(.systemGray4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(choices.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(.bar)
        .onChange(of: choices.count) { old, new in if new > old { withAnimation { open = true } } }
    }
}

// MARK: Photos

struct PhotosApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3), spacing: 1.5) {
                ForEach(state.story.photos.reversed()) { p in
                    NavigationLink(value: p.id) {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(ArtView(art: p.art))
                            .clipped()
                    }
                    .accessibilityLabel(p.date + ", " + p.place)
                }
            }
            Text(T("\(state.story.photos.count) photos", "\(state.story.photos.count) Photos"))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)

            if let album = state.story.hiddenAlbum, state.chapter >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    Text(T("Albums", "Albums")).font(.system(size: 22, weight: .bold))
                    Text(T("Utilitaires", "Utilities")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    NavigationLink(value: "album") {
                        HStack(spacing: 12) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 20))
                                .foregroundStyle(bubbleBlue)
                                .frame(width: 30)
                            Text(album.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: state.albumOpen ? "chevron.right" : "lock.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
            }
            Spacer().frame(height: 40)
        }
        .defaultScrollAnchor(.bottom)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(T("Sélect.", "Select"))
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
        }
    }
}

struct PhotoDetail: View {
    @Environment(GameState.self) private var state
    let photo: PhotoItem
    @State private var flipped = false
    @State private var liked = false
    @State private var info = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    ArtView(art: photo.art)
                        .overlay {
                            if let c = photo.car {
                                GeometryReader { g in
                                    GreyCar(plate: state.story.hiddenAlbum?.plate ?? "", showPlate: state.has("car_" + photo.id))
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
                    Rectangle()
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
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .onTapGesture(count: 2) { flip() }

                if photo.car != nil && state.has("car_" + photo.id) {
                    Text(T("Plaque relevée : \(state.story.hiddenAlbum?.plate ?? "") (\(state.carsSpotted)/\(state.carsTotal))",
                           "Plate noted: \(state.story.hiddenAlbum?.plate ?? "") (\(state.carsSpotted)/\(state.carsTotal))"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.top, 12)
                }
                if info {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(photo.date).font(.headline)
                        Label(photo.place, systemImage: "mappin.and.ellipse").font(.subheadline)
                        Text("iPhone · 26 mm f/1.6").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.15)))
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer()
                // La barre d'outils du bas
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Spacer()
                    Button { liked.toggle() } label: { Image(systemName: liked ? "heart.fill" : "heart") }
                    Spacer()
                    Button { withAnimation { info.toggle() } } label: { Image(systemName: info ? "info.circle.fill" : "info.circle") }
                    Spacer()
                    if photo.back != nil {
                        Button { flip() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                            .accessibilityLabel(T("Retourner la photo", "Turn the photo over"))
                        Spacer()
                    }
                    Image(systemName: "trash")
                }
                .font(.system(size: 21))
                .foregroundStyle(bubbleBlue)
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(photo.date).font(.system(size: 15, weight: .semibold))
                    Text(photo.place).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
        }
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .statusBar()
        .onAppear {
            // La première fois, montrer qu'une photo peut se retourner
            if photo.back != nil && !state.has("seen_back_" + photo.id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation(.spring(duration: 0.5)) { info = true } }
            }
        }
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
    @State private var search = ""

    var body: some View {
        let notes = state.story.notes
            .filter { n in n.requires.map { state.has($0) } ?? true }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
        let pinned = notes.filter(\.pinned), others = notes.filter { !$0.pinned }
        List {
            if !pinned.isEmpty {
                Section { ForEach(pinned) { NoteRow(note: $0) } } header: {
                    Label(T("Épinglées", "Pinned"), systemImage: "pin.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).textCase(nil)
                }
            }
            Section {
                ForEach(others) { NoteRow(note: $0) }
            } header: {
                Text(T("30 jours précédents", "Previous 30 Days")).font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: T("Rechercher", "Search"))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Text(T("\(notes.count) notes", "\(notes.count) Notes")).font(.system(size: 11))
                Spacer()
            }
            .overlay(alignment: .trailing) { Image(systemName: "square.and.pencil").font(.system(size: 20)).padding(.trailing, 20) }
            .padding(.top, 10).padding(.bottom, 34)
            .background(.bar)
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        NavigationLink(value: note.id) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                (Text(note.date + "  ").foregroundStyle(.primary) + Text(note.body.replacingOccurrences(of: "\n", with: " ")).foregroundStyle(.secondary))
                    .font(.system(size: 15))
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
        }
    }
}

struct NoteDetail: View {
    @Environment(GameState.self) private var state
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(note.date).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Text(note.title).font(.system(size: 28, weight: .bold))
                Text(note.body).font(.system(size: 17)).lineSpacing(3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "checklist"); Spacer()
                Image(systemName: "paperclip"); Spacer()
                Image(systemName: "pencil.tip.crop.circle"); Spacer()
                Image(systemName: "square.and.pencil")
            }
            .font(.system(size: 20))
            .foregroundStyle(Color(red: 0.89, green: 0.64, blue: 0.0))
            .padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 34)
            .background(.bar)
        }
        .onAppear {
            // Laisser le temps de lire avant la fin du chapitre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { state.set("read_" + note.id) }
        }
    }
}

// MARK: Téléphone

struct PhoneApp: View {
    @Environment(GameState.self) private var state
    @State private var tab = 1

    private var tabs: [(String, String)] {
        [(T("Favoris", "Favorites"), "star.fill"), (T("Récents", "Recents"), "clock.fill"), (T("Contacts", "Contacts"), "person.crop.circle.fill"),
         (T("Clavier", "Keypad"), "circle.grid.3x3.fill"), (T("Messagerie", "Voicemail"), "recordingtape")]
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case 0: favorites
                case 1: recents
                case 2: contacts
                case 3: Keypad()
                default: voicemail
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                ForEach(tabs.indices, id: \.self) { i in
                    Button { tab = i } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tabs[i].1).font(.system(size: 21))
                                .overlay(alignment: .topTrailing) {
                                    if i == 4 && unheard > 0 {
                                        Text("\(unheard)").font(.system(size: 12)).foregroundStyle(.white)
                                            .frame(minWidth: 18, minHeight: 18).background(Circle().fill(.red)).offset(x: 10, y: -6)
                                    }
                                }
                            Text(tabs[i].0).font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(tab == i ? bubbleBlue : Color(.systemGray))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8).padding(.bottom, 30)
            .background(.bar)
        }
        .navigationTitle(tabs[tab].0)
        .navigationBarTitleDisplayMode(tab == 3 ? .inline : .large)
    }

    private var visibleVoicemails: [Voicemail] { state.story.voicemails.filter { v in v.requires.map { state.has($0) } ?? true } }
    private var unheard: Int { visibleVoicemails.filter { !state.has("heard_" + $0.id) }.count }

    private var favorites: some View {
        List {
            ForEach(["maman", "ines"], id: \.self) { id in
                let c = state.story.contact(id)
                HStack(spacing: 12) {
                    Avatar(contact: c, size: 40)
                    VStack(alignment: .leading) {
                        Text(c.name).font(.system(size: 17, weight: .semibold))
                        Label(T("mobile", "mobile"), systemImage: "phone.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(bubbleBlue)
                }
            }
        }
        .listStyle(.plain)
    }

    /// Les appels manqués de ces trois jours.
    private var recents: some View {
        let calls: [(String, Int, String)] = [("maman", 6, "07:31"), ("ines", 4, "07:59"), ("samir", 1, "08:06"), ("h", 9, T("hier", "Yesterday")),
                                               ("maman", 3, T("hier", "Yesterday")), ("ines", 2, T("samedi", "Saturday")), ("h", 14, T("samedi", "Saturday"))]
        return List {
            ForEach(calls.indices, id: \.self) { i in
                let c = state.story.contact(calls[i].0)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name + (calls[i].1 > 1 ? " (\(calls[i].1))" : ""))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.red)
                        Text(T("Appel manqué", "Missed call")).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(calls[i].2).font(.system(size: 15)).foregroundStyle(.secondary)
                    Image(systemName: "info.circle").foregroundStyle(bubbleBlue)
                }
            }
        }
        .listStyle(.plain)
    }

    private var contacts: some View {
        List {
            ForEach(state.story.contacts.sorted { $0.name < $1.name }) { c in
                HStack(spacing: 12) {
                    Avatar(contact: c, size: 36)
                    Text(c.name).font(.system(size: 17))
                }
            }
        }
        .listStyle(.plain)
    }

    private var voicemail: some View {
        List {
            ForEach(visibleVoicemails) { VoicemailRow(voicemail: $0) }
        }
        .listStyle(.plain)
    }
}

struct Keypad: View {
    @State private var number = ""
    private let keys: [(String, String)] = [("1", ""), ("2", "A B C"), ("3", "D E F"), ("4", "G H I"), ("5", "J K L"), ("6", "M N O"),
                                             ("7", "P Q R S"), ("8", "T U V"), ("9", "W X Y Z"), ("*", ""), ("0", "+"), ("#", "")]

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(number.isEmpty ? " " : number).font(.system(size: 36)).frame(height: 44)
            ForEach(0..<4) { r in
                HStack(spacing: 26) {
                    ForEach(0..<3) { c in
                        let k = keys[r * 3 + c]
                        Button { if number.count < 14 { number += k.0 } } label: {
                            VStack(spacing: -2) {
                                Text(k.0).font(.system(size: 34))
                                if !k.1.isEmpty { Text(k.1).font(.system(size: 9, weight: .bold)).tracking(1.5) }
                            }
                            .frame(width: 78, height: 78)
                            .background(Circle().fill(Color(.systemGray5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 26) {
                Color.clear.frame(width: 78, height: 78)
                Image(systemName: "phone.fill").font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 78, height: 78).background(Circle().fill(Color.green))
                Button { if !number.isEmpty { number.removeLast() } } label: {
                    Image(systemName: "delete.left.fill").font(.system(size: 24)).foregroundStyle(Color(.systemGray3))
                        .frame(width: 78, height: 78)
                }
                .buttonStyle(.plain)
                .opacity(number.isEmpty ? 0 : 1)
            }
            Spacer()
        }
    }
}

struct VoicemailRow: View {
    @Environment(GameState.self) private var state
    let voicemail: Voicemail
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { open.toggle() }
            } label: {
                HStack(alignment: .top) {
                    Circle().fill(state.has("heard_" + voicemail.id) ? Color.clear : bubbleBlue).frame(width: 9, height: 9).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.story.contact(voicemail.contact).name).font(.system(size: 17, weight: .semibold))
                        Text(T("mobile", "mobile")).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(voicemail.date).font(.system(size: 15)).foregroundStyle(.secondary)
                        Text(String(format: "0:%02d", voicemail.seconds)).font(.system(size: 14)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(T("Transcription", "Transcription")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Text(state.has("heard_" + voicemail.id) ? voicemail.transcript : T("Écoute le message pour voir la transcription.", "Play the message to see the transcription."))
                    .font(.system(size: 15))
                HStack(spacing: 18) {
                    Button { state.play(voicemail) } label: { Image(systemName: "play.fill").font(.system(size: 22)) }
                    ProgressView(value: 0).tint(bubbleBlue)
                    Button { state.stopVoice() } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 18)) }
                    Image(systemName: "phone.fill").foregroundStyle(.green)
                }
                .foregroundStyle(bubbleBlue)
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
