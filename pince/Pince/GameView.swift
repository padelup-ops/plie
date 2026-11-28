import SwiftUI
import SceneKit

// MARK: - L'écran de jeu

/// Le jeu, en plein écran. Pour les captures, `-previewSize 951x669` le dessine à une taille donnée
/// (celle de l'iPhone Duo ouvert, par exemple) au milieu de l'écran.
struct RootView: View {
    var body: some View {
        #if DEBUG
        if let size = RootView.previewSize {
            ZStack {
                Color.black.ignoresSafeArea()
                GameView().frame(width: size.width, height: size.height).clipped()
            }
        } else {
            GameView()
        }
        #else
        GameView()
        #endif
    }

    #if DEBUG
    private static let previewSize: CGSize? = {
        let parts = (UserDefaults.standard.string(forKey: "previewSize") ?? "").split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }()
    #endif
}

struct GameView: View {
    @Environment(Game.self) private var game

    var body: some View {
        // Les marges sûres (encoche, barre du bas) se lisent ici : une fois qu'on dessine en plein écran,
        // elles sont annoncées à zéro.
        GeometryReader { safe in
            screen(insets: safe.safeAreaInsets)
        }
    }

    private func screen(insets: EdgeInsets) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let wide = size.width > size.height
            // Téléphone couché : les commandes se posent dans les coins.
            let compact = wide && size.height < 520
            // Sur un grand écran, les commandes sont dessinées plus gros.
            let k: CGFloat = min(size.width, size.height) >= 700 ? 1.4 : 1
            // La hauteur du pupitre : la face avant de la machine, sous la vitre. Elle est en 3D elle aussi,
            // avec le bac où tombent les doudous ; les commandes sont posées dessus.
            let panel = wide ? max(120, size.height * 0.27) : min(250 * k, max(190 * k, size.height * 0.27)) + insets.bottom
            ZStack {
                MachineView(game: game, panel: panel)

                VStack(spacing: 0) {
                    ZStack {
                        CoinPill()
                        HStack {
                            TrackingBadge()
                            Spacer()
                            TopButtons()
                        }
                    }
                    .padding(.horizontal, max(16, insets.leading + 8) / k)
                    .padding(.top, max(12, insets.top + 6) / k)
                    .frame(width: size.width / k)
                    .scaleEffect(k, anchor: .top)
                    .frame(width: size.width, alignment: .top)
                    Spacer(minLength: 0)
                    if compact {
                        CornerControls(height: size.height, insets: insets)
                    } else {
                        ControlBar(width: size.width / k, height: (panel - insets.bottom) / k, wide: wide)
                            .frame(width: size.width / k)
                            .scaleEffect(k, anchor: .bottom)
                            .frame(width: size.width, height: panel - insets.bottom, alignment: .bottom)
                            .padding(.bottom, insets.bottom)
                    }
                }

                if game.showCollection {
                    Modal(onClose: { game.showCollection = false }) { CollectionCard() }
                }
                if game.showSettings {
                    Modal(onClose: { game.showSettings = false }) { SettingsCard() }
                }
                if let prize = game.prize {
                    Modal(onClose: { game.closePrize() }) { PrizeCard(prize: prize) }
                    Confetti().ignoresSafeArea()
                }
                if !game.introSeen {
                    Modal(onClose: nil) { IntroCard() }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: game.prize)
            .animation(.easeOut(duration: 0.2), value: game.showCollection)
            .animation(.easeOut(duration: 0.2), value: game.showSettings)
            .animation(.easeOut(duration: 0.25), value: game.introSeen)
        }
        .ignoresSafeArea()
        .background(Color(hex: Tint.cream))
    }
}

// MARK: - La vue 3D

struct MachineView: UIViewRepresentable {
    let game: Game
    /// La hauteur, en points, de la face avant de la machine en bas de l'écran.
    let panel: CGFloat

    func makeUIView(context: Context) -> StageView {
        let view = StageView(game: game)
        view.panel = panel
        return view
    }

