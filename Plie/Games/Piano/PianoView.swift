import SwiftUI
import UIKit

extension Theme {
    static let piano = Color(hex: 0xC9A2FF)
}

// MARK: - Morceaux (domaine public)

struct PianoNote: Equatable {
    let midi: Int
    let beats: Double
    let start: Double
}

struct PianoSong: Identifiable {
    let id: String
    let titleKey: String
    let composer: String
    let bpm: Double
    let beatsPerBar: Int
    let notes: [PianoNote]

    var title: String { L(key: titleKey) }
    var totalBeats: Double { (notes.last.map { $0.start + $0.beats }) ?? 0 }

    /// « C5 D#5:0.5 E5:2 » : nom de note, octave, durée en temps (1 par défaut).
    init(id: String, title: String, composer: String, bpm: Double, beatsPerBar: Int, melody: String) {
        self.id = id
        self.titleKey = title
        self.composer = composer
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        var list: [PianoNote] = []
        var t = 0.0
        for token in melody.split(separator: " ") {
            let parts = token.split(separator: ":")
            guard let name = parts.first, let midi = PianoSong.midi(String(name)) else { continue }
            let beats = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
            list.append(PianoNote(midi: midi, beats: beats, start: t))
            t += beats
        }
        notes = list
    }

    static func midi(_ name: String) -> Int? {
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var chars = Array(name)
        guard let first = chars.first, let base = letters[first] else { return nil }
        chars.removeFirst()
        var value = base
        if chars.first == "#" { value += 1; chars.removeFirst() }
        guard let octave = Int(String(chars)) else { return nil }
        return 12 * (octave + 1) + value
    }

    static let all: [PianoSong] = [
        PianoSong(id: "lune", title: "Au clair de la lune", composer: "Trad.", bpm: 100, beatsPerBar: 4,
                  melody: "C5 C5 C5 D5 E5:2 D5:2 C5 E5 D5 D5 C5:4 C5 C5 C5 D5 E5:2 D5:2 C5 E5 D5 D5 C5:4 D5 D5 D5 D5 A4:2 A4:2 D5 C5 B4 A4 G4:4 C5 C5 C5 D5 E5:2 D5:2 C5 E5 D5 D5 C5:4"),
        PianoSong(id: "jacques", title: "Frère Jacques", composer: "Trad.", bpm: 110, beatsPerBar: 4,
                  melody: "C5 D5 E5 C5 C5 D5 E5 C5 E5 F5 G5:2 E5 F5 G5:2 G5:0.5 A5:0.5 G5:0.5 F5:0.5 E5 C5 G5:0.5 A5:0.5 G5:0.5 F5:0.5 E5 C5 C5 G4 C5:2 C5 G4 C5:2"),
        PianoSong(id: "maman", title: "Ah ! vous dirai-je, maman", composer: "Trad.", bpm: 100, beatsPerBar: 4,
                  melody: "C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2 G4 G4 F4 F4 E4 E4 D4:2 G4 G4 F4 F4 E4 E4 D4:2 C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2"),
        PianoSong(id: "joie", title: "Ode à la joie", composer: "Beethoven", bpm: 110, beatsPerBar: 4,
                  melody: "E5 E5 F5 G5 G5 F5 E5 D5 C5 C5 D5 E5 E5:1.5 D5:0.5 D5:2 E5 E5 F5 G5 G5 F5 E5 D5 C5 C5 D5 E5 D5:1.5 C5:0.5 C5:2 D5 D5 E5 C5 D5 E5:0.5 F5:0.5 E5 C5 D5 E5:0.5 F5:0.5 E5 D5 C5 D5 G4:2 E5 E5 F5 G5 G5 F5 E5 D5 C5 C5 D5 E5 D5:1.5 C5:0.5 C5:2"),
        PianoSong(id: "anniversaire", title: "Joyeux anniversaire", composer: "M. et P. Hill", bpm: 90, beatsPerBar: 3,
                  melody: "G4:0.75 G4:0.25 A4 G4 C5 B4:2 G4:0.75 G4:0.25 A4 G4 D5 C5:2 G4:0.75 G4:0.25 G5 E5 C5 B4 A4:2 F5:0.75 F5:0.25 E5 C5 D5 C5:2"),
        PianoSong(id: "vent", title: "Vive le vent", composer: "J. Pierpont", bpm: 120, beatsPerBar: 4,
                  melody: "E4 E4 E4:2 E4 E4 E4:2 E4 G4 C4:1.5 D4:0.5 E4:4 F4 F4 F4:1.5 F4:0.5 F4 E4 E4 E4:0.5 E4:0.5 E4 D4 D4 E4 D4:2 G4:2 E4 E4 E4:2 E4 E4 E4:2 E4 G4 C4:1.5 D4:0.5 E4:4 F4 F4 F4:1.5 F4:0.5 F4 E4 E4 E4:0.5 E4:0.5 G4 G4 F4 D4 C4:4"),
        PianoSong(id: "berceuse", title: "Berceuse", composer: "Brahms", bpm: 90, beatsPerBar: 3,
                  melody: "E4:0.5 E4:0.5 G4:2 E4:0.5 E4:0.5 G4:2 E4:0.5 G4:0.5 C5 B4:1.5 A4:0.5 A4 G4:2 D4:0.5 E4:0.5 F4 D4:2 D4:0.5 E4:0.5 F4:2 D4:0.5 F4:0.5 B4:0.5 A4:0.5 G4 B4 C5:2"),
        PianoSong(id: "elise", title: "Lettre à Élise", composer: "Beethoven", bpm: 72, beatsPerBar: 3,
                  melody: "E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 A4:1 C4:0.5 E4:0.5 A4:0.5 B4:1 E4:0.5 G#4:0.5 B4:0.5 C5:1 E4:0.5 E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 A4:1 C4:0.5 E4:0.5 A4:0.5 B4:1 E4:0.5 C5:0.5 B4:0.5 A4:2"),
    ]
}

