import SwiftUI
import Combine
import AVFoundation
import CoreImage

extension Theme {
    static let dessine = Color(hex: 0xFFB020)
}

// MARK: - Dessine-moi
//
// Le dessinateur tient le Duo ouvert comme un livre : il voit le mot secret et dessine sur
// l'écran intérieur. En face, les autres voient le dessin se faire en direct sur l'écran extérieur,
// et la caméra du dos les prend en photo au moment où ils trouvent.

struct DStroke: Identifiable {
    let id: Int
    let color: Color
    let width: CGFloat
    /// Points en coordonnées de la feuille (0 à 1 dans chaque sens).
    var points: [CGPoint]
}

struct DessinePhoto: Identifiable {
    let id: Int
    let word: String
    let image: UIImage
}

/// Petite caméra : elle doit tourner pour que l'écran extérieur s'allume, et elle prend la photo des joueurs.
final class GuessersCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.plie.dessine.camera")
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext(options: nil)
    private var latest: CIImage?
    private let lock = NSLock()

    func start(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            guard allowed else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.queue.async {
                let ok = self.configure()
                if ok && !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    private func configure() -> Bool {
        if !session.inputs.isEmpty { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        // La caméra du dos regarde les joueurs qui devinent, en face du dessinateur.
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        return true
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // On garde une copie légère de la dernière image (pas le tampon de la caméra).
        let image = CIImage(cvPixelBuffer: buffer)
        lock.lock()
        latest = image
        lock.unlock()
    }

    func snapshot() -> UIImage? {
        lock.lock()
        let image = latest
        lock.unlock()
        guard let image, let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

@Observable
final class DessineGame {
    enum Phase: Equatable {
        case menu, drawing, roundEnd
    }

    private(set) var phase: Phase = .menu
    private(set) var word = ""
    private(set) var strokes: [DStroke] = []
    private(set) var found = 0
    private(set) var foundWords: [String] = []
    private(set) var photos: [DessinePhoto] = []
    private(set) var timeLeft: Double = 90
    private(set) var flashAt: Double = -10
    private(set) var clock: Double = 0
    private(set) var round = 0
    private(set) var bestRound = 0
    var duration = 90
    var color: Color = Color(hex: 0x1A1A1A)
    var width: CGFloat = 0.012
    var categories: Set<WordTheme> = [.animals, .objects, .food]

    @ObservationIgnored private var deck: [String] = []
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored var takePhoto: (() -> UIImage?)?

    func startRound() {
        round += 1
        found = 0
        foundWords = []
        photos = []
        strokes = []
        timeLeft = Double(duration)
        if deck.isEmpty { refill() }
        word = deck.popLast() ?? ""
        phase = .drawing
        SoundPlayer.shared.play(.go, volume: 0.6)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func refill() {
        let english = Lang.shared.isEnglish
        let themes: [WordTheme] = categories.isEmpty ? [.animals, .objects] : Array(categories)
        let pool = themes.flatMap { $0.words }
        deck = pool.map { english ? $0.1 : $0.0 }.shuffled()
    }

    func backToMenu() {
        phase = .menu
        round = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Dessin

    func begin(at p: CGPoint) {
        nextID += 1
        strokes.append(DStroke(id: nextID, color: color, width: width, points: [p]))
    }

    func extend(to p: CGPoint) {
        guard !strokes.isEmpty else { return begin(at: p) }
        let last = strokes[strokes.count - 1].points.last ?? p
        if hypot(p.x - last.x, p.y - last.y) > 0.002 {
            strokes[strokes.count - 1].points.append(p)
        }
    }

    func undo() {
        if !strokes.isEmpty { strokes.removeLast() }
    }

    func clear() {
        strokes = []
    }

    // MARK: Mots

    func gotIt() {
        guard phase == .drawing else { return }
        found += 1
        foundWords.append(word)
        flashAt = clock
        if let image = takePhoto?() {
            nextID += 1
            photos.append(DessinePhoto(id: nextID, word: word, image: image))
        }
        SoundPlayer.shared.play(.bell, volume: 0.8)
        SoundPlayer.shared.play(.applause, volume: 0.5)
        Haptics.success()
        nextWord()
    }

    func skip() {
        guard phase == .drawing else { return }
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
        nextWord()
    }

    private func nextWord() {
        strokes = []
        if deck.isEmpty { refill() }
        word = deck.popLast() ?? word
    }

    func tick(dt: Double) {
        clock += dt
        guard phase == .drawing else { return }
        let before = Int(timeLeft.rounded(.up))
        timeLeft = max(0, timeLeft - dt)
        let after = Int(timeLeft.rounded(.up))
        if after != before && after <= 5 && after > 0 { SoundPlayer.shared.play(.clockTick, volume: 0.8) }
        if timeLeft <= 0 {
            phase = .roundEnd
            bestRound = max(bestRound, found)
            SoundPlayer.shared.play(.stop, volume: 0.9)
            Haptics.success()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

// MARK: - Écran du dessinateur (intérieur)

struct DessineView: View {
    @Environment(AppState.self) private var app
    @State private var game = DessineGame()
    @State private var camera = GuessersCamera()
    @State private var cameraOn = false
    @State private var outerEnabled = true
    @State private var outerAvailable = false
    @State private var peek = false

    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    static let palette: [UInt32] = [0x1A1A1A, 0xE5332A, 0xF28A1E, 0xF7C531, 0x1E8A4C, 0x2457D6, 0x8E44AD, 0x8B5A2B]

    /// L'écran extérieur montre le dessin : le mot peut rester affiché pour le dessinateur.
    private var twoScreens: Bool { outerAvailable && cameraOn }

    var body: some View {
        ZStack {
            Color(hex: 0x1B1408).ignoresSafeArea()
            switch game.phase {
            case .menu: menu
            case .drawing: drawing
            case .roundEnd: roundEnd
            }
        }
        .foregroundStyle(.white)
        .onReceive(ticker) { _ in game.tick(dt: 1.0 / 30.0) }
        .onAppear {
            game.takePhoto = { [camera] in camera.snapshot() }
            camera.start { ok in cameraOn = ok }
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .roundEnd { app.recordDessine(found: game.found) }
        }
        // Le dessin, en direct, sur l'écran extérieur face aux joueurs qui devinent.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            DessineOuterView(game: game)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .dessine)
            Spacer()
            if game.phase == .drawing {
                Label("\(game.found)", systemImage: "checkmark.seal.fill")
                    .font(.plie(18))
                    .foregroundStyle(Theme.go)
                Text("\(Int(game.timeLeft.rounded(.up)))")
                    .font(.plie(24))
                    .monospacedDigit()
                    .foregroundStyle(game.timeLeft <= 10 ? Theme.coral : .white)
                    .frame(minWidth: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                Text(verbatim: "🎨").font(.system(size: 56)).accessibilityHidden(true)
                Text(L("Dessine-moi")).font(.plie(34))
                Text(L("Tiens le Duo ouvert comme un livre : toi seul vois le mot. Dessine : les autres voient ton dessin en direct sur l'écran extérieur, et la caméra les prend en photo quand ils trouvent."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Label(twoScreens ? L("Écran extérieur prêt : le dessin s'y affiche") : L("Sans écran extérieur : montre ton dessin, le mot reste caché"),
                      systemImage: twoScreens ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(twoScreens ? Theme.go : Theme.gold)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
                Text(L("Thèmes")).font(.plie(17, weight: .bold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(WordTheme.allCases.filter { $0 != .mime }) { c in
                        let on = game.categories.contains(c)
                        Button {
                            if on { game.categories.remove(c) } else { game.categories.insert(c) }
                        } label: {
                            Label(c.title, systemImage: c.symbol)
                                .font(.plie(16, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? c.color : Color.white.opacity(0.08)))
                                .foregroundStyle(on ? Theme.ink : .white)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
                Picker(L("Durée"), selection: Binding(get: { game.duration }, set: { game.duration = $0 })) {
                    Text(L("60 s")).tag(60)
                    Text(L("90 s")).tag(90)
                    Text(L("2 min")).tag(120)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Button {
                    game.startRound()
                } label: {
                    Label(L("Je dessine !"), systemImage: "pencil.tip")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.dessine, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)
                .disabled(game.categories.isEmpty)
            }
            .padding(.bottom, 30)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Dessin

    private var drawing: some View {
        VStack(spacing: 10) {
            header
            wordCard
            DessineCanvas(game: game, editable: true)
                .padding(.horizontal, 12)
            toolbar
        }
        .padding(.bottom, 8)
    }

    private var wordCard: some View {
        HStack(spacing: 12) {
            if twoScreens || peek {
                Text(game.word)
                    .font(.plie(28))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else {
                Text(L("Maintiens ici pour voir le mot"))
                    .font(.plie(16, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 40, pressing: { pressing in peek = pressing }, perform: {})
            }
            Button(L("Passer")) { game.skip() }
                .font(.plie(15, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Capsule().fill(Theme.ink.opacity(0.15)))
            Button {
                game.gotIt()
                peek = false
            } label: {
                Label(L("Trouvé !"), systemImage: "checkmark")
                    .font(.plie(16, weight: .heavy))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Capsule().fill(Theme.go))
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(FoldedPaper(color: Theme.dessine, cornerRadius: 20))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(Self.palette, id: \.self) { hex in
                let c = Color(hex: hex)
                Button {
                    game.color = c
                    if game.width > 0.03 { game.width = 0.012 }
                } label: {
                    Circle().fill(c)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(.white, lineWidth: game.color == c ? 3 : 0))
                }
                .accessibilityLabel(L("Couleur"))
            }
            Divider().frame(height: 30)
            Button {
                game.width = game.width < 0.015 ? 0.025 : 0.012
            } label: {
                Image(systemName: game.width < 0.015 ? "pencil.tip" : "paintbrush.pointed.fill").font(.system(size: 20, weight: .bold))
            }
            .accessibilityLabel(L("Épaisseur du trait"))
            Button {
                game.color = Color(hex: 0xFFFDF6)
                game.width = 0.05
            } label: {
                Image(systemName: "eraser.fill").font(.system(size: 20, weight: .bold))
            }
            .accessibilityLabel(L("Gomme"))
            Button { game.undo() } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 20, weight: .bold))
            }
            .accessibilityLabel(L("Annuler le dernier trait"))
            Button { game.clear() } label: {
                Image(systemName: "trash.fill").font(.system(size: 20, weight: .bold))
            }
            .accessibilityLabel(L("Tout effacer"))
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    // MARK: Fin du tour

    private var roundEnd: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Text(L("Temps écoulé !")).font(.plie(30))
                Text(L("\(game.found) mot\(game.found > 1 ? "s" : "") trouvé\(game.found > 1 ? "s" : "")"))
                    .font(.plie(24))
                    .foregroundStyle(Theme.dessine)
                if !game.foundWords.isEmpty {
                    Text(game.foundWords.joined(separator: " · "))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                if !game.photos.isEmpty {
                    SectionTitle(text: L("Vos têtes quand vous avez trouvé"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(game.photos) { photo in
                                VStack(spacing: 6) {
                                    Image(uiImage: photo.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Text(photo.word).font(.plie(15, weight: .bold))
                                    ShareLink(item: Image(uiImage: photo.image), preview: SharePreview(photo.word, image: Image(uiImage: photo.image))) {
                                        Label(L("Partager"), systemImage: "square.and.arrow.up").font(.plie(13, weight: .bold))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    Text(L("Ces photos restent dans l'app jusqu'au prochain tour, sauf si tu les partages."))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
                Button(L("Au suivant de dessiner !")) { game.startRound() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.dessine, textColor: Theme.ink, height: 58))
                    .frame(maxWidth: 380)
                Button(L("Changer les réglages")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 380)
            }
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - La feuille

struct DessineCanvas: View {
    let game: DessineGame
    let editable: Bool
    @State private var stroking = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0xFFFDF6))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Canvas { context, s in
                    DessineCanvas.draw(&context, strokes: game.strokes, size: s)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if game.strokes.isEmpty && editable {
                    Text(L("Dessine ici avec le doigt"))
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.2))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard editable, game.phase == .drawing else { return }
                        let p = CGPoint(x: min(1, max(0, value.location.x / max(1, size.width))),
                                        y: min(1, max(0, value.location.y / max(1, size.height))))
                        if stroking {
                            game.extend(to: p)
                        } else {
                            stroking = true
                            game.begin(at: p)
                        }
                    }
                    .onEnded { _ in stroking = false }
            )
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .accessibilityLabel(L("Feuille de dessin"))
    }

    static func draw(_ context: inout GraphicsContext, strokes: [DStroke], size: CGSize) {
        for stroke in strokes {
            let w = stroke.width * size.width
            if stroke.points.count == 1, let p = stroke.points.first {
                let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w)), with: .color(stroke.color))
                continue
            }
            var path = Path()
            for (i, p) in stroke.points.enumerated() {
                let q = CGPoint(x: p.x * size.width, y: p.y * size.height)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Écran extérieur (les joueurs qui devinent)

struct DessineOuterView: View {
    let game: DessineGame

    var body: some View {
        ZStack {
            Color(hex: 0x1B1408).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    Label("\(game.found)", systemImage: "checkmark.seal.fill").font(.plie(24)).foregroundStyle(Theme.go)
                    Spacer()
                    if game.phase == .drawing {
                        Text("\(Int(game.timeLeft.rounded(.up)))").font(.plie(30)).monospacedDigit()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                if game.phase == .drawing {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xFFFDF6))
                        Canvas { context, s in
                            DessineCanvas.draw(&context, strokes: game.strokes, size: s)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        if game.clock - game.flashAt < 1.2 {
                            Text(L("Trouvé !"))
                                .font(.plie(64))
                                .foregroundStyle(Theme.go)
                                .shadow(color: .black.opacity(0.3), radius: 6)
                        }
                    }
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .padding(.horizontal, 14)
                    Text(L("Devinez ! Criez le mot dès que vous le trouvez."))
                        .font(.plie(18, weight: .bold))
                        .multilineTextAlignment(.center)
                } else {
                    Spacer()
                    Text(verbatim: "🎨").font(.system(size: 60))
                    Text(game.phase == .roundEnd ? L("\(game.found) mots trouvés !") : L("Prêts à deviner ?"))
                        .font(.plie(30))
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }
}