    func updateUIView(_ view: StageView, context: Context) {
        view.panel = panel
    }
}

final class StageView: SCNView {
    private let game: Game
    var panel: CGFloat = 0 {
        didSet { if oldValue != panel { refresh() } }
    }

    init(game: Game) {
        self.game = game
        super.init(frame: .zero, options: nil)
        scene = game.machine.scene
        pointOfView = game.machine.cameraNode
        delegate = game.machine
        isPlaying = true
        rendersContinuously = true
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        backgroundColor = UIColor(hex: 0xF7D9E6)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
        #if DEBUG
        // Pour les captures : `-wide YES` couche l'écran, le simulateur ne sachant pas tourner tout seul.
        if UserDefaults.standard.bool(forKey: "wide"), let scene = window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif
    }

    /// La taille de la vue et le sens de l'écran fixent la « fenêtre » par laquelle on regarde la machine.
    private func refresh() {
        let pad = traitCollection.userInterfaceIdiom == .pad
        game.machine.resize(bounds.size, panel: panel, pointsPerMeter: pad ? 5200 : 6100, restDistance: pad ? 0.5 : 0.38)
        if let orientation = window?.windowScene?.interfaceOrientation, orientation != .unknown {
            game.tracker.orientation = orientation
        }
    }
}

// MARK: - Les portraits

/// Une photo de chaque doudou, prise une fois pour toutes dans un petit studio 3D.
enum Portraits {
    private static var cache: [Species: UIImage] = [:]

    static func image(_ species: Species) -> UIImage {
        if let image = cache[species] { return image }
        let scene = SCNScene()
        scene.background.contents = UIColor(hex: 0xFFF1E0)
        let model = PlushModel.make(species)
        model.eulerAngles.y = -0.3
        scene.rootNode.addChildNode(model)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(hex: 0xFFF4F0)
        ambient.light?.intensity = 600
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 650
        key.simdPosition = SIMD3<Float>(2, 4, 4)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 26
        camera.simdPosition = SIMD3<Float>(0, 0.36, 7.4)
        scene.rootNode.addChildNode(camera)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 360, height: 360), antialiasingMode: .multisampling4X)
        cache[species] = image
        return image
    }
}

struct Portrait: View {
    let species: Species
    var size: CGFloat

    var body: some View {
        Image(uiImage: Portraits.image(species))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(hex: species.rarity.tint), lineWidth: max(3, size * 0.045)))
    }
}

// MARK: - Les pièces, les boutons du haut

struct CoinIcon: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0xE89B1C))
            Circle().fill(Color(hex: Tint.gold)).padding(size * 0.1)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFF3C4))
        }
        .frame(width: size, height: size)
    }
}

struct CoinPill: View {
    @Environment(Game.self) private var game

    var body: some View {
        HStack(spacing: 8) {
            CoinIcon(size: 24)
            Text("\(game.coins)")
                .font(.toon(21))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(Capsule().fill(Color(hex: Tint.plum)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 2))
        .overlay(alignment: .bottom) {
            if let delta = game.delta {
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .font(.toon(18))
                    .foregroundStyle(Color(hex: delta > 0 ? 0x2FA36B : Tint.rose))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white))
                    .offset(y: 24)
                    .transition(.scale.combined(with: .opacity))
                    .id(game.deltaTick)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.deltaTick)
        .animation(.easeOut(duration: 0.25), value: game.coins)
    }
}

struct RoundButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: Tint.plum))
                .frame(width: 42, height: 42)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Color(hex: Tint.coral), lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }
}

/// Indique comment le relief est calculé : avec le visage, ou en penchant l'appareil.
struct TrackingBadge: View {
    @Environment(Game.self) private var game

    var body: some View {
        if game.depth > 0, game.tracking != .none {
            HStack(spacing: 5) {
                Image(systemName: game.tracking == .tilt ? "gyroscope" : (game.faceSeen ? "eye.fill" : "eye.slash.fill"))
                    .font(.system(size: 13, weight: .bold))
                Text("3D").font(.toon(14))
            }
            .foregroundStyle(Color(hex: Tint.plum))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color(hex: game.tracking == .tilt || game.faceSeen ? Tint.mint : Tint.butter)))
        }
    }
}