// MARK: - Noms des notes

enum NoteName {
    static func name(_ midi: Int) -> String {
        let fr = ["Do", "Do♯", "Ré", "Ré♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
        let en = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return (Lang.shared.isEnglish ? en : fr)[midi % 12]
    }

    static func isBlack(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(midi % 12)
    }

    /// Position sur la portée de sol (0 = mi 4, ligne du bas ; 1 = fa 4, interligne…).
    static func staffStep(_ midi: Int) -> Int {
        let letter = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][midi % 12]
        let octave = midi / 12 - 1
        return octave * 7 + letter - (4 * 7 + 2)
    }
}

// MARK: - Modèle

@Observable
final class PianoModel {
    enum Mode: Int, CaseIterable, Identifiable {
        case learn, listen, free
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .learn: return L("Apprendre")
            case .listen: return L("Écouter")
            case .free: return L("Libre")
            }
        }
    }

    struct FreeNote: Identifiable, Equatable {
        let id: Int
        let midi: Int
    }

    private(set) var songIndex = 0
    private(set) var mode: Mode = .learn
    private(set) var index = 0
    private(set) var pressed: Set<Int> = []
    private(set) var lit: Set<Int> = []          // touches allumées par l'écoute
    private(set) var wrongAt: Date = .distantPast
    private(set) var finished = false
    private(set) var scrollFrom: Double = 0
    private(set) var scrollTo: Double = 0
    private(set) var scrollAt: Date = .distantPast
    private(set) var freeNotes: [FreeNote] = []
    var showNames = true
    /// Première touche blanche visible (index dans la liste des touches blanches).
    var firstWhite = 7

    @ObservationIgnored private var touchNotes: [Int: Int] = [:]
    @ObservationIgnored private var listenToken = 0
    @ObservationIgnored private var freeCounter = 0

    var song: PianoSong { PianoSong.all[songIndex] }
    var currentNote: PianoNote? { mode == .free || index >= song.notes.count ? nil : song.notes[index] }

    static let whiteKeys: [Int] = Array(PianoSynth.range).filter { !NoteName.isBlack($0) }

    func select(song i: Int) {
        songIndex = max(0, min(PianoSong.all.count - 1, i))
        restart()
    }

    func select(mode m: Mode) {
        mode = m
        restart()
    }

    func restart() {
        listenToken += 1
        for n in lit { PianoSynth.shared.noteOff(n) }
        lit = []
        index = 0
        finished = false
        moveScroll(to: 0)
        if mode == .listen { listen(from: 0, token: listenToken) }
    }

    func stopListening() {
        listenToken += 1
        for n in lit { PianoSynth.shared.noteOff(n) }
        lit = []
    }

    private func moveScroll(to beat: Double) {
        scrollFrom = displayedScroll(at: Date())
        scrollTo = beat
        scrollAt = Date()
    }

    /// Position affichée de la partition (glisse en douceur vers la note courante).
    func displayedScroll(at date: Date) -> Double {
        let t = min(1, date.timeIntervalSince(scrollAt) / 0.35)
        let e = 1 - pow(1 - t, 3)
        return scrollFrom + (scrollTo - scrollFrom) * e
    }

    // MARK: Touches

    /// Doigts posés sur le clavier : identifiant du doigt → note sous le doigt.
    func updateTouches(_ notes: [Int: Int]) {
        let before = Set(touchNotes.values)
        let after = Set(notes.values)
        for midi in before.subtracting(after) {
            PianoSynth.shared.noteOff(midi)
        }
        for (finger, midi) in notes where touchNotes[finger] != midi {
            press(midi)
        }
        touchNotes = notes
        pressed = after
    }

    private func press(_ midi: Int) {
        PianoSynth.shared.noteOn(midi, velocity: 0.85)
        switch mode {
        case .learn:
            guard let note = currentNote else { return }
            if midi == note.midi {
                index += 1
                moveScroll(to: index < song.notes.count ? song.notes[index].start : song.totalBeats)
                if index >= song.notes.count { complete() }
            } else {
                wrongAt = Date()
            }
        case .free:
            freeCounter += 1
            freeNotes.append(FreeNote(id: freeCounter, midi: midi))
            if freeNotes.count > 40 { freeNotes.removeFirst(freeNotes.count - 40) }
            moveScroll(to: Double(freeNotes.count))
        case .listen:
            break
        }
        ensureVisible(midi)
    }

    private func complete() {
        finished = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SoundPlayer.shared.play(.bloom, volume: 0.6)
            Haptics.success()
        }
    }

    // MARK: Écoute

    private func listen(from i: Int, token: Int) {
        guard token == listenToken, mode == .listen else { return }
        guard i < song.notes.count else {
            finished = true
            return
        }
        let note = song.notes[i]
        let beat = 60 / song.bpm
        index = i
        moveScroll(to: note.start)
        PianoSynth.shared.noteOn(note.midi, velocity: 0.8)
        lit = [note.midi]
        ensureVisible(note.midi)
        let duration = note.beats * beat
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.92) { [weak self] in
            guard let self, token == self.listenToken else { return }
            PianoSynth.shared.noteOff(note.midi)
            self.lit = []
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.listen(from: i + 1, token: token)
        }
    }

    // MARK: Clavier visible

    var visibleWhiteCount = 15

    func shift(by octaves: Int) {
        let maxFirst = max(0, Self.whiteKeys.count - visibleWhiteCount)
        firstWhite = max(0, min(maxFirst, firstWhite + 7 * octaves))
    }

    /// Fait défiler le clavier pour que la note soit visible.
    func ensureVisible(_ midi: Int) {
        let white = NoteName.isBlack(midi) ? midi - 1 : midi
        guard let i = Self.whiteKeys.firstIndex(of: white) else { return }
        let maxFirst = max(0, Self.whiteKeys.count - visibleWhiteCount)
        if i < firstWhite {
            withAnimation(.easeInOut(duration: 0.3)) { firstWhite = max(0, i - 2) }
        } else if i >= firstWhite + visibleWhiteCount {
            withAnimation(.easeInOut(duration: 0.3)) { firstWhite = min(maxFirst, i - visibleWhiteCount + 3) }
        }
    }

    /// Cadre le clavier sur le morceau choisi.
    func frameSong() {
        let notes = song.notes.map { NoteName.isBlack($0.midi) ? $0.midi - 1 : $0.midi }
        guard let lo = notes.min(), let hi = notes.max(),
              let a = Self.whiteKeys.firstIndex(of: lo), let b = Self.whiteKeys.firstIndex(of: hi) else { return }
        let maxFirst = max(0, Self.whiteKeys.count - visibleWhiteCount)
        let center = (a + b) / 2
        firstWhite = max(0, min(maxFirst, center - visibleWhiteCount / 2))
    }
}

