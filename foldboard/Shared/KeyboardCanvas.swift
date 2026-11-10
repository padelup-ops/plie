import UIKit

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Ce que le clavier demande à son hôte (l'extension clavier, ou l'aperçu dans l'app).
/// Téléphone tenu tête en bas : l'angle est retourné de 180° (droite et gauche restent celles de l'écran).
func kbAngleOffset(_ o: UIInterfaceOrientation?) -> Double {
    o == .portraitUpsideDown ? 180 : 0
}

protocol KBInput: AnyObject {
    func kbInsert(_ text: String)
    func kbDelete()
    func kbMoveCursor(_ offset: Int)
    func kbTextBefore() -> String?
    func kbNextKeyboard()
    func kbDismiss()
    func kbSettingsChanged(_ settings: KBSettings)
    var kbNeedsGlobe: Bool { get }
    var kbFullAccess: Bool { get }
    /// Relit l'accès Pro (coffre, puis achats) : l'app l'a peut-être débloqué entre-temps.
    func kbRecheckPro(_ done: @escaping (Bool) -> Void)
}

/// Une touche dessinée (elle ne reçoit pas les touchers : c'est le clavier qui les gère tous).
final class KeyView: UIView {
    let label = UILabel()
    let icon = UIImageView()
    var spec: KeySpec
    var special: Bool

    init(spec: KeySpec, special: Bool) {
        self.spec = spec
        self.special = special
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        icon.contentMode = .scaleAspectFit
        addSubview(label)
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        let s = min(bounds.width, bounds.height) * 0.46
        icon.frame = CGRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        let r = min(13, bounds.height * 0.26)
        layer.cornerRadius = r
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: r).cgPath
    }
}

/// Le clavier Foldboard : une main (gauche, droite, ou qui suit la main), toute la largeur, ou deux mains.
final class KeyboardCanvas: UIView {
    weak var input: KBInput?

    /// Les réglages enregistrés, et ceux appliqués (sans Pro, on revient à l'essentiel).
    private(set) var settings = KBSettings()
    private var eff = KBSettings()
    private(set) var pro = false
    private var theme = KBTheme.auto

    private var page: KBPage = .letters
    private enum Shift { case off, on, caps }
    private var shift: Shift = .off
    private var autoShifted = false
    private var lastShiftTap = Date.distantPast

    private struct Cell {
        let view: KeyView
        let frame: CGRect
        var hit: CGRect
    }
    private var cells: [Cell] = []
    private var blocks: [CGRect] = []
    private var panelRect: CGRect = .zero
    private var builtFor: CGSize = .zero