struct TopButtons: View {
    @Environment(Game.self) private var game

    var body: some View {
        HStack(spacing: 10) {
            RoundButton(symbol: "teddybear.fill") {
                game.say(.pop)
                Haptics.tap()
                game.showCollection = true
            }
            RoundButton(symbol: "gearshape.fill") {
                game.say(.pop)
                Haptics.tap()
                game.showSettings = true
            }
        }
    }
}

// MARK: - Les commandes

struct Joystick: View {
    let diameter: CGFloat
    let onMove: (CGSize) -> Void
    @State private var knob = CGSize.zero
    @State private var held = false

    var body: some View {
        let reach = diameter * 0.27
        ZStack {
            Circle().fill(Color(hex: 0x4B2A4A))
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x7A4A6C), Color(hex: 0x3F2140)], center: .center, startRadius: 0, endRadius: diameter / 2))
                .padding(diameter * 0.06)
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: diameter * 0.075))
                    .foregroundStyle(.white.opacity(0.4))
                    .offset(y: -diameter * 0.37)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFB3C0), Color(hex: Tint.rose), Color(hex: 0xC9405E)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: diameter * 0.3))
                .frame(width: diameter * 0.46, height: diameter * 0.46)
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.7))
                        .frame(width: diameter * 0.1, height: diameter * 0.1)
                        .offset(x: diameter * 0.09, y: diameter * 0.07)
                }
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 4)
                .offset(knob)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !held {
                        held = true
                        Haptics.tap()
                    }
                    var v = drag.translation
                    let length = hypot(v.width, v.height)
                    if length > reach {
                        v.width *= reach / length
                        v.height *= reach / length
                    }
                    knob = v
                    onMove(CGSize(width: v.width / reach, height: -v.height / reach))
                }
                .onEnded { _ in
                    held = false
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { knob = .zero }
                    onMove(.zero)
                }
        )
    }
}

/// Un gros bouton rond d'arcade qui s'enfonce.
struct ArcadeButton: ButtonStyle {
    var color: Color
    var shade: Color

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .background(
                ZStack {
                    Circle().fill(color)
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center)).padding(7)
                }
            )
            .offset(y: down ? 6 : 0)
            .background(Circle().fill(shade).offset(y: 7))
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: down)
    }
}

/// Le bouton qui fait descendre la pince, avec son prix. Sans pièces, il laisse la place à un cadeau.
struct DropControl: View {
    @Environment(Game.self) private var game
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            if game.broke {
                Button(action: { game.takeGift() }) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: diameter * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: diameter, height: diameter)
                }
                .buttonStyle(ArcadeButton(color: Color(hex: 0x4FBF8B), shade: Color(hex: 0x2F8F63)))
                Text("+\(Game.gift)").font(.toon(16)).foregroundStyle(Color(hex: 0x2F8F63))
            } else {
                Button(action: { game.drop() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: diameter * 0.42, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: diameter, height: diameter)
                }
                .buttonStyle(ArcadeButton(color: Color(hex: game.canDrop ? 0xF2496B : 0xC9B8C2), shade: Color(hex: game.canDrop ? 0xB52C4C : 0xA4939D)))
                .disabled(!game.canDrop)
                HStack(spacing: 4) {
                    CoinIcon(size: 16)
                    Text("\(Game.cost)").font(.toon(16)).foregroundStyle(Color(hex: Tint.plum))
                }
            }
        }
        .accessibilityLabel(game.broke ? T("Cadeau", "Gift") : T("Descendre la pince", "Drop the claw"))
    }
}

/// Un raccourci vers la collection, sous le bac de sortie.
struct CollectionChip: View {
    @Environment(Game.self) private var game