// MARK: - Géométrie du clavier

struct KeyboardGeometry {
    let size: CGSize
    let first: Int
    let count: Int

    var whiteWidth: CGFloat { size.width / CGFloat(count) }
    var blackWidth: CGFloat { whiteWidth * 0.6 }
    var blackHeight: CGFloat { size.height * 0.62 }

    var whites: [(midi: Int, rect: CGRect)] {
        (0..<count).compactMap { i -> (midi: Int, rect: CGRect)? in
            let k = first + i
            guard k < PianoModel.whiteKeys.count else { return nil }
            return (midi: PianoModel.whiteKeys[k], rect: CGRect(x: CGFloat(i) * whiteWidth, y: 0, width: whiteWidth, height: size.height))
        }
    }

    var blacks: [(midi: Int, rect: CGRect)] {
        whites.compactMap { w -> (midi: Int, rect: CGRect)? in
            let m = w.midi + 1
            guard NoteName.isBlack(m), PianoSynth.range.contains(m) else { return nil }
            return (midi: m, rect: CGRect(x: w.rect.maxX - blackWidth / 2, y: 0, width: blackWidth, height: blackHeight))
        }
    }

    func key(at p: CGPoint) -> Int? {
        guard p.y >= 0, p.y <= size.height else { return nil }
        if let b = blacks.first(where: { $0.rect.contains(p) }) { return b.midi }
        return whites.first(where: { $0.rect.minX <= p.x && p.x < $0.rect.maxX })?.midi
    }
}