    private let topBar = UIView()
    private let modeButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)
    /// Écran intérieur, petit clavier : un bouton pour passer en grand (et revenir).
    private let bigButton = UIButton(type: .system)
    private let hideButton = UIButton(type: .system)
    /// Petit clavier : le globe et les emojis sont ici, pour laisser la place à l'espace.
    private let globeButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let adjustButton = UIButton(type: .system)
    private let chips = UIScrollView()
    private let chipStack = UIStackView()
    private let toast = UILabel()
    private let panel = UIView()
    private let bubble = UILabel()
    private let accentView = UIView()
    private var accentLabels: [UILabel] = []

    /// Mode automatique : la main qui tient le téléphone (inclinaison, puis GripSense pendant la frappe).
    private let grip = GripDetector()
    /// Correction et suggestions de mots.
    private let suggest = KBSuggest()
    /// Les suggestions se calculent à part (le correcteur d'iOS peut prendre plusieurs dizaines de ms) :
    /// le fil principal reste libre pour les touchers, la frappe ne rame plus.
    private let bgSuggest = KBSuggest()
    private let suggestQueue = DispatchQueue(label: "foldboard.suggest", qos: .userInitiated)
    private var suggestGen = 0
    /// La correction déjà calculée pour le mot en cours (évite de la recalculer à l'espace).
    private var cachedFix: (word: String, fix: String?)?
    private var suggestionItems: [String] = []
    private var suggestionBest: Int?
    private var lastCorrection: (original: String, corrected: String, sep: String)?
    private var pendingGrip: KBGrip?
    private var idleTimer: Timer?
    private var visible = false
    private var autoOn: Bool { eff.mode == .auto && pro }

    private final class Track {
        let index: Int
        let start: CGPoint
        var lastX: CGFloat
        var cursorMode = false
        var cursorAccum: CGFloat = 0
        var accents: [String] = []
        var accentIndex = 0
        var longTimer: Timer?
        var repeatTimer: Timer?
        var done = false
        /// La lettre déjà écrite, dès que le doigt s'est posé (comme ça, rien n'attend que le doigt se relève).
        var typed: String?
        var swipe = false
        var points: [CGPoint] = []
        var t0: TimeInterval = 0
        init(index: Int, start: CGPoint) {
            self.index = index
            self.start = start
            self.lastX = start.x
        }
    }
    private var tracks: [UITouch: Track] = [:]
    private var order: [UITouch] = []

    static let topBarHeight: CGFloat = 42
    private let pad: CGFloat = 4
    private let gap: CGFloat = 7
    private let vgap: CGFloat = 11

    private var keyH: CGFloat { CGFloat(eff.keyHeight) }
    private var rowCount: Int { 4 }
    var preferredHeight: CGFloat {
        Self.topBarHeight + 6 + CGFloat(rowCount) * keyH + CGFloat(rowCount - 1) * vgap + 8
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = true
        // Comme le clavier d'Apple : un panneau aux coins du haut arrondis.
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        addSubview(panel)
        addSubview(topBar)
        emojiBoard.isHidden = true
        emojiBoard.onEmoji = { [weak self] e in
            guard let self else { return }
            KBFeedback.shared.tap(sound: self.eff.sound, haptics: self.eff.haptics)
            self.input?.kbInsert(e)
            self.refreshSuggestionsSoon()
        }
        emojiBoard.onABC = { [weak self] in self?.closeEmoji() }
        emojiBoard.onDelete = { [weak self] in
            guard let self else { return }
            KBFeedback.shared.tap(sound: self.eff.sound, haptics: self.eff.haptics)
            self.input?.kbDelete()
            self.refreshSuggestionsSoon()
        }
        addSubview(emojiBoard)
        adjustButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        adjustButton.addAction(UIAction { [weak self] _ in self?.startAdjust() }, for: .touchUpInside)
        adjustButton.accessibilityLabel = L("Adjust the keyboard")
        for b in [modeButton, flipButton, bigButton, hideButton, adjustButton, globeButton, emojiButton] {
            b.tintColor = .label
            topBar.addSubview(b)
        }
        modeButton.showsMenuAsPrimaryAction = true
        flipButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        flipButton.addAction(UIAction { [weak self] _ in self?.flipSide() }, for: .touchUpInside)
        flipButton.accessibilityLabel = L("Switch side")
        bigButton.addAction(UIAction { [weak self] _ in self?.toggleBig() }, for: .touchUpInside)
        // Appui long : la situation reconnue et l'étalonnage utilisé (pour vérifier).
        flipButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(showGripInfo(_:))))
        hideButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hideButton.addAction(UIAction { [weak self] _ in self?.input?.kbDismiss() }, for: .touchUpInside)
        hideButton.accessibilityLabel = L("Hide keyboard")
        hideButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(showPerf(_:))))
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.addAction(UIAction { [weak self] _ in self?.input?.kbNextKeyboard() }, for: .touchUpInside)
        emojiButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        emojiButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.showEmoji = true
            self.builtFor = .zero
            self.rebuild()
        }, for: .touchUpInside)
        chips.showsHorizontalScrollIndicator = false
        chips.alwaysBounceHorizontal = true
        chipStack.axis = .horizontal
        chipStack.spacing = 8
        chipStack.alignment = .center
        chips.addSubview(chipStack)
        topBar.addSubview(chips)
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 14, weight: .semibold)
        toast.alpha = 0
        toast.layer.cornerRadius = 10
        toast.layer.masksToBounds = true
        topBar.addSubview(toast)

        bubble.textAlignment = .center
        bubble.isHidden = true
        bubble.layer.cornerRadius = 9
        bubble.layer.masksToBounds = true
        addSubview(bubble)
        accentView.isHidden = true
        accentView.layer.cornerRadius = 10
        accentView.layer.shadowColor = UIColor.black.cgColor
        accentView.layer.shadowOpacity = 0.25
        accentView.layer.shadowRadius = 6
        accentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(accentView)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Réglages

    func configure(settings: KBSettings, pro: Bool) {
        self.settings = settings
        self.pro = pro
        eff = settings.effective(pro: pro)
        theme = KBTheme.named(eff.theme)
        suggest.setLayout(eff.layout)
        let layout = eff.layout
        suggestQueue.async { [bgSuggest] in bgSuggest.setLayout(layout) }
        updateGripContext()
        grip.current = settings.autoTwo ? .two : (settings.autoRight ? .right : .left)
        builtFor = .zero
        setNeedsLayout()
        if visible && (autoOn || recording != nil) && !gripStarted { startGrip() }
        if visible && !autoOn && recording == nil && gripStarted { grip.stop(); gripStarted = false }
    }

    /// Le clavier vient d'apparaître.
    func appeared() {
        visible = true
        perfStart()
        typedOnSide = 0
        showEmoji = false
        if autoOn { startGrip() }
        page = .letters
        shift = .off
        refreshShift()
        KBFeedback.shared.prepare()
        builtFor = .zero
        setNeedsLayout()
    }

    /// La situation (Duo fermé ou ouvert, portrait ou paysage) et l'étalonnage qui va avec.
    private var gripContext = "closed-portrait"
    /// La charnière du Duo : fermé (true), ouvert (false), inconnue (nil).
    private var hingeClosed: Bool?
    private var hingeWatched = false

    /// La taille de l'écran réellement utilisé (dans le bon sens : portrait ou paysage).
    private var screenSize: CGSize {
        // La fenêtre suit l'écran réellement utilisé ; l'écran de la scène peut rester l'ancien.
        let win = window?.bounds.size ?? .zero
        if win.width > 0 && win.height > bounds.height * 1.8 { return win }
        return window?.windowScene?.screen.bounds.size ?? bounds.size
    }

    /// La charnière répond aussi dans le clavier : on retient la taille de cet écran.
    private func learnScreen() {
        guard let closed = hingeClosed, let scr = window?.windowScene?.screen else { return }
        let key = closed ? "closed" : "open"
        let short = Double(min(scr.bounds.width, scr.bounds.height))
        let px = Double(min(scr.nativeBounds.width, scr.nativeBounds.height))
        guard short > 0, abs((settings.screenWidths[key] ?? 0) - short) > 1 || abs((settings.screenWidths[key + "Px"] ?? 0) - px) > 1 else { return }
        settings.screenWidths[key] = short
        settings.screenWidths[key + "Px"] = px
        input?.kbSettingsChanged(settings)
    }

    private func watchHinge() {
        guard !hingeWatched else { return }
        hingeWatched = true
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                switch update.hinge?.status {
                case .closed?: self.hingeClosed = true
                case .partiallyOpen?, .fullyOpen?: self.hingeClosed = false
                default: self.hingeClosed = nil
                }
                self.learnScreen()
                self.updateGripContext()
                self.builtFor = .zero
                self.setNeedsLayout()
            })
        }
    }

    private func updateGripContext() {
        let screen = screenSize
        let nb = window?.windowScene?.screen.nativeBounds ?? .zero
        let native: Double? = nb.width > 0 ? Double(min(nb.width, nb.height)) : nil
        var c = KBSettings.context(screen: screen, closed: hingeClosed, known: settings.screenWidths, native: native)
        // Si la taille de l'écran n'est pas sûre, la largeur du clavier (toute la largeur de l'écran) tranche.
        let w = Double(bounds.width)
        if hingeClosed == nil, w > 50, screen.width <= 0 || abs(Double(min(screen.width, screen.height)) - w) > 2,
           let o = settings.screenWidths["open"], let cl = settings.screenWidths["closed"] {
            let portrait = !c.hasSuffix("landscape")
            if portrait { c = abs(w - o) < abs(w - cl) ? "open-portrait" : "closed-portrait" }
        }
        // Le tutoriel montre toujours le fonctionnement de l'écran extérieur.
        if demoOneHand { c = "closed-portrait" }
        if let demoContext { c = demoContext }
        gripContext = c
        grip.angleOffset = kbAngleOffset(window?.windowScene?.interfaceOrientation)
        grip.guessUncalibrated = false
        grip.defaultTilt = followsHand
        let r = settings.roll("right", context: gripContext), l = settings.roll("left", context: gripContext)
        if let r, let l, abs(kbWrap(r - l)) >= 3 {
            let mid = kbWrap(r + kbWrap(l - r) / 2)
            grip.tiltMid = mid
            grip.rightNegative = kbWrap(r - mid) < 0
            grip.tiltGap = abs(kbWrap(r - l))
        } else {
            // Sans réglage : le téléphone penche du côté de la main qui le tient (haut vers la gauche : main gauche).
            grip.tiltMid = 0
            // Écran intérieur du Duo : ses axes sont inversés par rapport à l'écran extérieur (constaté sur le Duo).
            grip.rightNegative = gripContext.hasPrefix("open")
            grip.tiltGap = 0
        }
        // Deux classes : pouce droit, pouce gauche. Les appuis « deux mains » comptent selon leur côté.
        let t = settings.taps[gripContext] ?? [:]
        let both = (t["two"] ?? []).filter { $0.count == GripDetector.featureCount }
        let thumbs: [String: [[Double]]] = [
            "right": (t["right"] ?? []) + both.filter { $0[8] >= 0.5 },
            "left": (t["left"] ?? []) + both.filter { $0[8] < 0.5 },
        ]
        grip.tapModel = KBTapModel(thumbs)
        grip.swipeModel = KBTapModel(settings.swipes[gripContext] ?? [:], kind: .swipe)
        var postures: [KBGrip: (roll: Double, incline: Double)] = [:]
        for (k, p) in settings.calib[gripContext] ?? [:] where p.count == 2 {
            guard let g = KBGrip(rawValue: k) else { continue }
            postures[g] = (settings.roll(k, context: gripContext) ?? p[0], p[1])
        }
        grip.postures = postures
        // Les habitudes : les mesures du réglage servent d'exemples de départ, l'usage ajoute les siens.
        let ctx = gripContext
        var seeds: [KBHabit] = []
        if let r = postures[.right] { seeds.append(KBHabit(roll: r.roll, incline: r.incline, right: true, weight: 4)) }
        if let l = postures[.left] { seeds.append(KBHabit(roll: l.roll, incline: l.incline, right: false, weight: 4)) }
        let sig = seeds.map { String(format: "%.1f/%.1f", $0.roll, $0.incline) }.joined(separator: "|")
        KBHabits.shared.sync(context: ctx, signature: sig)
        habitSeeds = seeds
        grip.habitReady = followsHand && KBHabits.shared.ready(context: ctx, seeds: seeds)
        grip.habitVote = { roll, inc in KBHabits.shared.vote(context: ctx, roll: roll, incline: inc, seeds: seeds) }
    }

    private var habitSeeds: [KBHabit] = []
    /// Les lettres tapées depuis que le clavier est de ce côté (sans correction : le côté était le bon).
    private var typedOnSide = 0

    /// Retient la prise en main du moment pour ce côté. `correction` : choisi à la main (exemple fort).
    private func learnHabit(right: Bool, correction: Bool) {
        guard followsHand, recording == nil, !demoOneHand, let p = grip.currentPosture else { return }
        KBHabits.shared.add(context: gripContext, roll: p.roll, incline: p.incline, right: right,
                            weight: correction ? 3 : 1, correction: correction)
        grip.habitReady = KBHabits.shared.ready(context: gripContext, seeds: habitSeeds)
    }

    /// Une lettre tapée avec le petit clavier d'un côté : après quelques lettres sans correction, c'est une habitude.
    private func countTyped() {
        guard autoOn, followsHand, layoutMode.isOneHand, !settings.autoTwo else { return }
        typedOnSide += 1
        if typedOnSide == 8 || typedOnSide == 40 { learnHabit(right: settings.autoRight, correction: false) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        watchHinge()
        updateGripContext()
    }

    /// Le clavier disparaît : on coupe les capteurs.
    func disappeared() {
        visible = false
        perfLink?.invalidate()
        perfLink = nil
        grip.stop()
        gripStarted = false
        idleTimer?.invalidate()
    }

    /// Étalonnage dans l'app : la prise qu'on enregistre (le clavier ne bouge pas, chaque appui est envoyé).
    private(set) var recording: KBGrip?
    func setRecording(_ g: KBGrip?, _ handler: (([Double]) -> Void)?, swipes: (([Double]) -> Void)? = nil) {
        recording = g
        grip.onSample = g == nil ? nil : handler
        grip.onSwipeSample = g == nil ? nil : swipes
        if visible && g != nil && !gripStarted { startGrip() }
    }

    private var gripStarted = false
    private func startGrip() {
        gripStarted = true
        grip.onGrip = { [weak self] g in self?.gripDetected(g) }
        grip.start { [weak self] g in
            guard let self, let g, self.autoOn else { return }
            // Sans posture « deux mains » étalonnée, l'inclinaison ne fait pas quitter le mode deux mains.
            if self.settings.autoTwo && self.settings.calib[self.gripContext]?["two"] == nil { return }
            self.applyGrip(g)
        }
    }

    private func gripDetected(_ g: KBGrip) {
        guard autoOn else { return }
        pendingGrip = g
        scheduleGrip()
    }

    /// On ne déplace pas les touches sous le doigt : on attend une petite pause dans la frappe.
    private func scheduleGrip() {
        idleTimer?.invalidate()
        guard pendingGrip != nil, tracks.isEmpty else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self, let g = self.pendingGrip, self.tracks.isEmpty else { return }
            self.applyGrip(g)
        }
    }

    private func applyGrip(_ g: KBGrip) {
        pendingGrip = nil
        // Pendant qu'on ajuste le clavier, il ne bouge pas tout seul.
        guard !adjusting else { return }
        var s = settings
        s.autoTwo = g == .two
        if g != .two { s.autoRight = g == .right }
        grip.current = g
        guard s.autoTwo != settings.autoTwo || s.autoRight != settings.autoRight else { return }
        typedOnSide = 0
        settings = s
        save()
        layoutIfNeeded()
    }

    /// Le lexique de l'utilisateur (contacts, remplacements de texte).
    func setLexicon(_ lexicon: UILexicon) {
        suggest.setLexicon(lexicon)
        suggestQueue.async { [bgSuggest] in bgSuggest.setLexicon(lexicon) }
    }

    /// Le texte a changé (curseur déplacé, autre champ) : on revoit la majuscule et les suggestions.
    func textChanged() {
        refreshSuggestionsSoon()
        // Juste après une de nos touches, rien à relire dans le champ : la frappe reste légère.
        if ProcessInfo.processInfo.systemUptime - lastKeyTime < 0.25 { return }
        refreshShift()
        cursorMoved()
    }

    /// Le curseur a bougé sans qu'on tape : on vient de toucher la zone de texte, clavier déjà ouvert.
    /// Comme à l'ouverture, le clavier va du côté de la main qui tient le téléphone.
    private var lastReread: TimeInterval = 0
    private func cursorMoved() {
        let now = ProcessInfo.processInfo.systemUptime
        guard autoOn, visible, !adjusting, !showEmoji, tracks.isEmpty, recording == nil,
              now - lastKeyTime > 0.8, now - lastReread > 0.4,
              followsHand else { return }
        lastReread = now
        grip.reread { [weak self] g in
            guard let self, let g, g != .two else { return }
            self.applyGrip(g)
        }
    }

    private func save() {
        input?.kbSettingsChanged(settings)
        configure(settings: settings, pro: pro)
    }

    private func setMode(_ m: KBMode) {
        if (m == .auto || m == .split) && !pro {
            guard let input else { flash(L("Foldboard Pro: open the app to unlock")); return }
            input.kbRecheckPro { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.pro = true
                    self.setMode(m)
                } else if !input.kbFullAccess {
                    self.flash(L("Allow Full Access to use Foldboard Pro"))
                } else {
                    self.flash(L("Foldboard Pro: open the app to unlock"))
                }
            }
            return
        }
        settings.mode = m
        grip.locked = false
        save()
    }

    /// Un toucher dans la place libre : à gauche → clavier à gauche, à droite → à droite, au centre → au milieu
    /// (deux moitiés sur le Duo déplié). Pas besoin d'étalonnage.
    private var placeTouches: [UITouch: (CGPoint, TimeInterval)] = [:]
    private var lastKeyTime: TimeInterval = 0

    private func placeByTap(at p: CGPoint) {
        let W = bounds.width
        // Écran intérieur : le clavier est coupé en deux (ou entier), il n'y a rien à placer.
        guard W > 0, !(settings.mode == .auto && !followsHand) else { return }
        let center = abs(p.x - W / 2) < W * 0.17 && layoutMode.isOneHand
        let auto = eff.mode == .auto
        var s = settings
        if center {
            if auto { s.autoTwo = true } else { s.mode = pro && splitAllowed ? .split : .full }
            grip.current = .two
        } else {
            let right = p.x > W / 2
            if auto { s.autoTwo = false; s.autoRight = right } else { s.mode = right ? .right : .left }
            grip.current = right ? .right : .left
            // Le clavier retient comment le téléphone penche quand tu le veux de ce côté : il sortira du bon
            // côté tout seul la prochaine fois.
            if let a = grip.currentAngle { s.learn(roll: a, right: right, context: gripContext) }
            if auto { learnHabit(right: right, correction: true) }
            typedOnSide = 0
        }
        guard s != settings else { return }
        KBFeedback.shared.tap(sound: .off, haptics: max(0.4, eff.haptics))
        // Placé à la main : il reste là (plus de suivi automatique jusqu'à la prochaine apparition du clavier).
        grip.locked = true
        settings = s
        save()
        layoutIfNeeded()
    }

    @objc private func showGripInfo(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let names = ["closed-portrait": L("Closed · portrait"), "open-portrait": L("Open · portrait"),
                     "open-landscape": L("Open · landscape"), "closed-landscape": L("Closed · landscape")]
        let n = settings.taps[gripContext]?.values.filter { $0.count >= 6 }.count ?? 0
        let state = grip.tapModel != nil ? String(format: L("calibrated (%lld grips)"), n)
            : (grip.calibrated ? L("tilt only") : L("not calibrated"))
        let habits = String(format: L("%lld habits learned"), KBHabits.shared.count(context: gripContext))
        flash((names[gripContext] ?? gripContext) + " · " + state + " · " + habits)
    }

    /// Écran intérieur : passe d'une disposition à l'autre (portrait : une main ⇄ deux moitiés ; paysage : entier ⇄ deux moitiés).
    private func toggleBig() {
        if gripContext == "open-portrait" { settings.openSplit.toggle() } else { settings.openLandSplit.toggle() }
        settings.openFull = false
        KBFeedback.shared.tap(sound: .off, haptics: max(0.4, eff.haptics))
        save()
        layoutIfNeeded()
    }

    private func flipSide() {
        switch eff.mode {
        case .auto:
            settings.autoRight = settings.autoTwo ? true : !settings.autoRight
            settings.autoTwo = false
            grip.current = settings.autoRight ? .right : .left
            grip.locked = true
            // Le choix fait à la main apprend à la détection comment tu tiens le téléphone.
            if let a = grip.currentAngle { settings.learn(roll: a, right: settings.autoRight, context: gripContext) }
            learnHabit(right: settings.autoRight, correction: true)
            typedOnSide = 0
        case .left: settings.mode = .right
        case .right: settings.mode = .left
        default: return
        }
        save()
        layoutIfNeeded()
    }

    private func flash(_ text: String) {
        toast.text = "  " + text + "  "
        toast.backgroundColor = theme.accent
        toast.textColor = .white
        toast.sizeToFit()
        let w = min(topBar.bounds.width - 16, toast.bounds.width + 8)
        toast.frame = CGRect(x: (topBar.bounds.width - w) / 2, y: 7, width: w, height: 28)
        toast.alpha = 1
        UIView.animate(withDuration: 0.4, delay: 2.2, options: [], animations: { self.toast.alpha = 0 })
    }

    // MARK: Mise en page

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != builtFor, bounds.width > 50 else { return }
        builtFor = bounds.size
        updateGripContext()
        rebuild()
    }

    private var isRight: Bool {
        eff.mode == .right || (eff.mode == .auto && eff.autoRight)
    }

    /// Deux moitiés seulement sur un écran large : l'écran déplié du Duo (presque carré), ou un iPhone en paysage.
    /// Sur l'écran extérieur ou un iPhone classique en portrait, le clavier reste en pleine largeur.
    private var splitAllowed: Bool {
        bounds.width >= 600 || (gripContext.hasPrefix("open") && bounds.width >= 360)
    }

    /// Le mode réellement possible à cette largeur (deux mains : il faut de la place).
    /// Tutoriel : le clavier se comporte comme sur l'écran extérieur, même Duo ouvert.
    var demoOneHand = false
    /// Captures : la situation imposée (par exemple « open-portrait » sur un écran qui ne l'est pas).
    var demoContext: String?

    /// Le clavier suit la main ici : écran extérieur, ou écran intérieur en portrait sans les deux moitiés.
    private var followsHand: Bool {
        gripContext.hasPrefix("closed") || (gripContext == "open-portrait" && !settings.openSplit)
    }

    private var layoutMode: KBMode {
        // Écran intérieur du Duo, comme le clavier d'Apple : deux moitiés en portrait, entier en paysage.
        if settings.mode == .auto {
            // En portrait, au choix : deux moitiés, ou le petit clavier qui suit la main (comme sur l'écran extérieur).
            if gripContext == "open-portrait" && settings.openSplit { return pro && splitAllowed ? .split : .full }
            // En paysage, au choix : le clavier entier, ou deux moitiés.
            if gripContext == "open-landscape" { return settings.openLandSplit && pro && splitAllowed ? .split : .full }
        }
        if eff.mode == .auto && eff.autoTwo { return splitAllowed ? .split : .full }
        if eff.mode == .split && !splitAllowed { return .full }
        return eff.mode
    }

    /// Étalonnage : un halo lumineux autour du doigt, à chaque appui (façon Face ID).
    private func halo(at p: CGPoint, radius: CGFloat) {
        let r = max(26, radius * 1.5 + 14)
        for (i, scale) in [(0, 1.0), (1, 1.35)] {
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)).cgPath
            ring.position = p
            ring.fillColor = i == 0 ? theme.accent.withAlphaComponent(0.18).cgColor : UIColor.clear.cgColor
            ring.strokeColor = (i == 0 ? theme.accent : UIColor(red: 0.35, green: 0.9, blue: 0.75, alpha: 1)).cgColor
            ring.lineWidth = i == 0 ? 3 : 2
            ring.shadowColor = theme.accent.cgColor
            ring.shadowRadius = 10
            ring.shadowOpacity = 0.9
            ring.shadowOffset = .zero
            layer.addSublayer(ring)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.55
            grow.toValue = scale * 1.25
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 0.55 + Double(i) * 0.15
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            ring.add(group, forKey: "halo")
            DispatchQueue.main.asyncAfter(deadline: .now() + group.duration + 0.05) { ring.removeFromSuperlayer() }
        }
    }

    /// Part de la largeur pour le clavier à une main : plus compact sur le Duo déplié (encore plus en paysage).
    private var oneHandFraction: CGFloat {
        guard gripContext.hasPrefix("open") else { return CGFloat(eff.oneHandWidth) }
        let f = CGFloat(eff.oneHandWidthOpen)
        return gripContext.hasSuffix("landscape") ? f * 0.8 : f
    }

    private let emojiBoard = EmojiBoard()
    private var showEmoji = false

    // MARK: Ajuster le clavier

    private let adjust = AdjustOverlay()
    /// La hauteur du clavier vient de changer pendant le réglage : l'hôte suit.
    var onPreferredHeightChange: (() -> Void)?
    private var adjustingHeight = false
    private var adjustBackup: KBSettings?
    private var adjusting: Bool { adjustBackup != nil }

    private func startAdjust() {
        guard layoutMode.isOneHand || layoutMode == .split else {
            flash(L("Choose one hand or two hands to adjust"))
            return
        }
        showEmoji = false
        adjustingHeight = false
        adjustBackup = settings
        if adjust.superview == nil {
            adjust.onPan = { [weak self] g, dx, dy in self?.adjustBy(g, dx, dy) }
            adjust.onDone = { [weak self] in self?.endAdjust(keep: true) }
            adjust.onCancel = { [weak self] in self?.endAdjust(keep: false) }
            adjust.onReset = { [weak self] in self?.resetAdjust() }
            addSubview(adjust)
        }
        adjust.isHidden = false
        builtFor = .zero
        layoutIfNeeded()
        refreshAdjust()
    }

    private func refreshAdjust() {
        guard adjusting else { return }
        adjust.frame = bounds
        bringSubviewToFront(adjust)
        let W = bounds.width
        let text: String
        if adjustingHeight {
            text = String(format: L("Key height %lld pt"), Int(eff.keyHeight.rounded()))
        } else if layoutMode == .split {
            text = String(format: L("Width %lld %%"), Int((eff.splitWidth * 100).rounded()))
        } else if let b = blocks.first {
            let m = Int((isRight ? W - b.maxX : b.minX).rounded())
            text = String(format: L(isRight ? "%lld pt from the right" : "%lld pt from the left"), m)
        } else {
            text = ""
        }
        adjust.configure(blocks: blocks, split: layoutMode == .split, accent: theme.accent, text: text)
    }

    private func adjustBy(_ g: AdjustOverlay.Grab, _ dx: CGFloat, _ dy: CGFloat) {
        let W = bounds.width
        guard W > 0 else { return }
        var s = settings
        if dy != 0 {
            // De haut en bas : la hauteur des touches (vers le haut : plus grandes).
            adjustingHeight = true
            s.keyHeight = min(60, max(34, s.keyHeight - Double(dy) / 4))
            configure(settings: s, pro: pro)
            onPreferredHeightChange?()
            layoutIfNeeded()
            refreshAdjust()
            return
        }
        adjustingHeight = false
        switch g {
        case .leftHalf, .rightHalf:
            let hw = W * CGFloat(s.splitWidth) + (g == .leftHalf ? dx : -dx)
            s.splitWidth = Double(min(0.48, max(0.22, hw / W)))
        default:
            guard var b = blocks.first else { return }
            switch g {
            case .leftEdge: b.origin.x += dx; b.size.width -= dx
            case .rightEdge: b.size.width += dx
            default: b.origin.x += dx
            }
            b.size.width = min(W - 2 * pad, max(220, b.width))
            b.origin.x = min(W - b.width, max(0, b.minX))
            let frac = Double(b.width / W)
            if gripContext.hasPrefix("open") {
                s.oneHandWidthOpen = min(0.9, max(0.4, gripContext.hasSuffix("landscape") ? frac / 0.8 : frac))
            } else {
                s.oneHandWidth = min(0.95, max(0.45, frac))
            }
            s.edgeMargin = Double(isRight ? W - b.maxX : b.minX)
        }
        configure(settings: s, pro: pro)
        layoutIfNeeded()
        refreshAdjust()
    }

    private func resetAdjust() {
        var s = settings
        let d = KBSettings()
        s.edgeMargin = d.edgeMargin
        s.oneHandWidth = d.oneHandWidth
        s.oneHandWidthOpen = d.oneHandWidthOpen
        s.splitWidth = d.splitWidth
        s.keyHeight = d.keyHeight
        adjustingHeight = false
        configure(settings: s, pro: pro)
        onPreferredHeightChange?()
        layoutIfNeeded()
        refreshAdjust()
    }

    private func endAdjust(keep: Bool) {
        let backup = adjustBackup
        adjustBackup = nil
        adjust.isHidden = true
        adjustingHeight = false
        if !keep, let backup { settings = backup }
        save()
        onPreferredHeightChange?()
    }

    private func closeEmoji() {
        showEmoji = false
        builtFor = .zero
        rebuild()
    }

    private func rebuild() {
        let oldBlocks = blocks
        // Les touches vont changer : les appuis en cours s'arrêtent là.
        for tr in tracks.values {
            tr.done = true
            tr.longTimer?.invalidate()
            tr.repeatTimer?.invalidate()
        }
        // Thème automatique : le fond du clavier de l'iPhone se voit partout, jusqu'aux bords de l'écran.
        // Pas tout à fait transparent : dans les autres apps, iOS ne transmet pas au clavier les appuis tombés sur
        // une zone transparente (entre les touches), et des lettres se perdaient.
        backgroundColor = theme.id == "auto" ? UIColor(white: 0, alpha: 0.012) : theme.background
        cells.forEach { $0.view.removeFromSuperview() }
        cells = []
        let W = bounds.width
        let top = Self.topBarHeight + 6
        let areaH = CGFloat(rowCount) * keyH + CGFloat(rowCount - 1) * vgap
        let margin = CGFloat(eff.edgeMargin)
        let rows = KBLayouts.rows(page, layout: eff.layout)
        let globe = input?.kbNeedsGlobe ?? false

        // Les emojis prennent la place des touches (à une main : du côté du pouce).
        emojiBoard.isHidden = !showEmoji
        if showEmoji {
            var area = CGRect(x: pad, y: top, width: W - 2 * pad, height: areaH)
            if layoutMode.isOneHand {
                let bw = min(W - 2 * pad, max(min(W - 2 * pad, 250), W * oneHandFraction))
                let x = isRight ? W - margin - bw : margin
                area = CGRect(x: max(0, x), y: top, width: bw, height: areaH)
            }
            blocks = [area]
            panelRect = .zero
            emojiBoard.frame = area
            emojiBoard.textColor = theme.text
            emojiBoard.keyColor = theme.special
            emojiBoard.accent = theme.accent
            emojiBoard.configure(favorites: eff.emojis)
            emojiBoard.reloadRecent()
            rebuildPanel()
            layoutTopBar()
            return
        }

        switch layoutMode {
        case .full:
            let b = CGRect(x: pad, y: top, width: W - 2 * pad, height: areaH)
            blocks = [b]
            panelRect = .zero
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout)], in: b, align: 0)
        case .left, .right, .auto:
            let bw = min(W - 2 * pad, max(min(W - 2 * pad, 250), W * oneHandFraction))
            let x = isRight ? W - margin - bw : margin
            let b = CGRect(x: max(0, x), y: top, width: bw, height: areaH)
            blocks = [b]
            panelRect = isRight
                ? CGRect(x: 6, y: top, width: max(0, b.minX - 12), height: areaH)
                : CGRect(x: b.maxX + 6, y: top, width: max(0, W - b.maxX - 12), height: areaH)
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout, compact: true)], in: b, align: 0)
        case .split:
            let hw = W * CGFloat(eff.splitWidth)
            let l = CGRect(x: margin, y: top, width: hw, height: areaH)
            let r = CGRect(x: W - margin - hw, y: top, width: hw, height: areaH)
            blocks = [l, r]
            panelRect = CGRect(x: l.maxX + 10, y: top, width: max(0, r.minX - l.maxX - 20), height: areaH)
            var left: [KeyRow] = []
            var right: [KeyRow] = []
            for row in rows {
                let total = row.keys.reduce(0) { $0 + $1.width } + 2 * row.inset
                var acc = row.inset
                var lk: [KeySpec] = []
                var rk: [KeySpec] = []
                for k in row.keys {
                    let center = acc + k.width / 2
                    if center <= total / 2 { lk.append(k) } else { rk.append(k) }
                    acc += k.width
                }
                left.append(KeyRow(keys: lk))
                right.append(KeyRow(keys: rk))
            }
            let maxL = left.map { $0.keys.reduce(0) { $0 + $1.width } }.max() ?? 5
            let maxR = right.map { $0.keys.reduce(0) { $0 + $1.width } }.max() ?? 5
            var lb: [KeySpec] = [KeySpec(kind: .page(page == .letters ? .numbers : .letters), width: 1.5)]
            if globe { lb.append(KeySpec(kind: .globe, width: 1.1)) }
            lb.append(KeySpec(kind: .emoji, width: 1.1))
            lb.append(KeySpec(kind: .char(eff.layout == .azerty && page == .letters ? "," : "."), width: 1))
            let used = lb.reduce(0) { $0 + $1.width }
            lb.append(KeySpec(kind: .space, width: max(1.5, maxL - used)))
            left.append(KeyRow(keys: lb))
            right.append(KeyRow(keys: [KeySpec(kind: .space, width: max(1.5, maxR - 2)), KeySpec(kind: .ret, width: 2)]))
            place(left, in: l, align: -1, units: maxL)
            place(right, in: r, align: 1, units: maxR)
        }
        rebuildPanel()
        layoutTopBar()
        updateLabels()
        if adjusting { refreshAdjust() }
        slide(from: oldBlocks)
    }

    /// Le clavier change de côté, revient au milieu ou passe en grand : chaque touche glisse de son ancienne place
    /// à la nouvelle (pas de saut).
    private func slide(from old: [CGRect]) {
        guard visible, !adjusting, window != nil, old.count == 1, blocks.count == 1,
              abs(old[0].height - blocks[0].height) < 2 else { return }
        let o = old[0], n = blocks[0]
        let dx = o.midX - n.midX
        let sx = max(0.3, min(3, o.width / max(1, n.width)))
        guard abs(dx) > 8 || abs(sx - 1) > 0.05 else { return }
        let views = cells.map(\.view)
        UIView.performWithoutAnimation {
            for v in views {
                // Chaque touche part de là où elle était dans l'ancien bloc, à l'ancienne taille.
                let from = o.midX + (v.center.x - n.midX) * sx
                v.transform = CGAffineTransform(translationX: from - v.center.x, y: 0).scaledBy(x: sx, y: 1)
            }
            panel.alpha = 0
        }
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.3,
                       options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            views.forEach { $0.transform = .identity }
        }
        UIView.animate(withDuration: 0.22, delay: 0.18, options: [.allowUserInteraction]) { self.panel.alpha = 1 }
    }

    /// Place des rangées dans un bloc. `align` : -1 collé à gauche, 1 collé à droite, 0 centré.
    private func place(_ rows: [KeyRow], in b: CGRect, align: Int, units: Double = 10) {
        let unit = (b.width - 2 * pad) / CGFloat(units)
        for (i, row) in rows.enumerated() {
            let y = b.minY + CGFloat(i) * (keyH + vgap)
            let rowW = CGFloat(row.keys.reduce(0) { $0 + $1.width } + 2 * row.inset) * unit
            var x: CGFloat
            switch align {
            case -1: x = b.minX + pad
            case 1: x = b.maxX - pad - rowW
            default: x = b.minX + pad + (b.width - 2 * pad - rowW) / 2
            }
            x += CGFloat(row.inset) * unit
            var rowCells: [Cell] = []
            for k in row.keys {
                let w = CGFloat(k.width) * unit
                let f = CGRect(x: x + gap / 2, y: y, width: w - gap, height: keyH)
                let special: Bool
                switch k.kind {
                case .char: special = false
                case .space: special = false
                default: special = true
                }
                let v = KeyView(spec: k, special: special)
                v.frame = f
                insertSubview(v, belowSubview: bubble)
                let hit = CGRect(x: x, y: y - vgap / 2, width: w, height: keyH + vgap)
                rowCells.append(Cell(view: v, frame: f, hit: hit))
                x += w
            }
            // Les touches du bord prennent aussi l'espace jusqu'au bord du bloc.
            if var first = rowCells.first {
                first.hit = CGRect(x: b.minX, y: first.hit.minY, width: first.hit.maxX - b.minX, height: first.hit.height)
                rowCells[0] = first
            }
            if var last = rowCells.last {
                last.hit = CGRect(x: last.hit.minX, y: last.hit.minY, width: b.maxX - last.hit.minX, height: last.hit.height)
                rowCells[rowCells.count - 1] = last
            }
            cells.append(contentsOf: rowCells)
        }
    }

    private func layoutTopBar() {
        topBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.topBarHeight)
        let h = Self.topBarHeight
        modeButton.frame = CGRect(x: 6, y: 0, width: 40, height: h)
        modeButton.setImage(UIImage(systemName: eff.mode.symbol), for: .normal)
        modeButton.tintColor = theme.text.withAlphaComponent(0.7)
        modeButton.menu = modeMenu()
        modeButton.accessibilityLabel = L("Keyboard position")
        // La flèche ⇆ : changer de côté, ou revenir à une main depuis le milieu.
        let oneHand = layoutMode.isOneHand || (eff.mode == .auto && followsHand)
        flipButton.isHidden = !oneHand
        // En couleur : le clavier est verrouillé là où tu l'as mis.
        flipButton.tintColor = grip.locked && eff.mode == .auto ? theme.accent : theme.text.withAlphaComponent(0.7)
        flipButton.frame = CGRect(x: 46, y: 0, width: oneHand ? 36 : 0, height: h)
        // Écran intérieur : un bouton pour passer d'une disposition à l'autre.
        // Portrait : petit clavier qui suit la main ⇄ deux moitiés. Paysage : clavier entier ⇄ deux moitiés.
        let open = gripContext.hasPrefix("open")
        let bigShown = open && settings.mode == .auto && pro
        let splitNow = gripContext == "open-portrait" ? settings.openSplit : settings.openLandSplit
        bigButton.isHidden = !bigShown
        bigButton.setImage(UIImage(systemName: splitNow ? (gripContext == "open-portrait" ? "keyboard.onehanded.right" : "keyboard") : "rectangle.split.2x1"), for: .normal)
        bigButton.accessibilityLabel = splitNow ? L("One keyboard") : L("Split keyboard")
        bigButton.tintColor = theme.text.withAlphaComponent(0.7)
        bigButton.frame = CGRect(x: flipButton.frame.maxX, y: 0, width: bigShown ? 36 : 0, height: h)
        hideButton.tintColor = theme.text.withAlphaComponent(0.7)
        hideButton.frame = CGRect(x: bounds.width - 46, y: 0, width: 40, height: h)
        adjustButton.tintColor = theme.text.withAlphaComponent(0.7)
        adjustButton.frame = CGRect(x: bounds.width - 46 - 36, y: 0, width: 36, height: h)
        let compact = layoutMode.isOneHand && !showEmoji
        let globe = input?.kbNeedsGlobe ?? false
        emojiButton.isHidden = !compact
        globeButton.isHidden = !(compact && globe)
        emojiButton.tintColor = theme.text.withAlphaComponent(0.7)
        globeButton.tintColor = theme.text.withAlphaComponent(0.7)
        emojiButton.frame = CGRect(x: adjustButton.frame.minX - (compact ? 36 : 0), y: 0, width: compact ? 36 : 0, height: h)
        globeButton.frame = CGRect(x: emojiButton.frame.minX - (compact && globe ? 36 : 0), y: 0, width: compact && globe ? 36 : 0, height: h)
        let cx = max(flipButton.frame.maxX, bigButton.frame.maxX) + 4
        chips.frame = CGRect(x: cx, y: 0, width: max(0, globeButton.frame.minX - cx - 4), height: h)

        rebuildChips()
    }

    private func rebuildChips() {
        let h = Self.topBarHeight
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !suggestionItems.isEmpty {
            // Trois suggestions de mots, de même largeur ; la meilleure en gras (celle que l'espace appliquera).
            let n = CGFloat(suggestionItems.count)
            let w = max(60, (chips.bounds.width - (2 * n - 2) * 8 - (n - 1)) / n)
            for (i, item) in suggestionItems.enumerated() {
                let b = UIButton(type: .system)
                b.setTitle(i == 0 && suggestionBest != nil ? "“\(item)”" : item, for: .normal)
                b.titleLabel?.font = eff.font.ui(size: 16, weight: i == suggestionBest ? .bold : .regular)
                b.titleLabel?.lineBreakMode = .byTruncatingTail
                b.setTitleColor(theme.text, for: .normal)
                b.backgroundColor = i == suggestionBest ? theme.key.withAlphaComponent(0.55) : .clear
                b.layer.cornerRadius = 12
                b.layer.cornerCurve = .continuous
                b.addAction(UIAction { [weak self] _ in self?.applySuggestion(i) }, for: .touchUpInside)
                if i > 0 {
                    let line = UIView()
                    line.backgroundColor = theme.text.withAlphaComponent(0.18)
                    line.widthAnchor.constraint(equalToConstant: 1).isActive = true
                    line.heightAnchor.constraint(equalToConstant: 20).isActive = true
                    chipStack.addArrangedSubview(line)
                }
                chipStack.addArrangedSubview(b)
                b.widthAnchor.constraint(equalToConstant: w).isActive = true
                b.heightAnchor.constraint(equalToConstant: 32).isActive = true
            }
            chipStack.frame = CGRect(x: 0, y: (h - 32) / 2, width: w * n + (2 * n - 2) * 8 + (n - 1), height: 32)
            chips.contentSize = CGSize(width: chipStack.frame.width, height: h)
            chips.contentOffset = .zero
            return
        }
        let showPhrasesInBar = !(layoutMode.isOneHand && eff.sidePanel == .phrases && panelRect.width >= 90)
        if showPhrasesInBar {
            for p in eff.phrases where !p.isEmpty {
                let b = UIButton(type: .system)
                var cfg = UIButton.Configuration.plain()
                cfg.title = p
                cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
                cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [font = eff.font] a in
                    var a = a
                    a.font = font.ui(size: 15, weight: .medium)
                    return a
                }
                b.configuration = cfg
                b.tintColor = theme.text
                b.backgroundColor = theme.key.withAlphaComponent(0.6)
                b.layer.cornerRadius = 15
                b.layer.cornerCurve = .continuous
                b.addAction(UIAction { [weak self] _ in self?.insertPhrase(p) }, for: .touchUpInside)
                chipStack.addArrangedSubview(b)
                b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            }
        }
        let size = chipStack.systemLayoutSizeFitting(CGSize(width: UIView.layoutFittingCompressedSize.width, height: 30))
        chipStack.frame = CGRect(x: 0, y: (h - 30) / 2, width: size.width, height: 30)
        chips.contentSize = CGSize(width: size.width, height: h)
    }

    private func modeMenu() -> UIMenu {
        let names: [KBMode: String] = [.auto: L("Follows your hand"), .left: L("One hand, left"), .right: L("One hand, right"),
                                       .full: L("Full width"), .split: L("Two hands")]
        let actions = KBMode.allCases.map { m in
            UIAction(title: names[m] ?? m.rawValue,
                     subtitle: (m == .auto || m == .split) && !pro ? "Foldboard Pro" : nil,
                     image: UIImage(systemName: m.symbol),
                     state: m == eff.mode ? .on : .off) { [weak self] _ in self?.setMode(m) }
        }
        let adjustAction = UIAction(title: L("Adjust the keyboard"), image: UIImage(systemName: "arrow.left.and.right.square")) { [weak self] _ in
            self?.startAdjust()
        }
        var extra: [UIMenuElement] = [adjustAction]
        if gripContext == "open-portrait" {
            // Duo ouvert en portrait : l'utilisateur choisit entre deux moitiés et le petit clavier qui suit la main.
            extra.insert(UIAction(title: L("Split when the Duo is open"), image: UIImage(systemName: "rectangle.split.2x1"),
                                  state: settings.openSplit ? .on : .off) { [weak self] _ in
                guard let self else { return }
                if !self.pro && !self.settings.openSplit { self.setMode(.split); return }
                self.settings.openSplit.toggle()
                self.settings.mode = .auto
                self.save()
                self.layoutIfNeeded()
            }, at: 0)
        }
        return UIMenu(title: L("Keyboard position"), children: [UIMenu(options: .displayInline, children: actions)] + extra)
    }

    private func rebuildPanel() {
        panel.subviews.forEach { $0.removeFromSuperview() }
        panel.frame = panelRect
        guard panelRect.width >= 44, panelRect.height >= 44, eff.sidePanel != .none else { return }
        let w = panelRect.width
        let h = panelRect.height
        if layoutMode.isOneHand {
            // Comme le clavier d'Apple sur le Duo : les emojis au bord de l'écran ; un toucher dans la place libre
            // envoie le clavier de ce côté, ou au milieu près du centre.
            let cell: CGFloat = 44
            // Écran étroit : pas d'emojis sur le côté, toute la place libre sert à placer le clavier.
            let cols = w >= 170 ? 2 : (w >= 110 ? 1 : 0)
            let rowsN = max(1, min(4, Int(h / cell)))
            var list = KBEmoji.recent
            for e in eff.emojis where !list.contains(e) { list.append(e) }
            let count = min(list.count, cols * rowsN)
            let gridW = cell * CGFloat(cols)
            let gridH = cell * CGFloat(rowsN)
            let ox = isRight ? 2 : w - gridW - 2
            let oy = max(0, (h - gridH) / 2)
            for i in 0..<count {
                let e = list[i]
                let b = UIButton(type: .custom)
                b.setTitle(e, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 28)
                b.frame = CGRect(x: ox + CGFloat(i % cols) * cell, y: oy + CGFloat(i / cols) * cell, width: cell, height: cell)
                b.addAction(UIAction { [weak self] _ in self?.insertEmoji(e) }, for: .touchUpInside)
                panel.addSubview(b)
            }
            // Indices discrets : flèches vers ce côté, et le milieu près du centre.
            let freeW = w - gridW - 4
            if freeW >= 36 {
                let hint = UIImageView(image: UIImage(systemName: isRight ? "chevron.left.2" : "chevron.right.2"))
                hint.tintColor = theme.text.withAlphaComponent(0.22)
                hint.contentMode = .center
                let fx = isRight ? gridW + 4 : 0
                hint.frame = CGRect(x: fx, y: 0, width: freeW, height: h)
                hint.isUserInteractionEnabled = false
                panel.addSubview(hint)
            }
        } else if eff.sidePanel == .emoji || (layoutMode == .split && eff.sidePanel == .phrases && w < 90) {
            let cols = max(1, min(4, Int(w / 46)))
            let cell = min(52, w / CGFloat(cols))
            let rowsN = max(1, Int(h / cell))
            let count = min(eff.emojis.count, cols * rowsN)
            let gridW = cell * CGFloat(cols)
            let gridH = cell * CGFloat(min(rowsN, Int(ceil(Double(count) / Double(cols)))))
            let ox = (w - gridW) / 2
            let oy = max(0, (h - gridH) / 2)
            for i in 0..<count {
                let e = eff.emojis[i]
                let b = UIButton(type: .custom)
                b.setTitle(e, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: min(30, cell * 0.6))
                b.frame = CGRect(x: ox + CGFloat(i % cols) * cell, y: oy + CGFloat(i / cols) * cell, width: cell, height: cell)
                b.addAction(UIAction { [weak self] _ in self?.insertEmoji(e) }, for: .touchUpInside)
                panel.addSubview(b)
            }
        } else if eff.sidePanel == .phrases {
            let bh: CGFloat = 36
            let n = min(eff.phrases.count, max(1, Int((h + 6) / (bh + 6))))
            for i in 0..<n {
                let p = eff.phrases[i]
                let b = UIButton(type: .system)
                b.setTitle(p, for: .normal)
                b.titleLabel?.font = eff.font.ui(size: 14, weight: .medium)
                b.titleLabel?.lineBreakMode = .byTruncatingTail
                b.setTitleColor(theme.text, for: .normal)
                b.backgroundColor = theme.key
                b.layer.cornerRadius = 10
                b.frame = CGRect(x: 0, y: CGFloat(i) * (bh + 6), width: w, height: bh)
                b.addAction(UIAction { [weak self] _ in self?.insertPhrase(p) }, for: .touchUpInside)
                panel.addSubview(b)
            }
        }
    }

    private func updateLabels() {
        let upper = shift != .off && page == .letters
        for c in cells {
            let v = c.view
            v.backgroundColor = v.special ? theme.special : theme.key
            v.label.textColor = theme.text
            v.icon.tintColor = theme.text
            v.icon.image = nil
            v.label.text = nil
            let fontSize: CGFloat = min(26, keyH * 0.56)
            switch v.spec.kind {
            case .char(let s):
                v.label.text = upper ? s.uppercased() : s
                v.label.font = eff.font.ui(size: fontSize, weight: .regular)
            case .shift:
                v.icon.image = UIImage(systemName: shift == .caps ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"))
                if shift != .off { v.backgroundColor = theme.key }
            case .backspace:
                v.icon.image = UIImage(systemName: "delete.left")
            case .space:
                v.label.text = nil
            case .ret:
                v.icon.image = UIImage(systemName: "return")
                // Retour discret comme chez Apple ; coloré seulement dans les thèmes de couleur.
                if ["auto", "cloud", "night"].contains(theme.id) {
                    v.backgroundColor = theme.special
                } else {
                    v.backgroundColor = theme.accent
                    v.icon.tintColor = .white
                }
            case .page(let p):
                v.label.text = p == .letters ? "ABC" : (p == .numbers ? "123" : "#+=")
                v.label.font = eff.font.ui(size: 17, weight: .regular)
            case .globe:
                v.icon.image = UIImage(systemName: "globe")
            case .emoji:
                v.icon.image = UIImage(systemName: "face.smiling")
            }
            v.setNeedsLayout()
        }
    }

    // MARK: Touchers


    private func cellIndex(at raw: CGPoint) -> Int? {
        // Le pouce touche un peu plus bas qu'il ne vise (comme le clavier d'Apple, on compense de 4 pt).
        let p = CGPoint(x: raw.x, y: raw.y - 4)
        if let i = cells.firstIndex(where: { $0.hit.contains(p) }) { return i }
        // Juste à côté du clavier : la touche la plus proche (un appui un peu à côté écrit quand même).
        guard blocks.contains(where: { $0.insetBy(dx: -18, dy: -10).contains(p) }) else { return nil }
        var best: (Int, CGFloat)?
        for (i, c) in cells.enumerated() {
            let d = hypot(c.frame.midX - p.x, c.frame.midY - p.y)
            if d < 44, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    // MARK: Mesure de fluidité (appui long sur ⌄ en haut à droite)

    /// Pour chaque appui : le temps entre le toucher de l'écran et son arrivée au clavier, et le temps de traitement.
    private var perfDelay: [Double] = []
    private var perfWork: [Double] = []
    /// Les blocages du clavier (plus de 50 ms sans image).
    private var perfStalls = 0
    /// Appuis annulés par iOS, et appuis tombés à côté des touches.
    private var perfCancelled = 0
    private var perfMissed = 0
    private var perfLink: CADisplayLink?
    private var perfLast: CFTimeInterval = 0

    private func perfStart() {
        perfLink?.invalidate()
        perfLast = 0
        let l = CADisplayLink(target: self, selector: #selector(perfTick(_:)))
        l.add(to: .main, forMode: .common)
        perfLink = l
    }

    @objc private func perfTick(_ l: CADisplayLink) {
        if perfLast > 0, l.timestamp - perfLast > 0.05 { perfStalls += 1 }
        perfLast = l.timestamp
    }

    private func perfPush(_ a: inout [Double], _ v: Double) {
        a.append(v)
        if a.count > 60 { a.removeFirst() }
    }

    @objc private func showPerf(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        func avg(_ a: [Double]) -> Int { a.isEmpty ? 0 : Int(a.reduce(0, +) / Double(a.count)) }
        let text = String(format: "Appui %d ms (max %d) · traitement %d ms · blocages %d · annulés %d · à côté %d",
                          avg(perfDelay), Int(perfDelay.max() ?? 0), avg(perfWork), perfStalls, perfCancelled, perfMissed)
        flash(text)
        perfDelay = []; perfWork = []; perfStalls = 0; perfCancelled = 0; perfMissed = 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        idleTimer?.invalidate()
        let w0 = ProcessInfo.processInfo.systemUptime
        if let t = touches.first { perfPush(&perfDelay, (w0 - t.timestamp) * 1000) }
        defer { perfPush(&perfWork, (ProcessInfo.processInfo.systemUptime - w0) * 1000) }
        for t in touches {
            let p = t.location(in: self)
            // Un toucher dans la place libre : on attend de voir si c'est un vrai toucher (voir touchesEnded).
            // Près du bord des touches, c'est une touche visée de peu, pas la place libre.
            let nearKeys = blocks.contains { $0.insetBy(dx: -18, dy: 0).contains(p) }
            if !adjusting, !showEmoji, panelRect.width > 0, panelRect.contains(p), !nearKeys {
                placeTouches[t] = (p, t.timestamp)
                continue
            }
            guard p.y > Self.topBarHeight, let i = cellIndex(at: p) else {
                if p.y > Self.topBarHeight { perfMissed += 1 }
                continue
            }
            // Frappe en roulement : la touche précédente encore enfoncée part tout de suite.
            for o in order {
                if let tr = tracks[o], !tr.done, case .char? = kind(tr), tr.accents.isEmpty {
                    commit(tr)
                }
            }
            let tr = Track(index: i, start: p)
            tr.t0 = t.timestamp
            if recording != nil { halo(at: p, radius: t.majorRadius) }
            tr.points = [p]
            if autoOn || recording != nil, bounds.width > 0 {
                let lo = blocks.map { $0.minX }.min() ?? 0
                let hi = blocks.map { $0.maxX }.max() ?? bounds.width
                let bx = max(0, min(1, (p.x - lo) / max(1, hi - lo)))
                let others = order.filter { $0 != t }.map { $0.location(in: self).x / bounds.width }
                grip.tap(blockX: bx, screenX: p.x / bounds.width, radius: t.majorRadius, time: t.timestamp, others: others)
            }
            tracks[t] = tr
            order.append(t)
            press(tr)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let tr = tracks[t], !tr.done, let k = kind(tr) else { continue }
            let p = t.location(in: self)
            if tr.points.count < 80 { tr.points.append(p) }
            // Un balayage vertical du pouce n'écrit rien : il dit quelle main tape (arc du pouce).
            let ddx = p.x - tr.start.x, ddy = p.y - tr.start.y
            if !tr.swipe && !tr.cursorMode && tr.accents.isEmpty && abs(ddy) > 44 && abs(ddy) > abs(ddx) * 1.4 {
                tr.swipe = true
                tr.longTimer?.invalidate()
                hideBubble()
            }
            if tr.swipe { continue }
            if k == .space {
                let dx = p.x - tr.start.x
                // Déplacer le curseur : glisser franchement, ou après avoir gardé le doigt posé (comme chez Apple).
                // Un petit glissement du pouce pendant la frappe ne retire plus l'espace.
                let held = t.timestamp - tr.t0 > 0.35
                if !tr.cursorMode && (abs(dx) > 40 || (held && abs(dx) > 12)) {
                    if tr.typed != nil { input?.kbDelete(); tr.typed = nil }
                    tr.cursorMode = true
                    tr.lastX = p.x
                    hideBubble()
                }
                if tr.cursorMode {
                    let step = 18 - 13 * CGFloat(eff.swipe)
                    tr.cursorAccum += p.x - tr.lastX
                    tr.lastX = p.x
                    let n = Int(tr.cursorAccum / step)
                    if n != 0 {
                        input?.kbMoveCursor(n)
                        tr.cursorAccum -= CGFloat(n) * step
                        KBFeedback.shared.tap(sound: .off, haptics: eff.haptics * 0.4)
                    }
                }
            } else if !tr.accents.isEmpty {
                let cellW = accentCellWidth
                let idx = Int((p.x - accentView.frame.minX) / cellW)
                let clamped = max(0, min(tr.accents.count - 1, idx))
                if clamped != tr.accentIndex {
                    tr.accentIndex = clamped
                    highlightAccent(clamped)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let (p0, t0) = placeTouches.removeValue(forKey: t) {
                // Un vrai toucher : bref, sans glisser, du bout du doigt (pas la paume), loin des touches,
                // et pas en pleine frappe. Sinon on ne bouge pas.
                let p = t.location(in: self)
                let away = blocks.allSatisfy { !$0.insetBy(dx: -10, dy: 0).contains(p) }
                if t.timestamp - t0 < 0.35, hypot(p.x - p0.x, p.y - p0.y) < 14, t.majorRadius < 30, away,
                   tracks.isEmpty, t.timestamp - lastKeyTime > 0.5, panelRect.contains(p) {
                    placeByTap(at: p)
                }
                continue
            }
            guard let tr = tracks[t] else { continue }
            if tr.swipe {
                tr.done = true
                if autoOn || recording != nil {
                    grip.swipe(tr.points, width: bounds.width, t0: tr.t0, t1: t.timestamp)
                }
            } else if !tr.done {
                commit(tr)
            }
            finish(t)
        }
        if tracks.isEmpty { scheduleGrip() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        perfCancelled += touches.filter { tracks[$0] != nil }.count
        for t in touches {
            placeTouches[t] = nil
            guard let tr = tracks[t] else { continue }
            tr.done = true
            finish(t)
        }
    }

    private func finish(_ t: UITouch) {
        if let tr = tracks[t] {
            tr.longTimer?.invalidate()
            tr.repeatTimer?.invalidate()
            setPressed(tr.index, false)
            if case .backspace? = kind(tr) { refreshShiftSoon() }
        }
        tracks[t] = nil
        order.removeAll { $0 == t }
        if tracks.isEmpty {
            hideBubble()
            accentView.isHidden = true
        }
    }

    private func kind(_ tr: Track) -> KeyKind? {
        tr.index < cells.count ? cells[tr.index].view.spec.kind : nil
    }

    private func setPressed(_ i: Int, _ on: Bool) {
        guard i < cells.count else { return }
        let v = cells[i].view
        if on {
            v.backgroundColor = v.special ? theme.key : theme.special
        } else {
            // Seule cette touche reprend sa couleur (pas de redessin de tout le clavier à chaque lettre).
            var c = v.special ? theme.special : theme.key
            switch v.spec.kind {
            case .shift: if shift != .off { c = theme.key }
            case .ret: if !["auto", "cloud", "night"].contains(theme.id) { c = theme.accent }
            default: break
            }
            v.backgroundColor = c
        }
    }

    private func press(_ tr: Track) {
        lastKeyTime = ProcessInfo.processInfo.systemUptime
        let v = cells[tr.index].view
        let strong: Bool
        switch v.spec.kind {
        case .backspace, .ret, .shift: strong = true
        default: strong = false
        }
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics, strong: strong)
        setPressed(tr.index, true)
        if case .space = v.spec.kind {
            // L'espace part dès que le doigt se pose (retiré si le doigt glisse pour déplacer le curseur).
            tr.typed = " "
            typeSpace()
            return
        }
        switch v.spec.kind {
        case .char(let s):
            countTyped()
            let upper = shift != .off && page == .letters
            let text = upper ? s.uppercased() : s
            showBubble(over: cells[tr.index].frame, text: text)
            let options = KBLayouts.accents(s, layout: eff.layout)
            if !options.isEmpty {
                tr.longTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self, weak tr] _ in
                    guard let self, let tr, !tr.done, tr.index < self.cells.count else { return }
                    tr.accents = options.map { upper ? $0.uppercased() : $0 }
                    tr.accentIndex = 0
                    self.hideBubble()
                    self.showAccents(tr.accents, over: self.cells[tr.index].frame)
                }
            }
            // La lettre s'écrit dès que le doigt se pose : c'est ce qui rend la frappe immédiate.
            tr.typed = text
            typeText(text)
        case .backspace:
            if undoCorrection() {
                tr.done = true
                refreshSuggestionsSoon()
                break
            }
            lastCorrection = nil
            input?.kbDelete()
            refreshSuggestionsSoon()
            tr.done = true
            tr.longTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self, weak tr] _ in
                guard let self, let tr else { return }
                var count = 0
                tr.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    count += 1
                    if count > 18 {
                        // Après un moment, on efface mot par mot.
                        self.deleteWord()
                    } else {
                        self.input?.kbDelete()
                    }
                    KBFeedback.shared.tap(sound: .off, haptics: self.eff.haptics * 0.5)
                }
            }
            refreshShiftSoon()
        default:
            break
        }
    }

    private func commit(_ tr: Track) {
        guard !tr.done, tr.index < cells.count else { return }
        tr.done = true
        tr.longTimer?.invalidate()
        let v = cells[tr.index].view
        switch v.spec.kind {
        case .char(let s):
            if !tr.accents.isEmpty {
                let chosen = tr.accents[tr.accentIndex]
                if let typed = tr.typed {
                    // La lettre est déjà écrite : on la remplace par l'accent choisi.
                    if chosen != typed {
                        input?.kbDelete()
                        input?.kbInsert(chosen)
                        refreshSuggestionsSoon()
                    }
                } else {
                    typeText(chosen)
                }
                accentView.isHidden = true
            } else if tr.typed == nil {
                typeText(shift != .off && page == .letters ? s.uppercased() : s)
            }
        case .space:
            if !tr.cursorMode && tr.typed == nil { typeSpace() }
        case .ret:
            autocorrect(sep: "\n")
            input?.kbInsert("\n")
            refreshSuggestionsSoon()
            refreshShiftSoon()
        case .shift:
            let now = Date()
            if now.timeIntervalSince(lastShiftTap) < 0.32 {
                shift = .caps
            } else {
                shift = shift == .off ? .on : .off
            }
            autoShifted = false
            lastShiftTap = now
            updateLabels()
        case .page(let p):
            page = p
            builtFor = .zero
            rebuild()
        case .globe:
            input?.kbNextKeyboard()
        case .emoji:
            showEmoji = true
            builtFor = .zero
            rebuild()
        case .backspace:
            break
        }
        hideBubble()
    }

    private func typeText(_ text: String) {
        if [".", ",", "!", "?", ";", ":", ")"].contains(text) {
            autocorrect(sep: text)
        } else {
            lastCorrection = nil
        }
        input?.kbInsert(text)
        refreshSuggestionsSoon()
        if shift == .on {
            shift = .off
            autoShifted = false
            updateLabels()
        }
        // Après une ponctuation de fin de phrase suivie d'un espace, la majuscule revient (voir typeSpace).
        if page != .letters, text == "'" || text == "’" {
            page = .letters
            builtFor = .zero
            rebuild()
        }
    }

    private func typeSpace() {
        let before = input?.kbTextBefore() ?? ""
        if eff.doubleSpacePeriod, before.hasSuffix(" "), before.count >= 2 {
            let prev = before[before.index(before.endIndex, offsetBy: -2)]
            if prev.isLetter || prev.isNumber {
                input?.kbDelete()
                input?.kbInsert(". ")
                refreshShiftSoon()
                return
            }
        }
        autocorrect(sep: " ")
        input?.kbInsert(" ")
        refreshSuggestionsSoon()
        if page != .letters {
            page = .letters
            builtFor = .zero
            rebuild()
        }
        refreshShiftSoon()
    }

    private func deleteWord() {
        let before = input?.kbTextBefore() ?? ""
        guard !before.isEmpty else { return }
        var n = 0
        var seenWord = false
        for ch in before.reversed() {
            if ch.isWhitespace || ch.isPunctuation {
                if seenWord { break }
            } else {
                seenWord = true
            }
            n += 1
        }
        for _ in 0..<max(1, n) { input?.kbDelete() }
    }

    private func insertPhrase(_ p: String) {
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
        let before = input?.kbTextBefore() ?? ""
        let needsSpace = !(before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n"))
        input?.kbInsert((needsSpace ? " " : "") + p)
        refreshShiftSoon()
    }

    private func insertEmoji(_ e: String) {
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
        KBEmoji.used(e)
        input?.kbInsert(e)
        refreshSuggestionsSoon()
    }

    // MARK: Correction et suggestions

    /// Avant un espace ou une ponctuation : on corrige le mot qui vient d'être tapé.
    private func autocorrect(sep: String) {
        guard eff.autocorrect, page == .letters || sep != " " else { return }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        let known: String?? = cachedFix?.word == word ? .some(cachedFix?.fix) : nil
        // La correction préparée en arrière-plan si elle est prête, sinon on la calcule (quelques ms : la mesure
        // de fluidité montre que le clavier a toute la marge).
        let computed: String? = known ?? suggest.correction(for: word, before: before)
        guard !word.isEmpty, let fix = computed, fix != word else {
            lastCorrection = nil
            return
        }
        for _ in 0..<word.count { input?.kbDelete() }
        input?.kbInsert(fix)
        lastCorrection = (word, fix, sep)
    }

    /// Effacer juste après une correction : on revient au mot tapé, et on ne le corrigera plus.
    private func undoCorrection() -> Bool {
        guard let lc = lastCorrection else { return false }
        lastCorrection = nil
        let before = input?.kbTextBefore() ?? ""
        guard before.hasSuffix(lc.corrected + lc.sep) else { return false }
        for _ in 0..<(lc.corrected.count + lc.sep.count) { input?.kbDelete() }
        input?.kbInsert(lc.original)
        suggest.learn(lc.original)
        let w0 = lc.original
        suggestQueue.async { [bgSuggest] in bgSuggest.learn(w0) }
        cachedFix = nil
        return true
    }

    private func applySuggestion(_ i: Int) {
        guard i < suggestionItems.count else { return }
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        let item = suggestionItems[i]
        if suggestionBest != nil && i == 0 {
            // Le mot tel qu'il a été tapé (entre guillemets) : on le garde et on l'apprend.
            suggest.learn(word)
            let w1 = word
            suggestQueue.async { [bgSuggest] in bgSuggest.learn(w1) }
        }
        for _ in 0..<word.count { input?.kbDelete() }
        input?.kbInsert(item + " ")
        lastCorrection = nil
        refreshSuggestionsSoon()
        refreshShiftSoon()
    }

    /// Les suggestions se recalculent quand la frappe marque une petite pause : la touche réagit tout de suite.
    private var suggestWork: DispatchWorkItem?
    private func refreshSuggestionsSoon() {
        suggestWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refreshSuggestions() }
        suggestWork = w
        // Pendant une frappe rapide, rien n'est recalculé : seulement quand le doigt marque une pause.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: w)
    }

    private func refreshSuggestions() {
        guard eff.suggestions && page == .letters else {
            applySuggestions([], nil)
            return
        }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        guard !word.isEmpty else {
            applySuggestions([], nil)
            return
        }
        suggestGen += 1
        let gen = suggestGen
        let auto = eff.autocorrect
        suggestQueue.async { [weak self, bgSuggest] in
            let (items, best) = bgSuggest.suggestions(for: word, before: before)
            let fix = best.map { items[$0] }
            DispatchQueue.main.async {
                guard let self, gen == self.suggestGen else { return }
                self.cachedFix = (word, auto ? fix : nil)
                self.applySuggestions(items, auto ? best : nil)
            }
        }
    }

    private func applySuggestions(_ items: [String], _ best: Int?) {
        guard items != suggestionItems || best != suggestionBest else { return }
        suggestionItems = items
        suggestionBest = best
        rebuildChips()
    }

    private func refreshShiftSoon() {
        DispatchQueue.main.async { [weak self] in self?.refreshShift() }
    }

    private func refreshShift() {
        guard eff.autoCaps, shift != .caps else { return }
        let before = input?.kbTextBefore() ?? ""
        let trimmed = before.replacingOccurrences(of: " ", with: "")
        let cap = before.isEmpty || before.hasSuffix("\n") || trimmed.isEmpty
            || [". ", "! ", "? ", "… "].contains(where: { before.hasSuffix($0) })
        if cap && shift == .off {
            shift = .on
            autoShifted = true
            updateLabels()
        } else if !cap && shift == .on && autoShifted {
            shift = .off
            autoShifted = false
            updateLabels()
        }
    }

    // MARK: Bulles

    private func showBubble(over f: CGRect, text: String) {
        bubble.text = text
        let fs = min(34, keyH * 0.72)
        if bubble.font.pointSize != fs || bubbleFontName != eff.font.rawValue {
            bubble.font = eff.font.ui(size: fs)
            bubbleFontName = eff.font.rawValue
        }
        bubble.backgroundColor = theme.key
        bubble.textColor = theme.text
        let w = max(f.width * 1.35, 46)
        let h = keyH * 1.05
        var x = f.midX - w / 2
        x = max(2, min(bounds.width - w - 2, x))
        bubble.frame = CGRect(x: x, y: max(0, f.minY - h - 4), width: w, height: h)
        bubble.isHidden = false
        bringSubviewToFront(bubble)
    }

    private var bubbleFontName = ""

    private func hideBubble() { bubble.isHidden = true }

    private var accentCellWidth: CGFloat { max(36, keyH * 0.85) }

    private func showAccents(_ options: [String], over f: CGRect) {
        accentLabels.forEach { $0.removeFromSuperview() }
        accentLabels = []
        let cw = accentCellWidth
        let w = cw * CGFloat(options.count)
        let h = keyH * 1.05
        var x = f.minX
        x = max(2, min(bounds.width - w - 2, x))
        accentView.frame = CGRect(x: x, y: max(0, f.minY - h - 4), width: w, height: h)
        accentView.backgroundColor = theme.key
        for (i, o) in options.enumerated() {
            let l = UILabel(frame: CGRect(x: CGFloat(i) * cw, y: 0, width: cw, height: h))
            l.text = o
            l.textAlignment = .center
            l.font = eff.font.ui(size: min(26, keyH * 0.55))
            l.layer.cornerRadius = 8
            l.layer.masksToBounds = true
            accentView.addSubview(l)
            accentLabels.append(l)
        }
        accentView.isHidden = false
        bringSubviewToFront(accentView)
        highlightAccent(0)
        KBFeedback.shared.tap(sound: .off, haptics: eff.haptics)
    }

    private func highlightAccent(_ i: Int) {
        for (j, l) in accentLabels.enumerated() {
            l.backgroundColor = j == i ? theme.accent : .clear
            l.textColor = j == i ? .white : theme.text
        }
    }
}
