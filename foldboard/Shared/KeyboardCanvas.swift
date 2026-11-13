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
    func kbTextAfter() -> String?
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
    /// Au milieu, à deux mains : le clavier entier, et la prise en main est retenue.
    private let middleButton = UIButton(type: .system)
    /// Écran intérieur, petit clavier : un bouton pour passer en grand (et revenir).
    private let bigButton = UIButton(type: .system)
    private let hideButton = UIButton(type: .system)
    /// Petit clavier : le globe et les emojis sont ici, pour laisser la place à l'espace.
    private let globeButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    /// Le presse-papier, toujours en vue dans la barre du haut.
    private let clipButton = UIButton(type: .system)
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
    /// Où le doigt s'est posé pour chaque lettre tapée (les dernières) : la correction s'en sert, comme chez Apple.
    private var wordTouches: [(ch: Character, p: CGPoint)] = []

    private func noteTouch(_ text: String, at p: CGPoint) {
        guard text.count == 1, let c = text.lowercased().first, c.isLetter else { wordTouches.removeAll(); return }
        wordTouches.append((c, p))
        if wordTouches.count > 40 { wordTouches.removeFirst(wordTouches.count - 40) }
    }

    /// Le modèle de toucher pour le mot en cours, si chaque lettre a bien été tapée ici (pas collée ni déplacée).
    private func touchModel(for word: String) -> KBTouchModel? {
        let w = Array(word.lowercased())
        guard !w.isEmpty, wordTouches.count >= w.count else { return nil }
        let tail = Array(wordTouches.suffix(w.count))
        for (i, t) in tail.enumerated() {
            let a = String(t.ch).folding(options: .diacriticInsensitive, locale: nil)
            let b = String(w[i]).folding(options: .diacriticInsensitive, locale: nil)
            guard a == b else { return nil }
        }
        var centers: [Character: [CGPoint]] = [:]
        var keyW: CGFloat = 0, keyH: CGFloat = 0
        for c in cells {
            guard case .char(let s) = c.view.spec.kind, s.count == 1, let ch = s.lowercased().first, ch.isLetter else { continue }
            centers[ch, default: []].append(CGPoint(x: c.frame.midX, y: c.frame.midY))
            keyW = max(keyW, c.frame.width); keyH = max(keyH, c.frame.height)
        }
        guard centers.count >= 20 else { return nil }
        return KBTouchModel(points: tail.map { $0.p }, centers: centers, keyW: keyW, keyH: keyH)
    }
    private var pendingGrip: KBGrip?
    private var idleTimer: Timer?
    private var visible = false
    private var autoOn: Bool { eff.mode == .auto && pro }

    /// Appui sur « 123 » puis glisser jusqu'à un chiffre ou un signe : il s'écrit au lâcher et les lettres reviennent
    /// (comme le clavier d'Apple).
    private var pageSlide: (touch: UITouch, cell: Int?)?
    /// Recherche d'emoji : les lettres tapées vont dans la recherche (pas dans le texte), les résultats dans la barre.
    private var emojiQuery: String?

    private final class Track {
        let index: Int
        let start: CGPoint
        var lastX: CGFloat
        var lastY: CGFloat = 0
        var cursorMode = false
        var cursorAccum: CGFloat = 0
        var cursorAccumY: CGFloat = 0
        var lastT: TimeInterval = 0
        var accents: [String] = []
        var accentIndex = 0
        var longTimer: Timer?
        var repeatTimer: Timer?
        var done = false
        /// La lettre déjà écrite, dès que le doigt s'est posé (comme ça, rien n'attend que le doigt se relève).
        var typed: String?
        var swipe = false
        /// Écrire en glissant : le doigt trace le mot.
        var glide = false
        var points: [CGPoint] = []
        var t0: TimeInterval = 0
        init(index: Int, start: CGPoint) {
            self.index = index
            self.start = start
            self.lastX = start.x
        }
    }
    private var tracks: [UITouch: Track] = [:]
    /// Le trait du doigt quand on écrit en glissant.
    private let glideLayer = CAShapeLayer()
    /// Le dernier mot écrit en glissant : l'espace vient avant le mot suivant, et ⌫ l'efface en entier (comme chez Apple).
    private var glidedWord: String?
    /// Pavé tactile : la colonne visée, gardée quand on monte et descend (comme dans un éditeur de texte).
    private var trackGoalCol: Int?
    private var trackMap: TrackMap?

    /// Le texte autour du curseur, découpé en lignes (retours à la ligne, et lignes estimées dans un long
    /// paragraphe), pour savoir où le doigt envoie le curseur. Positions comptées depuis le curseur de départ.
    struct TrackMap {
        var lines: [(start: Int, len: Int)] = []
        var originLine = 0
        var originCol = 0
        var current = 0
        let origin: CGPoint
        let total: (lo: Int, hi: Int)
        let singleParagraph: Bool
        let perLine: Int

        init(before: String, after: String, perLine: Int, origin: CGPoint) {
            self.origin = origin
            self.perLine = perLine
            let text = before + after
            let idx = before.count
            total = (-idx, after.count)
            singleParagraph = !text.contains("\n")
            var pos = 0
            for para in text.components(separatedBy: "\n") {
                let n = para.count
                var off = 0
                repeat {
                    let len = min(perLine, n - off)
                    lines.append((start: pos + off - idx, len: len))
                    off += perLine
                } while off < n
                pos += n + 1
            }
            if let i = lines.lastIndex(where: { $0.start <= 0 }) {
                originLine = i
                originCol = -lines[i].start
            }
        }

        func target(dLine: Int, dCol: Int) -> Int {
            if singleParagraph || lines.isEmpty {
                return max(total.lo, min(total.hi, dCol + dLine * perLine))
            }
            let l = max(0, min(lines.count - 1, originLine + dLine))
            let c = max(0, min(lines[l].len, originCol + dCol))
            return max(total.lo, min(total.hi, lines[l].start + c))
        }
    }
    private var order: [UITouch] = []

    static let topBarHeight: CGFloat = 42
    private let pad: CGFloat = 4
    private let gap: CGFloat = 7
    private let vgap: CGFloat = 11

    private var keyH: CGFloat { CGFloat(eff.keyHeight) * (wideFull ? 1.24 : 1) }
    /// Le clavier entier sur l'écran déplié : de grandes touches, comme le clavier d'Apple.
    private var wideFull: Bool { layoutMode == .full && bounds.width >= 560 && !showEmoji }
    private var reportedHeight: CGFloat = 0
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
        emojiBoard.onSearch = { [weak self] in
            guard let self else { return }
            self.closeEmoji()
            self.page = .letters
            self.emojiQuery = ""
            if self.shift != .caps { self.shift = .off; self.updateLabels() }
            self.rebuildChips()
        }
        emojiBoard.onClip = { [weak self] t in
            guard let self else { return }
            KBFeedback.shared.tap(sound: self.eff.sound, haptics: self.eff.haptics)
            self.pasteClip(t)
            self.closeEmoji()
        }
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
        for b in [modeButton, flipButton, middleButton, bigButton, hideButton, adjustButton, globeButton, emojiButton, clipButton] {
            b.tintColor = .label
            topBar.addSubview(b)
        }
        modeButton.showsMenuAsPrimaryAction = true
        flipButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        flipButton.addAction(UIAction { [weak self] _ in self?.flipSide() }, for: .touchUpInside)
        flipButton.accessibilityLabel = L("Switch side")
        middleButton.setImage(UIImage(systemName: "rectangle.center.inset.filled"), for: .normal)
        middleButton.addAction(UIAction { [weak self] _ in self?.centerKeyboard() }, for: .touchUpInside)
        middleButton.accessibilityLabel = L("Keyboard in the middle")
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
        clipButton.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        clipButton.accessibilityLabel = L("Clipboard")
        clipButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.showEmoji = true
            self.builtFor = .zero
            self.rebuild()
            self.emojiBoard.setClipMode(true)
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
        KBThumb.shared.importSeed(settings.thumbSeed, stamps: settings.thumbSeedStamp)
        updateGripContext()
        grip.current = settings.autoTwo ? .two : (settings.autoRight ? .right : .left)
        // Captures de l'App Store : le presse-papier déjà ouvert.
        if ProcessInfo.processInfo.arguments.contains("-shotClip"), !showEmoji {
            KBClipboard.shared.seedForShots(["221B Baker Street, London", "https://foldly.netlify.app",
                                             "Meeting at 7 pm 🎬", "FOLD-2026-0412", "+1 555 0142"])
            showEmoji = true
            emojiBoard.setClipMode(true)
        }
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
        emojiBoard.setClipMode(false)
        startClipWatch()
        if ProcessInfo.processInfo.arguments.contains("-shotClip") {
            KBClipboard.shared.seedForShots(["221B Baker Street, London", "https://foldly.netlify.app",
                                             "Meeting at 7 pm 🎬", "FOLD-2026-0412", "+1 555 0142"])
            showEmoji = true
            emojiBoard.setClipMode(true)
        }
        builtFor = .zero
        setNeedsLayout()
    }

    // MARK: Presse-papier

    private var clipTimer: Timer?

    /// Ce que tu copies est gardé (accès complet seulement) : on regarde à l'apparition puis chaque seconde et demie.
    private func startClipWatch() {
        clipTimer?.invalidate()
        guard input?.kbFullAccess == true else { return }
        checkClipboard()
        clipTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkClipboard() }
    }

    private func checkClipboard() {
        guard visible, KBClipboard.shared.capture() else { return }
        if suggestionItems.isEmpty { rebuildChips() }
        if showEmoji, emojiBoard.clipMode { emojiBoard.clips.reload() }
    }

    private func pasteClip(_ t: String) {
        input?.kbInsert(t)
        KBClipboard.shared.dismissFresh()
        lastCorrection = nil
        refreshSuggestionsSoon()
        refreshShiftSoon()
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
        grip.thumbReady = followsHand && KBThumb.shared.ready(context: ctx)
        grip.thumbVote = { KBThumb.shared.vote(context: ctx, now: ProcessInfo.processInfo.systemUptime) }
    }

    // MARK: Justesse des choix (pour la mesurer, et proposer de recalibrer)

    /// Le dernier changement de côté décidé par le clavier, pas encore jugé.
    private var autoDecisionAt: TimeInterval?
    private var recentCorrections: [TimeInterval] = []

    private func judge(hit: Bool) {
        var l = KBVault.loadLearn()
        if hit { l.hits = (l.hits ?? 0) + 1 } else { l.misses = (l.misses ?? 0) + 1 }
        KBVault.save(l)
    }

    /// Une correction à la main : si le clavier venait de changer de côté tout seul, c'était un raté.
    /// Trois corrections en dix minutes : on propose de refaire le test des mains (une fois par jour).
    private func noteCorrection() {
        let now = ProcessInfo.processInfo.systemUptime
        if let at = autoDecisionAt, now - at < 20 { judge(hit: false) }
        autoDecisionAt = nil
        KBThumb.shared.reset()
        recentCorrections = recentCorrections.filter { now - $0 < 600 } + [now]
        let key = "foldboard.recalAsked"
        let last = UserDefaults.standard.double(forKey: key)
        if recentCorrections.count >= 3, Date().timeIntervalSince1970 - last > 86_400 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
            recentCorrections.removeAll()
            notice(L("Wrong side often? Redo the “Right hand, left hand” test in the Foldboard app (10 s)."))
        }
    }

    private var habitSeeds: [KBHabit] = []
    /// Les lettres tapées depuis que le clavier est de ce côté (sans correction : le côté était le bon).
    private var typedOnSide = 0

    /// Retient la prise en main du moment pour ce côté. `correction` : choisi à la main (exemple fort).
    private func learnHabit(right: Bool, two: Bool = false, correction: Bool) {
        guard followsHand, recording == nil, !demoOneHand else { return }
        if correction { noteCorrection() }
        guard let p = grip.currentPosture else { return }
        KBHabits.shared.add(context: gripContext, roll: p.roll, incline: p.incline, right: right, two: two,
                            weight: correction ? 3 : 1, correction: correction)
        grip.habitReady = KBHabits.shared.ready(context: gripContext, seeds: habitSeeds)
        showLearning(correction: correction)
    }

    /// Montrer que le clavier apprend : « noté » aux premières corrections, puis des paliers.
    private func showLearning(correction: Bool) {
        let n = KBHabits.shared.learnedTotal
        if [3, 10, 25, 50, 100, 200].contains(n) {
            notice(String(format: L("Foldboard knows your grip better: %lld habits learned"), n))
            return
        }
        guard correction else { return }
        let key = "foldboard.notedShown"
        let shown = UserDefaults.standard.integer(forKey: key)
        guard shown < 5 else { return }
        UserDefaults.standard.set(shown + 1, forKey: key)
        flash(L("Noted, I’ll remember this grip"))
    }

    /// Une lettre tapée avec le petit clavier d'un côté : après quelques lettres sans correction, c'est une habitude.
    private func countTyped() {
        guard autoOn, followsHand, layoutMode.isOneHand || settings.autoTwo else { return }
        typedOnSide += 1
        if typedOnSide == 8 || typedOnSide == 40 {
            learnHabit(right: settings.autoRight, two: settings.autoTwo, correction: false)
            // Les appuis de cette série étaient bien de cette main : le pouce l'apprend.
            if !settings.autoTwo {
                KBThumb.shared.confirm(context: gripContext, right: settings.autoRight)
                grip.thumbReady = followsHand && KBThumb.shared.ready(context: gripContext)
            }
            if typedOnSide == 8, autoDecisionAt != nil { judge(hit: true); autoDecisionAt = nil }
        }
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
        clipTimer?.invalidate()
        clipTimer = nil
    }

    /// Étalonnage dans l'app : la prise qu'on enregistre (le clavier ne bouge pas, chaque appui est envoyé).
    private(set) var recording: KBGrip?
    /// Étalonnage dans l'app : chaque appui sur une lettre, pour le deuxième indice (KBThumb).
    var onThumbSample: (([Double]) -> Void)?
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
        grip.onUnlock = { [weak self] in self?.layoutTopBar() }
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
        autoDecisionAt = ProcessInfo.processInfo.systemUptime
        KBThumb.shared.reset()
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
        if gripContext == "open-portrait" { settings.openSplit.toggle() }
        else if settings.openLandFollow { settings.openLandFollow = false }
        else { settings.openLandSplit.toggle() }
        settings.openFull = false
        KBFeedback.shared.tap(sound: .off, haptics: max(0.4, eff.haptics))
        save()
        layoutIfNeeded()
    }

    /// Le clavier au milieu (à deux mains), choisi à la main : la prise en main du moment est retenue.
    private func centerKeyboard() {
        guard eff.mode == .auto, followsHand else { return }
        settings.autoTwo = true
        grip.current = .two
        grip.locked = true
        learnHabit(right: settings.autoRight, two: true, correction: true)
        typedOnSide = 0
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

    /// Un message important, gardé plus longtemps à l'écran (fin de l'essai gratuit).
    func notice(_ text: String) {
        flash(text, hold: 6)
    }

    private func flash(_ text: String, hold: TimeInterval = 2.2) {
        toast.text = "  " + text + "  "
        toast.adjustsFontSizeToFitWidth = true
        toast.minimumScaleFactor = 0.7
        toast.backgroundColor = theme.accent
        toast.textColor = .white
        toast.sizeToFit()
        let w = min(topBar.bounds.width - 16, toast.bounds.width + 8)
        toast.frame = CGRect(x: (topBar.bounds.width - w) / 2, y: 7, width: w, height: 28)
        toast.alpha = 1
        UIView.animate(withDuration: 0.4, delay: hold, options: [], animations: { self.toast.alpha = 0 })
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
            || (gripContext == "open-landscape" && settings.openLandFollow)
    }

    private var layoutMode: KBMode {
        // Écran intérieur du Duo, comme le clavier d'Apple : deux moitiés en portrait, entier en paysage.
        if settings.mode == .auto {
            // En portrait, au choix : deux moitiés, ou le petit clavier qui suit la main (comme sur l'écran extérieur).
            if gripContext == "open-portrait" && settings.openSplit { return pro && splitAllowed ? .split : .full }
            // En paysage, au choix : le clavier entier, ou deux moitiés.
            if gripContext == "open-landscape" && !settings.openLandFollow { return settings.openLandSplit && pro && splitAllowed ? .split : .full }
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
        emojiBoard.setClipMode(false)
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
        // Thème automatique : fond plein, couleur du clavier d'Apple. Presque transparent, on voyait au travers
        // l'image de l'ancien clavier qu'iOS laisse dessous quand le Duo s'ouvre ou se ferme (claviers superposés).
        backgroundColor = theme.id == "glass" ? UIColor(white: 0, alpha: 0.012) : theme.background
        cells.forEach { $0.view.removeFromSuperview() }
        cells = []
        // La hauteur change avec la disposition (grandes touches du clavier entier) : on la redemande.
        if abs(preferredHeight - reportedHeight) > 0.5 {
            reportedHeight = preferredHeight
            DispatchQueue.main.async { [weak self] in self?.onPreferredHeightChange?() }
        }
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
            emojiBoard.clips.fullAccess = input?.kbFullAccess ?? false
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
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout, emoji: eff.emojiKey)], in: b, align: 0)
        case .left, .right, .auto:
            let bw = min(W - 2 * pad, max(min(W - 2 * pad, 250), W * oneHandFraction))
            let x = isRight ? W - margin - bw : margin
            let b = CGRect(x: max(0, x), y: top, width: bw, height: areaH)
            blocks = [b]
            panelRect = isRight
                ? CGRect(x: 6, y: top, width: max(0, b.minX - 12), height: areaH)
                : CGRect(x: b.maxX + 6, y: top, width: max(0, W - b.maxX - 12), height: areaH)
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout, compact: true, leftHand: !isRight)], in: b, align: 0)
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
                // Comme le clavier coupé d'Apple : la lettre du milieu de la dernière rangée (le V) est des deux côtés,
                // pour l'atteindre avec l'un ou l'autre pouce.
                if page == .letters, left.count == 2, let edge = lk.last, case .char = edge.kind { rk.insert(edge, at: 0) }
                left.append(KeyRow(keys: lk))
                right.append(KeyRow(keys: rk))
            }
            let maxL = left.map { $0.keys.reduce(0) { $0 + $1.width } }.max() ?? 5
            let maxR = right.map { $0.keys.reduce(0) { $0 + $1.width } }.max() ?? 5
            var lb: [KeySpec] = [KeySpec(kind: .page(page == .letters ? .numbers : .letters), width: 1.5)]
            if globe { lb.append(KeySpec(kind: .globe, width: 1.1)) }
            if eff.emojiKey { lb.append(KeySpec(kind: .emoji, width: 1.1)) }
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
        // Clavier d'un côté : la barre (boutons et suggestions) reste au-dessus des touches, à portée du pouce,
        // au lieu de traverser tout l'écran (Duo ouvert).
        let confine = layoutMode.isOneHand && panelRect.width > 0 && !blocks.isEmpty
        let x0 = confine ? (blocks.map { $0.minX }.min() ?? 0) : 0
        let x1 = confine ? (blocks.map { $0.maxX }.max() ?? bounds.width) : bounds.width
        modeButton.frame = CGRect(x: x0 + 6, y: 0, width: 40, height: h)
        modeButton.setImage(UIImage(systemName: eff.mode.symbol), for: .normal)
        modeButton.tintColor = theme.text.withAlphaComponent(0.7)
        modeButton.menu = modeMenu()
        modeButton.accessibilityLabel = L("Keyboard position")
        // La flèche ⇆ : changer de côté, ou revenir à une main depuis le milieu.
        let oneHand = layoutMode.isOneHand || (eff.mode == .auto && followsHand)
        flipButton.isHidden = !oneHand
        // En couleur : le clavier est verrouillé là où tu l'as mis.
        flipButton.tintColor = grip.locked && eff.mode == .auto ? theme.accent : theme.text.withAlphaComponent(0.7)
        flipButton.frame = CGRect(x: x0 + 46, y: 0, width: oneHand ? 36 : 0, height: h)
        // Le bouton du milieu : là où le clavier suit la main (il apprend aussi quand on le veut au milieu).
        let middleShown = eff.mode == .auto && followsHand && autoOn
        middleButton.isHidden = !middleShown
        middleButton.tintColor = settings.autoTwo ? theme.accent : theme.text.withAlphaComponent(0.7)
        middleButton.frame = CGRect(x: flipButton.frame.maxX, y: 0, width: middleShown ? 36 : 0, height: h)
        // Écran intérieur : un bouton pour passer d'une disposition à l'autre.
        // Portrait : petit clavier qui suit la main ⇄ deux moitiés. Paysage : clavier entier ⇄ deux moitiés.
        let open = gripContext.hasPrefix("open")
        let bigShown = open && settings.mode == .auto && pro
        let splitNow = gripContext == "open-portrait" ? settings.openSplit : (settings.openLandSplit || settings.openLandFollow)
        bigButton.isHidden = !bigShown
        bigButton.setImage(UIImage(systemName: splitNow ? (gripContext == "open-portrait" ? "keyboard.onehanded.right" : "keyboard") : "rectangle.split.2x1"), for: .normal)
        bigButton.accessibilityLabel = splitNow ? L("One keyboard") : L("Split keyboard")
        bigButton.tintColor = theme.text.withAlphaComponent(0.7)
        bigButton.frame = CGRect(x: max(flipButton.frame.maxX, middleButton.frame.maxX), y: 0, width: bigShown ? 36 : 0, height: h)
        hideButton.tintColor = theme.text.withAlphaComponent(0.7)
        hideButton.frame = CGRect(x: x1 - 46, y: 0, width: 40, height: h)
        adjustButton.tintColor = theme.text.withAlphaComponent(0.7)
        adjustButton.frame = CGRect(x: x1 - 46 - 36, y: 0, width: 36, height: h)
        let compact = layoutMode.isOneHand && !showEmoji
        let globe = input?.kbNeedsGlobe ?? false
        let emojiOn = compact && eff.emojiKey
        emojiButton.isHidden = !emojiOn
        globeButton.isHidden = !(compact && globe)
        globeButton.setImage(UIImage(systemName: eff.globeAsEmoji ? "face.smiling" : "globe"), for: .normal)
        emojiButton.tintColor = theme.text.withAlphaComponent(0.7)
        globeButton.tintColor = theme.text.withAlphaComponent(0.7)
        // Le presse-papier : juste à gauche des réglages, partout (sauf quand les emojis sont ouverts).
        let clipShown = !showEmoji
        clipButton.isHidden = !clipShown
        clipButton.tintColor = theme.text.withAlphaComponent(0.7)
        clipButton.frame = CGRect(x: adjustButton.frame.minX - (clipShown ? 36 : 0), y: 0, width: clipShown ? 36 : 0, height: h)
        emojiButton.frame = CGRect(x: clipButton.frame.minX - (emojiOn ? 36 : 0), y: 0, width: emojiOn ? 36 : 0, height: h)
        globeButton.frame = CGRect(x: emojiButton.frame.minX - (compact && globe ? 36 : 0), y: 0, width: compact && globe ? 36 : 0, height: h)
        let cx = max(flipButton.frame.maxX, middleButton.frame.maxX, bigButton.frame.maxX) + 4
        if let g = sideButtonsGrid {
            // Dans la place libre, en haut, du côté du clavier : 🌐 😀 réglages masquer.
            let buttons: [UIButton] = (globe ? [globeButton] : []) + (eff.emojiKey ? [emojiButton] : []) + [clipButton, adjustButton, hideButton]
            let gridW = CGFloat(g.cols) * 44
            let vertical = gripContext == "open-portrait"
            // En colonne : contre le clavier (côté pouce), et les boutons répartis sur la hauteur des touches.
            let ox = vertical ? (isRight ? panelRect.maxX - gridW - 6 : panelRect.minX + 6)
                              : (isRight ? panelRect.maxX - gridW : panelRect.minX)
            let step: CGFloat = vertical ? min(56, panelRect.height / CGFloat(g.rows)) : 44
            for (i, b) in buttons.enumerated() {
                b.isHidden = false
                // En colonne, l'ordre se lit de haut en bas, colonne après colonne.
                let col = vertical ? i / g.rows : i % g.cols
                let row = vertical ? i % g.rows : i / g.cols
                b.frame = CGRect(x: ox + CGFloat(col) * 44, y: panelRect.minY + CGFloat(row) * step, width: 44, height: step)
            }
            chips.frame = CGRect(x: cx, y: 0, width: max(0, x1 - cx - 6), height: h)
        } else {
            chips.frame = CGRect(x: cx, y: 0, width: max(0, globeButton.frame.minX - cx - 4), height: h)
        }

        rebuildChips()
    }

    private func rebuildChips() {
        let h = Self.topBarHeight
        // Un petit fondu quand les mots changent : moins sec, plus lisible.
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.12
        chipStack.layer.add(fade, forKey: "fade")
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let q = emojiQuery {
            buildSearchChips(q, height: h)
            return
        }
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
        // Tu viens de copier quelque chose : « Coller » dans la barre, comme sur le clavier d'Apple.
        if let t = KBClipboard.shared.freshText, input?.kbFullAccess == true {
            let b = UIButton(type: .system)
            var cfg = UIButton.Configuration.plain()
            let one = t.replacingOccurrences(of: "\n", with: " ")
            cfg.title = one.count > 22 ? String(one.prefix(22)) + "…" : one
            cfg.image = UIImage(systemName: "doc.on.clipboard", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            cfg.imagePadding = 6
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
            b.accessibilityLabel = L("Paste")
            b.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                KBFeedback.shared.tap(sound: self.eff.sound, haptics: self.eff.haptics)
                self.pasteClip(t)
                self.rebuildChips()
            }, for: .touchUpInside)
            chipStack.addArrangedSubview(b)
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
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
        if gripContext == "open-landscape" {
            // Duo ouvert en paysage : en option, le petit clavier qui suit la main (comme sur l'écran extérieur).
            extra.insert(UIAction(title: L("Follow your hand in landscape"), image: UIImage(systemName: "hand.raised"),
                                  state: settings.openLandFollow ? .on : .off) { [weak self] _ in
                guard let self else { return }
                if !self.pro { self.setMode(.auto); return }
                self.settings.openLandFollow.toggle()
                self.settings.mode = .auto
                self.grip.locked = false
                self.save()
                self.updateGripContext()
                self.layoutIfNeeded()
            }, at: 0)
        }
        return UIMenu(title: L("Keyboard position"), children: [UIMenu(options: .displayInline, children: actions)] + extra)
    }

    /// Clavier d'un côté : les boutons 🌐 😀 réglages et masquer passent dans la place libre à côté du clavier,
    /// pour laisser toute la barre du haut aux suggestions (on voit les mots même tenu d'une main).
    private var sideButtonsGrid: (cols: Int, rows: Int, count: Int)? {
        guard layoutMode.isOneHand, !showEmoji, !adjusting, panelRect.width >= 44, panelRect.height >= 132 else { return nil }
        let n = 3 + ((input?.kbNeedsGlobe ?? false) ? 1 : 0) + (eff.emojiKey ? 1 : 0)
        // Duo ouvert en portrait : une colonne verticale collée au clavier, à portée du pouce
        // (une rangée tout en haut de la place libre était trop loin).
        // Les touches ne font qu'environ 170 pt de haut : boutons resserrés (32 pt mini), sur deux colonnes s'il le faut.
        if gripContext == "open-portrait", panelRect.width >= 100 {
            let cols = CGFloat(n) * 32 <= panelRect.height ? 1 : 2
            return (cols, Int(ceil(Double(n) / Double(cols))), n)
        }
        let cols = max(1, min(n, Int(panelRect.width / 44)))
        let rows = Int(ceil(Double(n) / Double(cols)))
        guard CGFloat(rows) * 44 <= panelRect.height - 44 else { return nil }
        return (cols, rows, n)
    }

    /// Ces boutons sont rangés dans la place libre, donc hors de la barre du haut qui les porte : sans ceci,
    /// iOS ne les trouve pas sous le doigt et l'appui part à la place libre (le clavier changeait de côté).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if sideButtonsGrid != nil, !isHidden, isUserInteractionEnabled {
            let q = convert(point, to: topBar)
            for b in [globeButton, emojiButton, clipButton, adjustButton, hideButton] where !b.isHidden && b.alpha > 0.01 && b.frame.contains(q) {
                return b
            }
        }
        return super.hitTest(point, with: event)
    }

    private func rebuildPanel() {
        panel.subviews.forEach { $0.removeFromSuperview() }
        var area = panelRect
        if let g = sideButtonsGrid {
            if gripContext == "open-portrait" {
                // La colonne de boutons longe le clavier : le reste de la place libre est à côté.
                let side = CGFloat(g.cols) * 44 + 12
                area = CGRect(x: isRight ? area.minX : area.minX + side, y: area.minY, width: max(0, area.width - side), height: area.height)
            } else {
                let top = CGFloat(g.rows) * 44 + 6
                area = CGRect(x: area.minX, y: area.minY + top, width: area.width, height: area.height - top)
            }
        }
        panel.frame = area
        guard area.width >= 44, area.height >= 44, eff.sidePanel != .none else { return }
        let w = area.width
        let h = area.height
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
            let fontSize: CGFloat = min(wideFull ? 30 : 26, keyH * 0.56)
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
                v.icon.image = UIImage(systemName: eff.globeAsEmoji ? "face.smiling" : "globe")
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
        // D'abord la touche réellement dessinée sous le doigt (même pendant une animation).
        if let i = cells.firstIndex(where: { ($0.view.layer.presentation()?.frame ?? $0.view.frame).contains(raw) }) { return i }
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
    /// Les derniers appuis : où (x) et quelle touche (pour comprendre une touche mal reconnue).
    private var lastHits: [String] = []
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
            + " · L\(Int(bounds.width)) · " + lastHits.joined(separator: " ")
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
            let label: String
            switch cells[i].view.spec.kind {
            case .char(let c): label = c
            case .backspace: label = "⌫"
            case .ret: label = "⏎"
            case .space: label = "␣"
            default: label = "•"
            }
            lastHits.append("\(Int(p.x))→\(label)")
            if lastHits.count > 4 { lastHits.removeFirst() }
            let tr = Track(index: i, start: p)
            tr.t0 = t.timestamp
            if recording != nil { halo(at: p, radius: t.majorRadius) }
            tr.points = [p]
            if autoOn, layoutMode.isOneHand, case .char(let c) = cells[i].view.spec.kind, c.count == 1, c.first?.isLetter == true {
                let f = cells[i].frame
                let lo = blocks.map { $0.minX }.min() ?? 0
                let hi = blocks.map { $0.maxX }.max() ?? bounds.width
                KBThumb.shared.tap(kx: Double((f.midX - lo) / max(1, hi - lo)), dx: Double((p.x - f.midX) / max(1, f.width)),
                                   radius: Double(t.majorRadius), time: t.timestamp)
                // Et comment le téléphone a bougé sous l'appui (connu un quart de seconde après).
                let ts = t.timestamp
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                    if let k = self?.grip.kick(at: ts) { KBThumb.shared.kick(time: ts, k) }
                }
            }
            // Étalonnage dans l'app (« Apprends tes pouces ») : où tombe le pouce sur chaque lettre, la taille du toucher
            // et la réaction du téléphone, envoyés à l'app (qui les passe au clavier par les réglages).
            if let onThumbSample, recording == .right || recording == .left,
               case .char(let c) = cells[i].view.spec.kind, c.count == 1, c.first?.isLetter == true {
                let f = cells[i].frame
                let lo = blocks.map { $0.minX }.min() ?? 0
                let hi = blocks.map { $0.maxX }.max() ?? bounds.width
                let kx = Double((f.midX - lo) / max(1, hi - lo)), dx = Double((p.x - f.midX) / max(1, f.width))
                let r = Double(t.majorRadius), ts = t.timestamp
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                    if let k = self?.grip.kick(at: ts) { onThumbSample([kx, dx, r, k.x, k.y, k.z]) } else { onThumbSample([kx, dx, r]) }
                }
            }
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
            if let ps = pageSlide, ps.touch == t {
                let j = cellIndex(at: t.location(in: self))
                if j != ps.cell {
                    if let o = ps.cell { setPressed(o, false) }
                    if let j, case .char = cells[j].view.spec.kind { setPressed(j, true) }
                    pageSlide = (t, j)
                }
                continue
            }
            guard let tr = tracks[t], !tr.done, let k = kind(tr) else { continue }
            let p = t.location(in: self)
            // « 123 » gardé appuyé et le doigt qui sort de la touche : la page des chiffres s'ouvre sous le doigt.
            if case .page(let target) = k, page == .letters, target != .letters,
               !cells[tr.index].frame.insetBy(dx: -4, dy: -4).contains(p) {
                tr.done = true
                setPressed(tr.index, false)
                page = target
                builtFor = .zero
                rebuild()
                pageSlide = (t, nil)
                if let j = cellIndex(at: p), case .char = cells[j].view.spec.kind { setPressed(j, true); pageSlide = (t, j) }
                continue
            }
            if tr.points.count < (tr.glide ? 600 : 80) { tr.points.append(p) }
            if tr.glide {
                drawGlide(tr.points)
                continue
            }
            if canGlide(tr, k, to: p) {
                startGlide(tr)
                continue
            }
            // Un balayage vertical du pouce n'écrit rien : il dit quelle main tape (arc du pouce).
            let ddx = p.x - tr.start.x, ddy = p.y - tr.start.y
            if k != .space && !tr.swipe && !tr.cursorMode && tr.accents.isEmpty && abs(ddy) > 44 && abs(ddy) > abs(ddx) * 1.4 {
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
                let dy = p.y - tr.start.y
                if !tr.cursorMode && (abs(dx) > 40 || abs(dy) > 34 || (held && (abs(dx) > 12 || abs(dy) > 12))) {
                    enterTrackpad(tr, at: p)
                }
                if tr.cursorMode, let map = trackMap {
                    // Comme chez Apple : le curseur suit le doigt dans tous les sens, avec une accélération :
                    // un geste lent avance lettre par lettre (précis), un geste rapide va plus loin.
                    let mdx = p.x - tr.lastX, mdy = p.y - tr.lastY
                    let dt = tr.lastT > 0 ? max(0.004, t.timestamp - tr.lastT) : 0.016
                    tr.lastX = p.x; tr.lastY = p.y; tr.lastT = t.timestamp
                    let speed = hypot(mdx, mdy) / CGFloat(dt)          // points par seconde
                    let gain: CGFloat = speed < 120 ? 0.55 : (speed < 600 ? 0.55 + (speed - 120) / 480 * 0.45 : min(1.8, 1 + (speed - 600) / 900))
                    tr.cursorAccum += mdx * gain
                    // Le vertical, plus dur : il faut vraiment monter ou descendre pour changer de ligne.
                    tr.cursorAccumY += mdy * gain * (abs(mdy) > abs(mdx) * 0.6 ? 1 : 0.35)
                    // Réglage « Sensibilité » : de 14 pt par lettre (lent) à 7 pt (rapide).
                    let charStep = 14 - 7 * CGFloat(eff.swipe)
                    let lineStep: CGFloat = 30
                    let dCol = Int((tr.cursorAccum / charStep).rounded(.towardZero))
                    let dLine = Int((tr.cursorAccumY / lineStep).rounded(.towardZero))
                    let target = map.target(dLine: dLine, dCol: dCol)
                    if target != map.current {
                        input?.kbMoveCursor(target - map.current)
                        trackMap?.current = target
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
            if let ps = pageSlide, ps.touch == t {
                pageSlide = nil
                if let j = cellIndex(at: t.location(in: self)), case .char(let c) = cells[j].view.spec.kind {
                    setPressed(j, false)
                    KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
                    typeText(c)
                    page = .letters
                    builtFor = .zero
                    rebuild()
                }
                finish(t)
                continue
            }
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
            if tr.glide {
                tr.done = true
                endGlide(tr)
            } else if tr.swipe {
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
            if pageSlide?.touch == t { pageSlide = nil }
            guard let tr = tracks[t] else { continue }
            tr.done = true
            finish(t)
        }
    }

    // MARK: Écrire en glissant

    /// Le doigt part d'une lettre et file vers d'autres lettres : on écrit en glissant (pas un balayage vertical
    /// du pouce, pas le pavé tactile de l'espace).
    private func canGlide(_ tr: Track, _ k: KeyKind, to p: CGPoint) -> Bool {
        guard eff.glide, emojiQuery == nil, page == .letters, !tr.swipe, !tr.cursorMode, tr.accents.isEmpty, !adjusting else { return false }
        guard case .char(let c) = k, c.count == 1, c.first?.isLetter == true else { return false }
        let kw = cells.first { if case .char = $0.view.spec.kind { return true }; return false }?.frame.width ?? 32
        let dx = p.x - tr.start.x, dy = p.y - tr.start.y
        guard abs(dx) > kw * 0.95 || hypot(dx, dy) > kw * 1.6 else { return false }
        // Arrivé sur une autre lettre.
        guard let j = cellIndex(at: p), j != tr.index, case .char(let c2) = cells[j].view.spec.kind, c2.first?.isLetter == true else { return false }
        return true
    }

    private func startGlide(_ tr: Track) {
        tr.glide = true
        tr.longTimer?.invalidate()
        hideBubble()
        setPressed(tr.index, false)
        if tr.typed != nil {
            input?.kbDelete()
            if !wordTouches.isEmpty { wordTouches.removeLast() }
            tr.typed = nil
        }
        glideLayer.strokeColor = theme.accent.withAlphaComponent(0.55).cgColor
        glideLayer.fillColor = nil
        glideLayer.lineWidth = 7
        glideLayer.lineCap = .round
        glideLayer.lineJoin = .round
        glideLayer.opacity = 1
        if glideLayer.superlayer == nil { layer.addSublayer(glideLayer) }
        glideLayer.zPosition = 50
        drawGlide(tr.points)
    }

    private func drawGlide(_ pts: [CGPoint]) {
        let path = UIBezierPath()
        for (i, p) in pts.suffix(60).enumerated() { if i == 0 { path.move(to: p) } else { path.addLine(to: p) } }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glideLayer.path = path.cgPath
        CATransaction.commit()
    }

    private func endGlide(_ tr: Track) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.25
        glideLayer.add(fade, forKey: "fade")
        glideLayer.opacity = 0
        // Les centres des touches, comme pour la correction.
        var centers: [Character: [CGPoint]] = [:]
        var keyW: CGFloat = 0, keyH: CGFloat = 0
        for c in cells {
            guard case .char(let s) = c.view.spec.kind, s.count == 1, let ch = s.lowercased().first, ch.isLetter else { continue }
            centers[ch, default: []].append(CGPoint(x: c.frame.midX, y: c.frame.midY))
            keyW = max(keyW, c.frame.width); keyH = max(keyH, c.frame.height)
        }
        let model = KBTouchModel(points: [], centers: centers, keyW: keyW, keyH: keyH)
        var before = input?.kbTextBefore() ?? ""
        let found = suggest.glide(tr.points, touch: model, before: before + " ")
        guard var word = found.first else {
            KBFeedback.shared.tap(sound: .off, haptics: eff.haptics * 0.6)
            return
        }
        // Un espace avant le mot, sauf en début de texte, après un espace ou une parenthèse ouvrante.
        if let last = before.last, !last.isWhitespace, !"([{«“\"'’-/".contains(last) {
            input?.kbInsert(" ")
            before += " "
        }
        if shift != .off { word = word.prefix(1).uppercased() + word.dropFirst() }
        if suggest.language.hasPrefix("en"), word == "i" || word.hasPrefix("i’") { word = "I" + word.dropFirst() }
        input?.kbInsert(word)
        glidedWord = word
        lastCorrection = nil
        wordTouches.removeAll()
        if shift == .on { shift = .off; autoShifted = false; updateLabels() }
        let prev = KBSuggest.lastWord(before)
        let start = KBSuggest.atSentenceStart(before + "x", word: "x")
        suggestQueue.async { KBWordStore.shared.commit(word, after: start ? nil : prev) }
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
        // Les autres mots possibles dans la barre : un toucher remplace le mot tracé.
        let others = found.dropFirst().map { w -> String in shift != .off ? w.prefix(1).uppercased() + w.dropFirst() : w }
        suggestGen += 1
        cachedFix = nil
        applySuggestions(Array(others.prefix(3)), nil)
    }

    /// Le pavé tactile : les lettres s'effacent, et le doigt déplace le curseur partout dans le texte.
    private func enterTrackpad(_ tr: Track, at p: CGPoint) {
        if tr.typed != nil { input?.kbDelete(); tr.typed = nil }
        tr.cursorMode = true
        trackMap = TrackMap(before: input?.kbTextBefore() ?? "", after: input?.kbTextAfter() ?? "",
                            perLine: max(24, Int(UIScreen.main.bounds.width / 8.5)), origin: p)
        tr.lastX = p.x
        tr.lastY = p.y
        tr.lastT = 0
        tr.cursorAccum = 0
        tr.cursorAccumY = 0
        hideBubble()
        setTrackpad(true)
        KBFeedback.shared.tap(sound: .off, haptics: max(0.5, eff.haptics))
    }

    private func setTrackpad(_ on: Bool) {
        trackGoalCol = nil
        if !on { trackMap = nil }
        UIView.animate(withDuration: 0.18) {
            // Comme chez Apple : la barre du haut disparaît aussi, il ne reste que le pavé.
            for v in [self.chips, self.modeButton, self.flipButton, self.middleButton, self.bigButton, self.globeButton, self.emojiButton, self.clipButton, self.adjustButton, self.hideButton] as [UIView] {
                v.alpha = on ? 0 : 1
            }
            for c in self.cells {
                c.view.label.alpha = on ? 0 : 1
                c.view.icon.alpha = on ? 0 : 1
                c.view.alpha = on ? 0.55 : 1
            }
        }
    }

    /// Une ligne plus haut ou plus bas, à la même colonne quand le texte a des retours à la ligne.
    private func moveLine(down: Bool) {
        // iOS ne dit pas aux claviers où passent les lignes à l'écran : on suit les retours à la ligne, et
        // dans un long paragraphe on estime une ligne d'après la largeur de l'écran (environ un caractère tous les 8,5 pt).
        let perLine = max(24, Int(UIScreen.main.bounds.width / 8.5))
        let before = input?.kbTextBefore() ?? ""
        let lines = before.components(separatedBy: "\n")
        let here = lines.last?.count ?? 0
        let col = trackGoalCol ?? here
        trackGoalCol = col
        if !down {
            if here >= perLine {
                input?.kbMoveCursor(-perLine)
            } else if lines.count >= 2 {
                let prevLen = lines[lines.count - 2].count
                // Même colonne sur la dernière ligne visuelle du paragraphe d'avant.
                let lastVisual = prevLen % perLine
                input?.kbMoveCursor(-(here + 1 + max(0, lastVisual - col % perLine)))
            } else {
                input?.kbMoveCursor(-min(before.count, perLine))
            }
        } else {
            let after = input?.kbTextAfter() ?? ""
            let parts = after.components(separatedBy: "\n")
            let rest = parts[0].count
            if rest >= perLine {
                input?.kbMoveCursor(perLine)
            } else if parts.count >= 2 {
                input?.kbMoveCursor(rest + 1 + min(col % perLine, parts[1].count))
            } else {
                input?.kbMoveCursor(rest)
            }
        }
    }

    private func finish(_ t: UITouch) {
        if let tr = tracks[t], tr.cursorMode { setTrackpad(false) }
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
        if emojiQuery != nil {
            switch v.spec.kind {
            case .space:
                emojiQuery! += " "
                tr.done = true
                rebuildChips()
                return
            case .backspace:
                if !emojiQuery!.isEmpty { emojiQuery!.removeLast() }
                tr.done = true
                rebuildChips()
                return
            default: break
            }
        }
        if case .space = v.spec.kind {
            // L'espace part dès que le doigt se pose (retiré si le doigt glisse pour déplacer le curseur).
            tr.typed = " "
            typeSpace()
            // Appui long : le clavier devient un pavé tactile, comme chez Apple.
            tr.longTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak tr] _ in
                guard let self, let tr, !tr.done, !tr.cursorMode, !tr.swipe else { return }
                self.enterTrackpad(tr, at: tr.start)
            }
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
            noteTouch(text, at: tr.start)
        case .backspace:
            if let g = glidedWord, (input?.kbTextBefore() ?? "").hasSuffix(g) {
                for _ in 0..<g.count { input?.kbDelete() }
                glidedWord = nil
                wordTouches.removeAll()
                tr.done = true
                refreshSuggestionsSoon()
                break
            }
            if undoCorrection() {
                tr.done = true
                refreshSuggestionsSoon()
                break
            }
            lastCorrection = nil
            input?.kbDelete()
            if !wordTouches.isEmpty { wordTouches.removeLast() }
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
                if emojiQuery != nil {
                    if let typed = tr.typed, emojiQuery!.hasSuffix(typed.lowercased()) { emojiQuery!.removeLast(typed.count) }
                    emojiQuery! += chosen.lowercased()
                    rebuildChips()
                } else if let typed = tr.typed {
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
                noteTouch(s, at: tr.start)
            }
        case .space:
            if !tr.cursorMode && tr.typed == nil { typeSpace() }
        case .ret where emojiQuery != nil:
            if let e = KBEmoji.search(emojiQuery ?? "").first { pickSearchedEmoji(e) } else { endEmojiSearch() }
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
            emojiQuery = nil
            showEmoji = true
            builtFor = .zero
            rebuild()
        case .backspace:
            break
        }
        hideBubble()
    }

    /// La touche ’ du clavier français (à droite du N) sert aussi d'accent, comme chez Apple : ’ puis e → é.
    /// Après une lettre d'élision (l’, d’, j’, qu’…), elle reste une apostrophe : « l’été » s'écrit normalement.
    private static let frAccent: [Character: String] = ["e": "é", "a": "à", "u": "ù", "i": "î", "o": "ô",
                                                         "E": "É", "A": "À", "U": "Ù", "I": "Î", "O": "Ô"]
    /// Mots anglais où « voyelle + ’ » est une vraie contraction (we’re, you’re, she’ll…) : on n'y touche pas.
    private static let enBeforeApostrophe: Set<String> = ["we", "he", "she", "you", "there", "here", "where", "who", "one",
                                                          "someone", "everyone", "anyone", "no", "do", "o", "ma", "be", "i"]

    /// L'autre sens, celui qu'on essaie d'instinct : e puis ’ → é, a puis ’ → à.
    /// Jamais après une consonne (l’, qu’, jusqu’ restent des apostrophes) ni sur une contraction anglaise.
    private func accentAfter(_ text: String) -> Bool {
        guard eff.layout == .azerty, text == "’" || text == "'" else { return false }
        let before = input?.kbTextBefore() ?? ""
        guard let v = before.last, let acc = Self.frAccent[v] else { return false }
        let word = String(before.reversed().prefix { $0.isLetter }.reversed()).lowercased()
        if Self.enBeforeApostrophe.contains(word) { return false }
        // Après qu (« qu’ ») c'est l'élision.
        if word.hasSuffix("qu") { return false }
        // Un mot entre apostrophes ('bonjour') : c'est le guillemet fermant.
        // (Mais « l’e’te » → « l’été » : là, l'apostrophe suit une lettre.)
        let head = before.dropLast(word.count)
        if let open = head.last, "'‘’".contains(open), head.dropLast().last.map({ $0.isWhitespace }) ?? true { return false }
        input?.kbDelete()
        input?.kbInsert(acc)
        return true
    }

    private func accentKey(_ text: String) -> Bool {
        guard eff.layout == .azerty, text.count == 1, let v = text.first else { return false }
        guard let acc = Self.frAccent[v] else { return false }
        let before = input?.kbTextBefore() ?? ""
        guard before.hasSuffix("’") || before.hasSuffix("'") else { return false }
        let prev = before.dropLast().last
        if let p = prev, p.isLetter {
            let l = Character(p.lowercased())
            if "ldjmnstc".contains(l) || (l == "u" && before.dropLast(2).last.map { $0.lowercased() == "q" } == true) { return false }
        }
        input?.kbDelete()
        input?.kbInsert(acc)
        return true
    }

    private func typeText(_ text: String) {
        if emojiQuery != nil {
            emojiQuery! += text.lowercased()
            rebuildChips()
            return
        }
        // Après un mot écrit en glissant, la lettre suivante commence un nouveau mot : l'espace d'abord.
        if let g = glidedWord {
            glidedWord = nil
            if let c = text.first, c.isLetter || c.isNumber, (input?.kbTextBefore() ?? "").hasSuffix(g) { input?.kbInsert(" ") }
        }
        if accentKey(text) || accentAfter(text) {
            lastCorrection = nil
            refreshSuggestionsSoon()
            if shift == .on { shift = .off; autoShifted = false; updateLabels() }
            return
        }
        // Comme chez Apple : « mot . » → « mot. » — l'espace laissée avant un point ou une virgule disparaît.
        // Le mot avant a déjà été traité au moment de l'espace : pas de seconde correction.
        var spaceEaten = false
        if text == "." || text == "," {
            let before = input?.kbTextBefore() ?? ""
            let chars = Array(before.suffix(2))
            if chars.count == 2, chars[1] == " ", !chars[0].isWhitespace, !".,;:!?".contains(chars[0]) {
                input?.kbDelete()
                spaceEaten = true
            }
        }
        if spaceEaten {
            lastCorrection = nil   // le mot est déjà validé
        } else if [".", ",", "!", "?", ";", ":", ")"].contains(text) {
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

    /// Le moment du dernier espace tapé : le point du double espace n'arrive que si on tape deux espaces
    /// coup sur coup (comme chez Apple), pas quand on revient taper un espace plus tard.
    private var lastSpaceAt: TimeInterval = 0

    private func typeSpace() {
        let before = input?.kbTextBefore() ?? ""
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastSpaceAt = now }
        if eff.doubleSpacePeriod, before.hasSuffix(" "), before.count >= 2, now - lastSpaceAt < 0.6 {
            let prev = before[before.index(before.endIndex, offsetBy: -2)]
            // Après une lettre, un chiffre, un emoji, une parenthèse ou un guillemet fermant (« passer" ») :
            // pas après une ponctuation, ni après un guillemet ouvrant.
            let chars = Array(before)
            let beforePrev: Character? = chars.count >= 3 ? chars[chars.count - 3] : nil
            let quote = "\"'’".contains(prev)
            let closingQuote = quote && beforePrev.map { !$0.isWhitespace } == true
            if !prev.isWhitespace, closingQuote || (!quote && !".,;:!?…-–—(«“".contains(prev)) {
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

    /// La barre pendant la recherche d'emoji : ✕, la recherche tapée, puis les emojis trouvés.
    private func buildSearchChips(_ q: String, height h: CGFloat) {
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = theme.text.withAlphaComponent(0.5)
        close.accessibilityLabel = L("Cancel")
        close.addAction(UIAction { [weak self] _ in self?.endEmojiSearch() }, for: .touchUpInside)
        chipStack.addArrangedSubview(close)
        close.widthAnchor.constraint(equalToConstant: 30).isActive = true
        close.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let field = UILabel()
        let icon = NSTextAttachment(image: UIImage(systemName: "magnifyingglass")!.withTintColor(theme.text.withAlphaComponent(0.5), renderingMode: .alwaysOriginal))
        let txt = NSMutableAttributedString(attachment: icon)
        txt.append(NSAttributedString(string: " " + (q.isEmpty ? L("Search emoji") : q + "|"),
                                      attributes: [.foregroundColor: theme.text.withAlphaComponent(q.isEmpty ? 0.5 : 1), .font: eff.font.ui(size: 15, weight: .medium)]))
        field.attributedText = txt
        field.backgroundColor = theme.key.withAlphaComponent(0.6)
        field.layer.cornerRadius = 14
        field.layer.masksToBounds = true
        field.textAlignment = .center
        chipStack.addArrangedSubview(field)
        field.widthAnchor.constraint(equalToConstant: max(110, min(170, field.intrinsicContentSize.width + 24))).isActive = true
        field.heightAnchor.constraint(equalToConstant: 30).isActive = true
        for e in KBEmoji.search(q).prefix(24) {
            let b = UIButton(type: .system)
            b.setTitle(e, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 26)
            b.addAction(UIAction { [weak self] _ in self?.pickSearchedEmoji(e) }, for: .touchUpInside)
            chipStack.addArrangedSubview(b)
            b.widthAnchor.constraint(equalToConstant: 40).isActive = true
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        chipStack.layoutIfNeeded()
        let w = chipStack.systemLayoutSizeFitting(CGSize(width: 10_000, height: 36)).width
        chipStack.frame = CGRect(x: 0, y: (h - 36) / 2, width: w, height: 36)
        chips.contentSize = CGSize(width: w, height: h)
        chips.contentOffset = .zero
    }

    private func pickSearchedEmoji(_ e: String) {
        insertEmoji(e)
        endEmojiSearch()
    }

    private func endEmojiSearch() {
        emojiQuery = nil
        rebuildChips()
        refreshSuggestionsSoon()
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
        // Le mot terminé (corrigé ou non) est retenu : tes mots et ce qui suit quoi (pour la barre et la correction).
        let before0 = input?.kbTextBefore() ?? ""
        let typed0 = KBSuggest.currentWord(before0)
        defer {
            if !typed0.isEmpty, let final = KBSuggest.lastWord(input?.kbTextBefore() ?? "") {
                let prev = KBSuggest.previousWord(before0, word: typed0)
                let sentenceStart = KBSuggest.atSentenceStart(before0, word: typed0)
                suggestQueue.async { KBWordStore.shared.commit(final, after: sentenceStart ? nil : prev) }
            }
        }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        // Tes remplacements de texte (Réglages > Général > Clavier) : appliqués même sans correction automatique,
        // comme sur le clavier d'Apple.
        // Le raccourci peut contenir des chiffres ou des signes (« @@ », « adr1 ») : tout ce qui suit la dernière espace.
        let token = String(before.reversed().prefix { !$0.isWhitespace }.reversed())
        if !token.isEmpty, let r = suggest.replacement(for: token), r != token {
            wordTouches.removeAll()
            for _ in 0..<token.count { input?.kbDelete() }
            input?.kbInsert(r)
            lastCorrection = (token, r, sep)
            return
        }
        if !eff.autocorrect, !word.isEmpty, let r = suggest.replacement(for: word), r != word {
            wordTouches.removeAll()
            for _ in 0..<word.count { input?.kbDelete() }
            input?.kbInsert(r)
            lastCorrection = (word, r, sep)
            return
        }
        guard eff.autocorrect, page == .letters || sep != " " else { return }
        let known: String?? = cachedFix?.word == word ? .some(cachedFix?.fix) : nil
        // La correction préparée en arrière-plan si elle est prête, sinon on la calcule (quelques ms : la mesure
        // de fluidité montre que le clavier a toute la marge).
        var computed: String? = known ?? suggest.correction(for: word, before: before, touch: touchModel(for: word))
        // La majuscule du début de phrase reste : « Hâte » ne redevient jamais « hâte ».
        if let c = computed { computed = Self.keepCapital(c, like: word) }
        guard !word.isEmpty, let fix = computed, fix != word else {
            lastCorrection = nil
            wordTouches.removeAll()
            return
        }
        wordTouches.removeAll()
        for _ in 0..<word.count { input?.kbDelete() }
        input?.kbInsert(fix)
        lastCorrection = (word, fix, sep)
    }

    /// Le mot tapé commence par une majuscule : la correction aussi.
    static func keepCapital(_ fix: String, like word: String) -> String {
        guard let f = word.first, f.isUppercase, let g = fix.first, g.isLowercase else { return fix }
        return g.uppercased() + fix.dropFirst()
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
        let item = Self.keepCapital(suggestionItems[i], like: word)
        if suggestionBest != nil && i == 0 {
            // Le mot tel qu'il a été tapé (entre guillemets) : on le garde et on l'apprend.
            suggest.learn(word)
            let w1 = word
            suggestQueue.async { [bgSuggest] in bgSuggest.learn(w1) }
        }
        for _ in 0..<word.count { input?.kbDelete() }
        glidedWord = nil
        input?.kbInsert(item + " ")
        lastCorrection = nil
        wordTouches.removeAll()
        let prev = word.isEmpty ? KBSuggest.lastWord(before) : KBSuggest.previousWord(before, word: word)
        let start = KBSuggest.atSentenceStart(before + (word.isEmpty ? "x" : ""), word: word.isEmpty ? "x" : word)
        if !item.contains(" ") { suggestQueue.async { KBWordStore.shared.commit(item, after: start ? nil : prev) } }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: w)
    }

    private func refreshSuggestions() {
        guard eff.suggestions && page == .letters else {
            applySuggestions([], nil)
            return
        }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        guard !word.isEmpty else {
            // Après une espace : le mot suivant le plus probable, comme le clavier d'Apple.
            suggestGen += 1
            let gen = suggestGen
            guard before.hasSuffix(" ") || before.isEmpty else { applySuggestions([], nil); return }
            suggestQueue.async { [weak self, bgSuggest] in
                let items = bgSuggest.predictions(before: before)
                DispatchQueue.main.async {
                    guard let self, gen == self.suggestGen else { return }
                    self.cachedFix = nil
                    self.applySuggestions(items, nil)
                }
            }
            return
        }
        suggestGen += 1
        let gen = suggestGen
        let auto = eff.autocorrect
        let touch = touchModel(for: word)
        suggestQueue.async { [weak self, bgSuggest] in
            let (items, best) = bgSuggest.suggestions(for: word, before: before, touch: touch)
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