/// Surface multi-touch : plusieurs doigts à la fois, et le glissé d'une touche à l'autre.
struct MultiTouchSurface: UIViewRepresentable {
    let onChange: ([Int: CGPoint]) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        v.onChange = onChange
        return v
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onChange = onChange
    }

    final class TouchView: UIView {
        var onChange: (([Int: CGPoint]) -> Void)?
        private var points: [Int: CGPoint] = [:]

        private func key(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { points[key(t)] = t.location(in: self) }
            onChange?(points)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { points[key(t)] = t.location(in: self) }
            onChange?(points)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { points[key(t)] = nil }
            onChange?(points)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { points[key(t)] = nil }
            onChange?(points)
        }
    }
}

// MARK: - Écran

struct PianoView: View {
    @Environment(AppState.self) private var app
    @State private var model = PianoModel()
    @State private var hingeAngle: Double?
    /// Le choix du morceau s'ouvre sur la moitié à plat (une liste déroulante tomberait sur la charnière).
    @State private var choosingSong = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safe = proxy.safeAreaInsets
            let fold = size.height / 2
            let fallboard: CGFloat = 34
            let keysHeight = size.height - fold - fallboard - max(safe.bottom, 6)
            let visible = max(8, min(22, Int(((size.width - safe.leading - safe.trailing) / 46).rounded(.down))))
            ZStack(alignment: .topLeading) {
                Color(hex: 0x14110F)

                // Moitié haute : le pupitre et la partition
                VStack(spacing: 8) {
                    controls
                    ScoreSheet(model: model, hingeAngle: hingeAngle)
                }
                .padding(.top, safe.top + 6)
                .padding(.horizontal, max(safe.leading, safe.trailing, 12))
                .padding(.bottom, 10)
                .frame(width: size.width, height: fold)
                .background(
                    LinearGradient(colors: [Color(hex: 0x2A1C14), Color(hex: 0x3B271B)], startPoint: .top, endPoint: .bottom)
                )

                // Moitié basse : le clavier
                VStack(spacing: 0) {
                    Fallboard(model: model, height: fallboard)
                    KeyboardView(model: model, visible: visible)
                        .frame(height: max(80, keysHeight))
                        .padding(.horizontal, max(safe.leading, safe.trailing))
                    Color(hex: 0x14110F).frame(height: max(safe.bottom, 6))
                }
                .frame(width: size.width)
                .offset(y: fold)

                if choosingSong {
                    songChooser
                        .padding(.bottom, max(safe.bottom, 6))
                        .frame(width: size.width, height: size.height - fold)
                        .offset(y: fold)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                model.visibleWhiteCount = visible
                model.frameSong()
            }
            .onChange(of: visible) { _, v in
                model.visibleWhiteCount = v
                model.frameSong()
            }
        }
        .ignoresSafeArea()
        .onHingeAngle { hingeAngle = $0 }
        .onAppear {
            SoundPlayer.configureInstrumentSession()
            PianoSynth.shared.prepare()
            MusicPlayer.shared.duck(true)
        }
        .onDisappear {
            model.stopListening()
            PianoSynth.shared.stop()
            SoundPlayer.configureSession()
            MusicPlayer.shared.duck(false)
        }
    }

    private var songChooser: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L("Choisis un morceau"))
                    .font(.plie(18))
                Spacer()
                IconButton(symbol: "xmark", label: L("Fermer")) {
                    withAnimation(.easeOut(duration: 0.25)) { choosingSong = false }
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                    ForEach(Array(PianoSong.all.enumerated()), id: \.offset) { item in
                        let selected = model.song.id == item.element.id
                        Button {
                            model.select(song: item.offset)
                            model.frameSong()
                            withAnimation(.easeOut(duration: 0.25)) { choosingSong = false }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected ? "music.note" : "music.note.list")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(selected ? Theme.ink : Theme.piano)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.element.title)
                                        .font(.plie(15, weight: .heavy))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(item.element.composer)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .opacity(0.7)
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(selected ? Theme.ink : .white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.piano : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Color(hex: 0x1B1210).opacity(0.97))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
            HowToButton(game: .piano)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { choosingSong.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                    Text(model.song.title)
                        .lineLimit(1)
                    Image(systemName: choosingSong ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.plie(15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            }
            .disabled(model.mode == .free)
            .opacity(model.mode == .free ? 0.4 : 1)
            Spacer(minLength: 0)
            Picker("", selection: Binding(get: { model.mode }, set: { model.select(mode: $0) })) {
                ForEach(PianoModel.Mode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Button {
                model.showNames.toggle()
            } label: {
                Text(Lang.shared.isEnglish ? "ABC" : "Do Ré")
                    .font(.plie(13, weight: .bold))
                    .foregroundStyle(model.showNames ? Theme.ink : .white)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Capsule().fill(model.showNames ? Theme.piano : Color.black.opacity(0.35)))
            }
            .accessibilityLabel(L("Noms des notes"))
        }
    }
}

// MARK: - Partition

struct ScoreSheet: View {
    let model: PianoModel
    let hingeAngle: Double?

    var body: some View {
        // Le papier est dessiné une seule fois ; seules les notes sont redessinées (30 images par seconde
        // au plus), pour ne pas surcharger le grand écran du Duo.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            Canvas { context, size in
                draw(&context, size: size, now: now)
            }
        }
        .background(PaperBackground())
        .overlay(alignment: .center) {
            if model.finished && model.mode == .learn {
                VStack(spacing: 10) {
                    Text(L("Bravo ! Morceau joué en entier"))
                        .font(.plie(22))
                        .foregroundStyle(Color(hex: 0x2A1C14))
                    HStack(spacing: 10) {
                        SeatButton(title: L("Rejouer"), color: Theme.piano) { model.restart() }
                        SeatButton(title: L("Morceau suivant"), color: Color(hex: 0x2A1C14), textColor: .white) {
                            model.select(song: (model.songIndex + 1) % PianoSong.all.count)
                            model.frameSong()
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.85)))
                .overlay(ConfettiView().allowsHitTesting(false))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let tip = hint {
                Text(tip)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x5A4632))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0xEADFC8)))
                    .padding(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.finished)
    }

    private var hint: String? {
        guard let a = hingeAngle else { return nil }
        if a > 165 { return L("Relève l'écran du haut à 45° : il devient un pupitre") }
        if a < 95 { return L("Ouvre un peu plus le Duo pour bien voir la partition") }
        return nil
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let paper = CGRect(origin: .zero, size: size)
        var clip = context
        clip.clip(to: Path(roundedRect: paper.insetBy(dx: 2, dy: 2), cornerRadius: 9))

        let ink = Color(hex: 0x231C16)
        let gap = max(7, min(16, size.height * 0.085))
        let staffBottom = size.height * 0.62
        let left: CGFloat = gap * 5.2
        let playX = model.mode == .free ? size.width * 0.78 : left + gap * 4
        func y(ofStep s: Int) -> CGFloat { staffBottom - CGFloat(s) * gap / 2 }

        // Titre
        let title = model.mode == .free ? L("Mode libre : joue ce que tu veux") : "\(model.song.title) · \(model.song.composer)"
        clip.draw(Text(title).font(.system(size: max(12, gap * 1.15), weight: .bold, design: .serif)).foregroundColor(ink),
                  at: CGPoint(x: 14, y: gap * 1.4), anchor: .leading)
        if model.mode != .free {
            let progress = "\(min(model.index, model.song.notes.count)) / \(model.song.notes.count)"
            clip.draw(Text(progress).font(.system(size: max(11, gap), weight: .semibold, design: .rounded)).foregroundColor(ink.opacity(0.5)),
                      at: CGPoint(x: size.width - 14, y: gap * 1.4), anchor: .trailing)
        }

        // Portée et clé de sol
        var staff = Path()
        for l in 0..<5 {
            let ly = staffBottom - CGFloat(l) * gap
            staff.move(to: CGPoint(x: 10, y: ly))
            staff.addLine(to: CGPoint(x: size.width - 10, y: ly))
        }
        clip.stroke(staff, with: .color(ink.opacity(0.75)), lineWidth: 1)
        clip.draw(Text("𝄞").font(.system(size: gap * 6.4)).foregroundColor(ink),
                  at: CGPoint(x: 14 + gap * 1.2, y: staffBottom - gap * 1.6))

        // Repère de lecture
        var head = Path()
        head.move(to: CGPoint(x: playX, y: staffBottom - gap * 6))
        head.addLine(to: CGPoint(x: playX, y: staffBottom + gap * 2.5))
        clip.stroke(head, with: .color(Theme.piano.opacity(0.55)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let scroll = model.displayedScroll(at: now)
        let beatWidth = max(gap * 3.4, 34)
        let wrongFlash = max(0, 1 - now.timeIntervalSince(model.wrongAt) / 0.4)

        // Mesures
        if model.mode != .free {
            let bar = Double(model.song.beatsPerBar)
            var b = bar
            while b < model.song.totalBeats {
                let x = playX + CGFloat(b - scroll) * beatWidth - beatWidth * 0.35
                if x > left && x < size.width {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: staffBottom))
                    line.addLine(to: CGPoint(x: x, y: staffBottom - gap * 4))
                    clip.stroke(line, with: .color(ink.opacity(0.6)), lineWidth: 1)
                }
                b += bar
            }
        }

        // Notes
        let items: [(midi: Int, beats: Double, x: CGFloat, state: Int)]
        if model.mode == .free {
            let n = model.freeNotes.count
            items = model.freeNotes.enumerated().map { i, note in
                (midi: note.midi, beats: 1.0, x: playX + CGFloat(Double(i + 1) - scroll) * beatWidth, state: i == n - 1 ? 1 : 2)
            }
        } else {
            items = model.song.notes.enumerated().map { i, note in
                (midi: note.midi, beats: note.beats, x: playX + CGFloat(note.start - scroll) * beatWidth,
                 state: i < model.index ? 2 : (i == model.index ? 1 : 0))
            }
        }
        for item in items where item.x > left - gap && item.x < size.width + gap {
            let step = NoteName.staffStep(item.midi)
            let cy = y(ofStep: step)
            let color: Color
            switch item.state {
            case 2: color = Color(hex: 0x2F9E6B)
            case 1: color = wrongFlash > 0 && model.mode == .learn ? Color(hex: 0xD9483B) : Color(hex: 0xB07A1E)
            default: color = ink
            }
            if item.state == 1 {
                clip.fill(Path(ellipseIn: CGRect(x: item.x - gap * 1.6, y: cy - gap * 1.6, width: gap * 3.2, height: gap * 3.2)),
                          with: .radialGradient(Gradient(colors: [Theme.piano.opacity(0.55), .clear]), center: CGPoint(x: item.x, y: cy),
                                                startRadius: 0, endRadius: gap * 1.6))
            }
            // Lignes supplémentaires
            if step <= -2 {
                for s in stride(from: -2, through: step, by: -2) {
                    var l = Path()
                    l.move(to: CGPoint(x: item.x - gap * 1.0, y: y(ofStep: s)))
                    l.addLine(to: CGPoint(x: item.x + gap * 1.0, y: y(ofStep: s)))
                    clip.stroke(l, with: .color(ink.opacity(0.75)), lineWidth: 1)
                }
            }
            if step >= 10 {
                for s in stride(from: 10, through: step, by: 2) {
                    var l = Path()
                    l.move(to: CGPoint(x: item.x - gap * 1.0, y: y(ofStep: s)))
                    l.addLine(to: CGPoint(x: item.x + gap * 1.0, y: y(ofStep: s)))
                    clip.stroke(l, with: .color(ink.opacity(0.75)), lineWidth: 1)
                }
            }
            // Tête de note
            let open = item.beats >= 2
            var headCtx = clip
            headCtx.translateBy(x: item.x, y: cy)
            headCtx.rotate(by: .degrees(-20))
            let headRect = CGRect(x: -gap * 0.66, y: -gap * 0.48, width: gap * 1.32, height: gap * 0.96)
            if open {
                headCtx.stroke(Path(ellipseIn: headRect.insetBy(dx: gap * 0.08, dy: gap * 0.08)), with: .color(color), lineWidth: gap * 0.2)
            } else {
                headCtx.fill(Path(ellipseIn: headRect), with: .color(color))
            }
            // Hampe et crochets
            if item.beats < 4 {
                let up = step < 4
                let sx = up ? item.x + gap * 0.6 : item.x - gap * 0.6
                var stem = Path()
                stem.move(to: CGPoint(x: sx, y: cy))
                stem.addLine(to: CGPoint(x: sx, y: cy + (up ? -gap * 3.3 : gap * 3.3)))
                clip.stroke(stem, with: .color(color), lineWidth: max(1.2, gap * 0.12))
                let flags = item.beats <= 0.25 ? 2 : (item.beats <= 0.75 ? 1 : 0)
                for f in 0..<flags {
                    let fy = cy + (up ? -gap * 3.3 : gap * 3.3) + CGFloat(f) * (up ? gap * 0.8 : -gap * 0.8)
                    var flag = Path()
                    flag.move(to: CGPoint(x: sx, y: fy))
                    flag.addQuadCurve(to: CGPoint(x: sx + gap * 0.9, y: fy + (up ? gap * 1.6 : -gap * 1.6)),
                                      control: CGPoint(x: sx + gap * 1.0, y: fy + (up ? gap * 0.5 : -gap * 0.5)))
                    clip.stroke(flag, with: .color(color), lineWidth: max(1.2, gap * 0.16))
                }
            }
            if [1.5, 3, 0.75].contains(item.beats) {
                clip.fill(Path(ellipseIn: CGRect(x: item.x + gap * 0.95, y: cy - gap * 0.18, width: gap * 0.36, height: gap * 0.36)), with: .color(color))
            }
            if NoteName.isBlack(item.midi) {
                clip.draw(Text("♯").font(.system(size: gap * 1.7, weight: .bold)).foregroundColor(color),
                          at: CGPoint(x: item.x - gap * 1.35, y: cy))
            }
            if model.showNames {
                clip.draw(Text(NoteName.name(item.midi)).font(.system(size: max(10, gap * 0.95), weight: .bold, design: .rounded))
                            .foregroundColor(color.opacity(item.state == 0 ? 0.6 : 1)),
                          at: CGPoint(x: item.x, y: staffBottom + gap * 2.6))
            }
        }

        // Écoute : on montre la mesure qui passe ; libre : invitation
        if model.mode == .free && model.freeNotes.isEmpty {
            clip.draw(Text(L("Pose les doigts sur le clavier : tes notes s'écrivent ici")).font(.system(size: max(12, gap), weight: .semibold, design: .rounded))
                        .foregroundColor(ink.opacity(0.5)),
                      at: CGPoint(x: size.width / 2 + gap * 2, y: staffBottom - gap * 2))
        }
    }
}