    var body: some View {
        Button(action: {
            game.say(.pop)
            Haptics.tap()
            game.showCollection = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "teddybear.fill").font(.system(size: 14, weight: .bold))
                Text("\(game.collected)/\(Species.allCases.count)").font(.toon(15))
            }
            .foregroundStyle(Color(hex: Tint.plum))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(.white))
            .overlay(Capsule().strokeBorder(Color(hex: Tint.coral), lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Mes doudous", "My plushies"))
    }
}

/// Les commandes, posées sur la face avant de la machine : le manche au milieu, le bouton à droite.
/// La gauche reste libre : c'est là que se trouve le bac de sortie, sous la trappe.
struct ControlBar: View {
    @Environment(Game.self) private var game
    let width: CGFloat
    let height: CGFloat
    let wide: Bool

    var body: some View {
        let inner = min(width, 660) - 32
        let stick = min(height - 34, 150, inner * 0.4)
        HStack(spacing: 0) {
            VStack {
                Spacer(minLength: 0)
                if !wide { CollectionChip().padding(.bottom, 18) }
            }
            .frame(maxWidth: .infinity)
            Joystick(diameter: stick) { game.stick($0) }
            DropControl(diameter: min(stick * 0.74, inner * 0.29, height - 58))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 660)
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

/// Les commandes dans les coins, pour un téléphone tenu couché : la machine reste dégagée.
struct CornerControls: View {
    @Environment(Game.self) private var game
    let height: CGFloat
    let insets: EdgeInsets

    var body: some View {
        let stick = min(120, height * 0.3)
        HStack(alignment: .bottom) {
            Joystick(diameter: stick) { game.stick($0) }
            Spacer()
            DropControl(diameter: stick * 0.8)
        }
        .padding(.bottom, max(14, insets.bottom + 6))
        .padding(.leading, max(14, insets.leading - 8))
        .padding(.trailing, max(14, insets.trailing - 8))
    }
}

// MARK: - Les cartes

/// Un voile sombre et une carte au milieu. Toucher le voile ferme la carte.
struct Modal<Content: View>: View {
    let onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(hex: 0x2B1830, opacity: 0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose?() }
            content()
                .padding(22)
                .frame(maxWidth: 430)
                .background(RoundedRectangle(cornerRadius: 30).fill(Color(hex: Tint.paper)))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color(hex: Tint.coral), lineWidth: 4))
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .scaleEffect(UIDevice.current.userInterfaceIdiom == .pad ? 1.35 : 1)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .transition(.opacity)
    }
}

struct BigButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.toon(20))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .frame(height: 52)
                .background(Capsule().fill(Color(hex: Tint.rose)))
                .background(Capsule().fill(Color(hex: 0xB52C4C)).offset(y: 4))
        }
        .buttonStyle(.plain)
    }
}

struct PrizeCard: View {
    @Environment(Game.self) private var game
    let prize: Prize
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 12) {
            Text(T("Gagné !", "You got one!"))
                .font(.toon(30))
                .foregroundStyle(Color(hex: Tint.rose))
            Portrait(species: prize.species, size: 170)
                .scaleEffect(bounce ? 1 : 0.6)
                .overlay(alignment: .topTrailing) {
                    if prize.isNew {
                        Text(T("NOUVEAU", "NEW"))
                            .font(.toon(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(Color(hex: 0x2FA36B)))
                            .rotationEffect(.degrees(12))
                            .offset(x: 14, y: 4)
                    }
                }
            Text(prize.species.name)
                .font(.toon(22))
                .foregroundStyle(Color(hex: Tint.plum))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Text(prize.species.rarity.label)
                    .font(.toon(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color(hex: prize.species.rarity.tint)))
                HStack(spacing: 4) {
                    CoinIcon(size: 20)
                    Text("+\(prize.reward)").font(.toon(18)).foregroundStyle(Color(hex: Tint.plum))
                }
            }
            BigButton(title: T("Super !", "Yay!")) { game.closePrize() }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { bounce = true }
        }
    }
}

