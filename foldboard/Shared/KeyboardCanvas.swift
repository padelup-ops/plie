import UIKit

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Ce que le clavier demande à son hôte (l'extension clavier, ou l'aperçu dans l'app).
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
    private let hideButton = UIButton(type: .system)
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
        for b in [modeButton, flipButton, hideButton] {
            b.tintColor = .label
            topBar.addSubview(b)
        }
        modeButton.showsMenuAsPrimaryAction = true
        flipButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        flipButton.addAction(UIAction { [weak self] _ in self?.flipSide() }, for: .touchUpInside)
        flipButton.accessibilityLabel = L("Switch side")
        // Appui long : la situation reconnue et l'étalonnage utilisé (pour vérifier).
        flipButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(showGripInfo(_:))))
        hideButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hideButton.addAction(UIAction { [weak self] _ in self?.input?.kbDismiss() }, for: .touchUpInside)
        hideButton.accessibilityLabel = L("Hide keyboard")
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
                self.updateGripContext()
                self.builtFor = .zero
                self.setNeedsLayout()
            })
        }
    }

    private func updateGripContext() {
        var c = KBSettings.context(screen: screenSize, closed: hingeClosed)
        // La largeur du clavier dit sur quel écran et dans quel sens on est : on reprend la situation étalonnée
        // à cette largeur (l'app et le clavier tombent ainsi toujours sur le même étalonnage).
        let w = Double(bounds.width)
        if w > 50, let best = settings.widths.min(by: { abs($0.value - w) < abs($1.value - w) }), abs(best.value - w) <= 24 {
            c = best.key
        }
        gripContext = c
        grip.guessUncalibrated = !gripContext.hasPrefix("open")
        let r = settings.roll("right", context: gripContext), l = settings.roll("left", context: gripContext)
        if let r, let l, abs(kbWrap(r - l)) >= 3 {
            let mid = kbWrap(r + kbWrap(l - r) / 2)
            grip.tiltMid = mid
            grip.rightNegative = kbWrap(r - mid) < 0
            grip.tiltGap = abs(kbWrap(r - l))
        } else {
            grip.tiltMid = 0
            grip.rightNegative = true
            grip.tiltGap = 0
        }
        grip.tapModel = KBTapModel(settings.taps[gripContext] ?? [:])
        grip.swipeModel = KBTapModel(settings.swipes[gripContext] ?? [:], kind: .swipe)
        var postures: [KBGrip: (roll: Double, incline: Double)] = [:]
        for (k, p) in settings.calib[gripContext] ?? [:] where p.count == 2 {
            guard let g = KBGrip(rawValue: k) else { continue }
            postures[g] = (settings.roll(k, context: gripContext) ?? p[0], p[1])
        }
        grip.postures = postures
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        watchHinge()
        updateGripContext()
    }

    /// Le clavier disparaît : on coupe les capteurs.
    func disappeared() {
        visible = false
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
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            guard let self, let g = self.pendingGrip, self.tracks.isEmpty else { return }
            self.applyGrip(g)
        }
    }

    private func applyGrip(_ g: KBGrip) {
        pendingGrip = nil
        var s = settings
        s.autoTwo = g == .two
        if g != .two { s.autoRight = g == .right }
        grip.current = g
        guard s.autoTwo != settings.autoTwo || s.autoRight != settings.autoRight else { return }
        settings = s
        UIView.transition(with: self, duration: 0.15, options: .transitionCrossDissolve, animations: {
            self.save()
            self.layoutIfNeeded()
        })
    }

    /// Le lexique de l'utilisateur (contacts, remplacements de texte).
    func setLexicon(_ lexicon: UILexicon) {
        suggest.setLexicon(lexicon)
    }

    /// Le texte a changé (curseur déplacé, autre champ) : on revoit la majuscule et les suggestions.
    func textChanged() {
        refreshSuggestions()
        refreshShift()
    }

    private func save() {
        input?.kbSettingsChanged(settings)
        configure(settings: settings, pro: pro)
    }

    private func setMode(_ m: KBMode) {
        if (m == .auto || m == .split) && !pro {
            flash(L("Foldboard Pro: open the app to unlock"))
            return
        }
        settings.mode = m
        save()
    }

    @objc private func showGripInfo(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let names = ["closed-portrait": L("Closed · portrait"), "open-portrait": L("Open · portrait"),
                     "open-landscape": L("Open · landscape"), "closed-landscape": L("Closed · landscape")]
        let n = settings.taps[gripContext]?.values.filter { $0.count >= 6 }.count ?? 0
        let state = grip.tapModel != nil ? String(format: L("calibrated (%lld grips)"), n)
            : (grip.calibrated ? L("tilt only") : L("not calibrated"))
        flash((names[gripContext] ?? gripContext) + " · " + state)
    }

    private func flipSide() {
        switch eff.mode {
        case .auto:
            settings.autoRight = settings.autoTwo ? true : !settings.autoRight
            settings.autoTwo = false
            grip.current = settings.autoRight ? .right : .left
            // Le choix fait à la main apprend à la détection comment tu tiens le téléphone.
            if let a = grip.currentAngle { settings.learn(roll: a, right: settings.autoRight, context: gripContext) }
        case .left: settings.mode = .right
        case .right: settings.mode = .left
        default: return
        }
        UIView.animate(withDuration: 0.25) { self.save(); self.layoutIfNeeded() }
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
    private var layoutMode: KBMode {
        if eff.mode == .auto && eff.autoTwo { return splitAllowed ? .split : .full }
        if eff.mode == .split && !splitAllowed { return .full }
        return eff.mode
    }

    private func rebuild() {
        // Les touches vont changer : les appuis en cours s'arrêtent là.
        for tr in tracks.values {
            tr.done = true
            tr.longTimer?.invalidate()
            tr.repeatTimer?.invalidate()
        }
        backgroundColor = theme.background
        cells.forEach { $0.view.removeFromSuperview() }
        cells = []
        let W = bounds.width
        let top = Self.topBarHeight + 6
        let areaH = CGFloat(rowCount) * keyH + CGFloat(rowCount - 1) * vgap
        let margin = CGFloat(eff.edgeMargin)
        let rows = KBLayouts.rows(page, layout: eff.layout)
        let globe = input?.kbNeedsGlobe ?? false

        switch layoutMode {
        case .full:
            let b = CGRect(x: pad, y: top, width: W - 2 * pad, height: areaH)
            blocks = [b]
            panelRect = .zero
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout)], in: b, align: 0)
        case .left, .right, .auto:
            let bw = min(W - 2 * pad, max(250, W * CGFloat(eff.oneHandWidth)))
            let x = isRight ? W - margin - bw : margin
            let b = CGRect(x: max(0, x), y: top, width: bw, height: areaH)
            blocks = [b]
            panelRect = isRight
                ? CGRect(x: 6, y: top, width: max(0, b.minX - 12), height: areaH)
                : CGRect(x: b.maxX + 6, y: top, width: max(0, W - b.maxX - 12), height: areaH)
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout)], in: b, align: 0)
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
        let oneHand = layoutMode.isOneHand
        flipButton.isHidden = !oneHand
        flipButton.tintColor = theme.text.withAlphaComponent(0.7)
        flipButton.frame = CGRect(x: 46, y: 0, width: oneHand ? 36 : 0, height: h)
        hideButton.tintColor = theme.text.withAlphaComponent(0.7)
        hideButton.frame = CGRect(x: bounds.width - 46, y: 0, width: 40, height: h)
        let cx = flipButton.frame.maxX + 4
        chips.frame = CGRect(x: cx, y: 0, width: max(0, hideButton.frame.minX - cx - 4), height: h)

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
        return UIMenu(title: L("Keyboard position"), children: actions)
    }

    private func rebuildPanel() {
        panel.subviews.forEach { $0.removeFromSuperview() }
        panel.frame = panelRect
        guard panelRect.width >= 44, panelRect.height >= 44, eff.sidePanel != .none else { return }
        let w = panelRect.width
        let h = panelRect.height
        if eff.sidePanel == .emoji || (layoutMode == .split && eff.sidePanel == .phrases && w < 90) {
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
            }
            v.setNeedsLayout()
        }
    }

    // MARK: Touchers


    private func cellIndex(at p: CGPoint) -> Int? {
        if let i = cells.firstIndex(where: { $0.hit.contains(p) }) { return i }
        guard blocks.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(p) }) else { return nil }
        var best: (Int, CGFloat)?
        for (i, c) in cells.enumerated() {
            let d = hypot(c.frame.midX - p.x, c.frame.midY - p.y)
            if d < 44, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        idleTimer?.invalidate()
        for t in touches {
            let p = t.location(in: self)
            // Un toucher dans l'espace vide de l'autre côté : le clavier y passe.
            if eff.mode == .auto && layoutMode.isOneHand && panelRect.contains(p) {
                flipSide()
                continue
            }
            guard p.y > Self.topBarHeight, let i = cellIndex(at: p) else { continue }
            // Frappe en roulement : la touche précédente encore enfoncée part tout de suite.
            for o in order {
                if let tr = tracks[o], !tr.done, case .char? = kind(tr), tr.accents.isEmpty {
                    commit(tr)
                }
            }
            let tr = Track(index: i, start: p)
            tr.t0 = t.timestamp
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
            if !tr.swipe && !tr.cursorMode && tr.accents.isEmpty && abs(ddy) > 30 && abs(ddy) > abs(ddx) * 1.2 {
                tr.swipe = true
                tr.longTimer?.invalidate()
                hideBubble()
            }
            if tr.swipe { continue }
            if k == .space {
                let dx = p.x - tr.start.x
                if !tr.cursorMode && abs(dx) > 12 {
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
        for t in touches {
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
            updateLabels()
        }
    }

    private func press(_ tr: Track) {
        let v = cells[tr.index].view
        let strong: Bool
        switch v.spec.kind {
        case .backspace, .ret, .shift: strong = true
        default: strong = false
        }
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics, strong: strong)
        setPressed(tr.index, true)
        switch v.spec.kind {
        case .char(let s):
            showBubble(over: cells[tr.index].frame, text: shift != .off && page == .letters ? s.uppercased() : s)
            let options = KBLayouts.accents(s, layout: eff.layout)
            if !options.isEmpty {
                tr.longTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self, weak tr] _ in
                    guard let self, let tr, !tr.done else { return }
                    let upper = self.shift != .off && self.page == .letters
                    tr.accents = options.map { upper ? $0.uppercased() : $0 }
                    tr.accentIndex = 0
                    self.hideBubble()
                    self.showAccents(tr.accents, over: self.cells[tr.index].frame)
                }
            }
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
                typeText(tr.accents[tr.accentIndex])
                accentView.isHidden = true
            } else {
                typeText(shift != .off && page == .letters ? s.uppercased() : s)
            }
        case .space:
            if !tr.cursorMode { typeSpace() }
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
        input?.kbInsert(e)
        refreshSuggestionsSoon()
    }

    // MARK: Correction et suggestions

    /// Avant un espace ou une ponctuation : on corrige le mot qui vient d'être tapé.
    private func autocorrect(sep: String) {
        guard eff.autocorrect, page == .letters || sep != " " else { return }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        guard !word.isEmpty, let fix = suggest.correction(for: word, before: before), fix != word else {
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
        }
        for _ in 0..<word.count { input?.kbDelete() }
        input?.kbInsert(item + " ")
        lastCorrection = nil
        refreshSuggestionsSoon()
        refreshShiftSoon()
    }

    private func refreshSuggestionsSoon() {
        DispatchQueue.main.async { [weak self] in self?.refreshSuggestions() }
    }

    private func refreshSuggestions() {
        var items: [String] = []
        var best: Int?
        if eff.suggestions && page == .letters {
            let before = input?.kbTextBefore() ?? ""
            let word = KBSuggest.currentWord(before)
            (items, best) = suggest.suggestions(for: word, before: before)
            if !eff.autocorrect { best = nil }
        }
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
        bubble.font = eff.font.ui(size: min(34, keyH * 0.72))
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