/// Papier crème de la partition, avec son ombre : dessiné une fois, pas à chaque image.
struct PaperBackground: View {
    var body: some View {
        Canvas { context, size in
            let paper = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: paper, cornerRadius: 10),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xFFFBF1), Color(hex: 0xF3E9D2)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for i in 0..<60 {
                let x = CGFloat(Draw.hash(i, 5)) * size.width
                let y = CGFloat(Draw.hash(i, 6)) * size.height
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(Color(hex: 0xBFAE8C).opacity(0.25)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
    }
}

// MARK: - Clavier

/// Bandeau en bois au-dessus des touches : feutre rouge, nom de l'app, changement d'octave.
struct Fallboard: View {
    let model: PianoModel
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B1210), Color(hex: 0x2E1F18), Color(hex: 0x120C0A)], startPoint: .top, endPoint: .bottom)
            HStack {
                octaveButton(-1, symbol: "chevron.left.2")
                Spacer()
                Text("ORIGAMO")
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .tracking(4)
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xF3D79A), Color(hex: 0xB8893C)], startPoint: .top, endPoint: .bottom))
                Spacer()
                octaveButton(1, symbol: "chevron.right.2")
            }
            .padding(.horizontal, 14)
            VStack {
                Spacer()
                Rectangle().fill(Color(hex: 0x8E1B22)).frame(height: 3)
            }
        }
        .frame(height: height)
    }

    private func octaveButton(_ dir: Int, symbol: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { model.shift(by: dir) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0xF3D79A))
                .frame(width: 44, height: height - 6)
        }
        .accessibilityLabel(dir < 0 ? L("Octave plus grave") : L("Octave plus aiguë"))
    }
}