struct CollectionCard: View {
    @Environment(Game.self) private var game

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(T("Mes doudous", "My plushies"))
                    .font(.toon(26))
                    .foregroundStyle(Color(hex: Tint.rose))
                Spacer()
                Text("\(game.collected)/\(Species.allCases.count)")
                    .font(.toon(18))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(Color(hex: Tint.plum)))
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(Species.allCases) { species in
                        let count = game.owned[species.rawValue] ?? 0
                        VStack(spacing: 6) {
                            if count > 0 {
                                Portrait(species: species, size: 84)
                                    .overlay(alignment: .bottomTrailing) {
                                        Text("×\(count)")
                                            .font(.toon(13))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7)
                                            .frame(height: 22)
                                            .background(Capsule().fill(Color(hex: Tint.plum)))
                                            .offset(x: 6, y: 2)
                                    }
                                Text(species.name)
                                    .font(.toon(12, .bold))
                                    .foregroundStyle(Color(hex: Tint.plum))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            } else {
                                ZStack {
                                    Circle().fill(Color(hex: 0xF5E6EC))
                                    Circle().strokeBorder(Color(hex: species.rarity.tint), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 30, weight: .black))
                                        .foregroundStyle(Color(hex: 0xD9BFCB))
                                }
                                .frame(width: 84, height: 84)
                                Text(species.rarity.label)
                                    .font(.toon(12, .bold))
                                    .foregroundStyle(Color(hex: species.rarity.tint))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 430)
            BigButton(title: T("Fermer", "Close")) { game.showCollection = false }
        }
    }
}