struct KeyboardView: View {
    let model: PianoModel
    let visible: Int

    var body: some View {
        GeometryReader { proxy in
            let geo = KeyboardGeometry(size: proxy.size, first: model.firstWhite, count: visible)
            let pressed = model.pressed
            let lit = model.lit
            let guide = model.currentNote?.midi
            let showNames = model.showNames
            ZStack {
                // La touche à jouer clignote ; sans touche guide, le clavier ne se redessine qu'au toucher.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: guide == nil)) { timeline in
                    let pulse = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 5)
                    Canvas { context, size in
                        drawKeys(&context, geo: geo, pressed: pressed, lit: lit, guide: guide, pulse: pulse, showNames: showNames)
                    }
                }
                MultiTouchSurface { points in
                    var notes: [Int: Int] = [:]
                    for (finger, p) in points {
                        if let m = geo.key(at: p) { notes[finger] = m }
                    }
                    model.updateTouches(notes)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("Clavier de piano"))
    }

    private func drawKeys(_ context: inout GraphicsContext, geo: KeyboardGeometry, pressed: Set<Int>, lit: Set<Int>, guide: Int?, pulse: Double, showNames: Bool) {
        let h = geo.size.height
        for w in geo.whites {
            let r = w.rect.insetBy(dx: 0.8, dy: 0)
            let down = pressed.contains(w.midi) || lit.contains(w.midi)
            let key = Path(roundedRect: CGRect(x: r.minX, y: -8, width: r.width, height: r.height + 8 - (down ? 2 : 0)), cornerRadius: 6)
            context.fill(key, with: .linearGradient(
                Gradient(colors: down ? [Color(hex: 0xE4DDCF), Color(hex: 0xCFC6B4)] : [Color(hex: 0xFFFEFA), Color(hex: 0xF1EBDD), Color(hex: 0xE2D9C6)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            if guide == w.midi {
                context.fill(key, with: .linearGradient(Gradient(colors: [.clear, Theme.piano.opacity(0.35 + 0.35 * pulse)]),
                                                         startPoint: CGPoint(x: 0, y: h * 0.4), endPoint: CGPoint(x: 0, y: h)))
            }
            if down {
                context.fill(key, with: .color(Theme.piano.opacity(0.22)))
            }
            context.stroke(key, with: .color(Color(hex: 0x8C8270).opacity(0.6)), lineWidth: 1)
            if showNames || w.midi % 12 == 0 {
                let octave = w.midi / 12 - 1
                let label = w.midi % 12 == 0 ? "\(NoteName.name(w.midi))\(octave)" : NoteName.name(w.midi)
                context.draw(Text(label).font(.system(size: min(14, r.width * 0.32), weight: .bold, design: .rounded))
                                .foregroundColor(guide == w.midi ? Color(hex: 0x6A3FB0) : Color(hex: 0x7A6F5C)),
                             at: CGPoint(x: r.midX, y: h - min(18, h * 0.12)))
            }
        }
        for b in geo.blacks {
            let down = pressed.contains(b.midi) || lit.contains(b.midi)
            let r = b.rect
            let shadow = Path(roundedRect: r.offsetBy(dx: 2, dy: 3), cornerRadius: 4)
            context.fill(shadow, with: .color(.black.opacity(0.35)))
            let key = Path(roundedRect: CGRect(x: r.minX, y: -6, width: r.width, height: r.height + 6 - (down ? 2 : 0)), cornerRadius: 4)
            context.fill(key, with: .linearGradient(
                Gradient(colors: down ? [Color(hex: 0x3A3542), Color(hex: 0x24202A)] : [Color(hex: 0x2C2830), Color(hex: 0x0E0C10)]),
                startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
            var shine = Path()
            shine.addRoundedRect(in: CGRect(x: r.minX + r.width * 0.18, y: r.maxY - r.height * 0.3, width: r.width * 0.64, height: r.height * 0.22),
                                 cornerSize: CGSize(width: 3, height: 3))
            context.fill(shine, with: .linearGradient(Gradient(colors: [.white.opacity(0.0), .white.opacity(0.22)]),
                                                       startPoint: CGPoint(x: 0, y: r.maxY - r.height * 0.3), endPoint: CGPoint(x: 0, y: r.maxY)))
            if guide == b.midi {
                context.fill(key, with: .color(Theme.piano.opacity(0.35 + 0.4 * pulse)))
            }
            if down {
                context.fill(key, with: .color(Theme.piano.opacity(0.3)))
            }
        }
    }
}