struct SettingsCard: View {
    @Environment(Game.self) private var game

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(T("Réglages", "Settings"))
                .font(.toon(26))
                .foregroundStyle(Color(hex: Tint.rose))
            Toggle(T("Bruitages", "Sound effects"), isOn: Binding(get: { game.soundOn }, set: { game.setSound($0) }))
            Toggle(T("Musique", "Music"), isOn: Binding(get: { game.musicOn }, set: { game.setMusic($0) }))
            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle(T("Vibrations", "Vibrations"), isOn: Binding(get: { game.hapticsOn }, set: { game.setHaptics($0) }))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(T("Relief", "3D effect"))
                Picker(T("Relief", "3D effect"), selection: Binding(get: { game.depth }, set: { game.setDepth($0) })) {
                    Text(T("À plat", "Off")).tag(0)
                    Text(T("Normal", "Normal")).tag(1)
                    Text(T("Fort", "Strong")).tag(2)
                }
                .pickerStyle(.segmented)
                if game.depth > 0, HeadTracker.hasDepthTracking, game.tracking == .face || game.tracking == .camera {
                    Picker(T("Suivi", "Tracking"), selection: Binding(get: { game.simpleCamera ? 1 : 0 }, set: { game.setSimpleCamera($0 == 1) })) {
                        Text(T("Suivi automatique", "Automatic tracking")).tag(0)
                        Text(T("Caméra simple", "Plain camera")).tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                Text(status)
                    .font(.toon(13, .medium))
                    .foregroundStyle(Color(hex: Tint.plum, opacity: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if game.depth > 0, game.tracking != .none {
                    // Le relief doit suivre la tête : quand on va à droite, on découvre le côté droit de la machine.
                    // Si un appareil donne un axe à l'envers, on le retourne ici.
                    Toggle(T("Inverser gauche-droite", "Flip left-right"), isOn: Binding(get: { game.flipX }, set: { game.setFlip(x: $0) }))
                        .font(.toon(14, .bold))
                    Toggle(T("Inverser haut-bas", "Flip up-down"), isOn: Binding(get: { game.flipY }, set: { game.setFlip(y: $0) }))
                        .font(.toon(14, .bold))
                }
            }
            HStack {
                if game.depth > 0, game.tracking != .none {
                    Button(action: { game.recenter() }) {
                        Label(T("Recentrer la vue", "Recenter the view"), systemImage: "scope")
                            .font(.toon(15))
                            .foregroundStyle(Color(hex: Tint.plum))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Capsule().fill(Color(hex: Tint.mint)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                BigButton(title: T("Fermer", "Close")) { game.showSettings = false }
            }
        }
        .font(.toon(17, .bold))
        .foregroundStyle(Color(hex: Tint.plum))
        .tint(Color(hex: Tint.rose))
    }

    private var status: String {
        if game.depth == 0 { return T("L'image reste fixe.", "The picture stays still.") }
        switch game.tracking {
        case .face, .camera:
            let privacy = T(" Aucune image n'est enregistrée ni envoyée.", " No image is recorded or sent.")
            if game.faceSeen {
                let side = game.faceRight >= 0 ? T("à droite", "to the right") : T("à gauche", "to the left")
                let lift = game.faceUp >= 0 ? T("vers le haut", "up") : T("vers le bas", "down")
                return T("Je vois ta tête : \(abs(game.faceRight)) cm \(side), \(abs(game.faceUp)) cm \(lift), à \(game.faceDistance) cm de l'écran.",
                         "I can see your head: \(abs(game.faceRight)) cm \(side), \(abs(game.faceUp)) cm \(lift), \(game.faceDistance) cm from the screen.") + privacy
            }
            return T("Je ne vois pas ton visage : place-toi bien face à la caméra avant, dans la lumière.",
                     "I can't see your face: sit right in front of the front camera, in good light.") + privacy
        case .tilt:
            return T("Sans la caméra, le relief suit l'inclinaison de l'appareil : penche-le pour regarder sur les côtés.",
                     "Without the camera, the effect follows the tilt of the device: lean it to look around.")
        case .none:
            return T("Le relief n'est pas disponible sur cet appareil.", "The 3D effect isn't available on this device.")
        }
    }
}

struct IntroCard: View {
    @Environment(Game.self) private var game

    var body: some View {
        VStack(spacing: 14) {
            Portrait(species: .bunny, size: 120)
            Text("Peekaclaw")
                .font(.toon(30))
                .foregroundStyle(Color(hex: Tint.rose))
            VStack(alignment: .leading, spacing: 12) {
                tip("eye.fill", T("La machine est en relief : bouge la tête pour regarder sur les côtés et par-dessus.",
                                  "The machine is in 3D: move your head to look around the sides and over the top."))
                tip("scope", T("Place la pince pile au-dessus d'un doudou, puis fais-la descendre. Bien centré, il ne glisse pas.",
                               "Put the claw right above a plushie, then drop it. Dead centre, it won't slip."))
                tip("camera.fill", T("La caméra avant sert seulement à repérer ta tête. Aucune image n'est enregistrée ni envoyée.",
                                     "The front camera is only used to locate your head. No image is recorded or sent."))
            }
            BigButton(title: T("C'est parti !", "Let's play!")) {
                game.say(.pop)
                Haptics.tap()
                game.begin()
            }
            .padding(.top, 4)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: Tint.coral)))
            Text(text)
                .font(.toon(15, .semibold))
                .foregroundStyle(Color(hex: Tint.plum))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Les confettis

struct Confetti: View {
    @State private var start = Date()
    private let colors: [UInt32] = [Tint.coral, Tint.butter, Tint.mint, Tint.sky, Tint.lilac, Tint.rose]

    private func noise(_ i: Int, _ k: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for i in 0..<70 {
                    let speed = 140 + noise(i, 1) * 200
                    let fall = t * speed - noise(i, 2) * 500
                    guard fall > -20, fall < size.height + 20 else { continue }
                    let x = noise(i, 3) * size.width + sin(t * 2.2 + noise(i, 4) * 6) * 22
                    var piece = context
                    piece.translateBy(x: x, y: fall)
                    piece.rotate(by: .radians(t * (2 + noise(i, 5) * 4) + noise(i, 6) * 6))
                    piece.fill(Path(roundedRect: CGRect(x: -5, y: -7, width: 10, height: 14), cornerRadius: 3),
                               with: .color(Color(hex: colors[i % colors.count])))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
