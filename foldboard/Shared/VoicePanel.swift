import UIKit

/// La dictée dans le clavier, comme les claviers de dictée (Wispr Flow, Diction) : les touches laissent la place à un
/// grand panneau. On voit sa voix (des ondes lumineuses qui suivent la voix, et un liseré de lumière qui tourne
/// autour du panneau, comme Apple Intelligence), le texte qui s'écrit, et deux boutons : annuler, ou valider.
/// Quand l'app doit d'abord ouvrir le micro (une fois par session), le panneau l'explique et propose un seul bouton ;
/// au retour, la dictée démarre toute seule.
final class KBVoicePanel: UIView {
    enum Mode: Equatable { case connecting, needsApp, listening, finishing }

    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    var onOpenApp: (() -> Void)?

    private(set) var mode = Mode.connecting
    private let status = UILabel()
    private let transcript = UILabel()
    private let bars = UIView()
    private var barViews: [UIView] = []
    private var levels: [CGFloat] = Array(repeating: 0, count: 28)
    private let cancel = UIButton(type: .system)
    private let done = UIButton(type: .system)
    private let openApp = UIButton(type: .system)
    /// Les ondes : trois rubans de lumière, chacun sa couleur, qui ondulent plus fort quand on parle.
    private var waveLayers: [CAShapeLayer] = []
    private let waveColors: [UIColor] = [UIColor(red: 0.25, green: 0.85, blue: 1, alpha: 1),
                                         UIColor(red: 0.62, green: 0.42, blue: 1, alpha: 1),
                                         UIColor(red: 1, green: 0.38, blue: 0.72, alpha: 1)]
    /// Le liseré qui tourne autour du panneau.
    private let glowHolder = CALayer()
    private let glowGradient = CAGradientLayer()
    private let glowMask = CAShapeLayer()
    private var link: CADisplayLink?
    private var phase: CGFloat = 0
    private var amp: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private var accent: UIColor = .systemBlue
    private var text: UIColor = .label
    private var key: UIColor = .systemGray4

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous

        status.font = .systemFont(ofSize: 15, weight: .semibold)
        status.textAlignment = .center
        addSubview(status)

        transcript.font = .systemFont(ofSize: 19, weight: .regular)
        transcript.numberOfLines = 3
        transcript.lineBreakMode = .byTruncatingHead
        transcript.textAlignment = .center
        addSubview(transcript)

        for c in waveColors {
            let l = CAShapeLayer()
            l.fillColor = UIColor.clear.cgColor
            l.strokeColor = c.cgColor
            l.lineWidth = 3
            l.lineCap = .round
            l.shadowColor = c.cgColor
            l.shadowRadius = 7
            l.shadowOpacity = 0.9
            l.shadowOffset = .zero
            bars.layer.addSublayer(l)
            waveLayers.append(l)
        }
        addSubview(bars)
        glowGradient.type = .conic
        glowGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowGradient.endPoint = CGPoint(x: 0.5, y: 0)
        glowGradient.colors = (waveColors + [UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1), waveColors[0]]).map(\.cgColor)
        glowHolder.addSublayer(glowGradient)
        glowMask.fillColor = UIColor.clear.cgColor
        glowMask.strokeColor = UIColor.black.cgColor
        glowMask.lineWidth = 3
        glowHolder.mask = glowMask
        glowHolder.opacity = 0
        layer.addSublayer(glowHolder)

        let big = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        cancel.setImage(UIImage(systemName: "xmark", withConfiguration: big), for: .normal)
        cancel.accessibilityLabel = L("Cancel")
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        addSubview(cancel)

        done.setImage(UIImage(systemName: "checkmark", withConfiguration: big), for: .normal)
        done.accessibilityLabel = L("Done")
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        addSubview(done)

        var cfg = UIButton.Configuration.filled()
        cfg.cornerStyle = .capsule
        cfg.image = UIImage(systemName: "mic.fill")
        cfg.imagePadding = 8
        cfg.title = L("Turn on dictation")
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)
        openApp.configuration = cfg
        openApp.addAction(UIAction { [weak self] _ in self?.onOpenApp?() }, for: .touchUpInside)
        addSubview(openApp)
        set(.connecting)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Les touchers sur le panneau ne doivent pas tomber sur les touches du clavier en dessous.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    func style(background: UIColor, key: UIColor, text: UIColor, accent: UIColor) {
        backgroundColor = background
        self.key = key
        self.text = text
        self.accent = accent
        status.textColor = text.withAlphaComponent(0.6)
        transcript.textColor = text
        cancel.tintColor = text
        cancel.backgroundColor = key
        done.tintColor = .white
        done.backgroundColor = accent
        openApp.configuration?.baseBackgroundColor = accent
        openApp.configuration?.baseForegroundColor = .white
    }

    func set(_ m: Mode, text t: String? = nil) {
        mode = m
        switch m {
        case .connecting: status.text = L("Dictation")
        case .needsApp: status.text = L("Foldboard opens for a moment to turn on the microphone. Come back here: it listens right away.")
        case .listening: status.text = L("Listening…")
        case .finishing: status.text = L("Writing…")
        }
        status.numberOfLines = m == .needsApp ? 3 : 1
        if let t { transcript.text = t } else if m == .connecting || m == .needsApp { transcript.text = nil }
        openApp.isHidden = m != .needsApp
        done.isHidden = m == .needsApp
        bars.isHidden = m == .needsApp
        done.alpha = m == .finishing ? 0.5 : 1
        if m != .listening { push(level: 0) }
        // Le liseré tourne pendant l'écoute et l'écriture ; les ondes vivent tant que le panneau est là.
        let lit = m == .listening || m == .finishing || m == .connecting
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        glowHolder.opacity = lit ? (m == .connecting ? 0.45 : 0.85) : 0
        CATransaction.commit()
        if lit, glowGradient.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = m == .finishing ? 1.6 : 3.2
            spin.repeatCount = .infinity
            glowGradient.add(spin, forKey: "spin")
        } else if !lit {
            glowGradient.removeAnimation(forKey: "spin")
        }
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !isHidden { startLink() } else { stopLink() }
    }

    override var isHidden: Bool {
        didSet { if isHidden { stopLink() } else if window != nil { startLink() } }
    }

    private func startLink() {
        guard link == nil else { return }
        let l = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        lastTick = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// Une image : les ondes avancent, leur hauteur suit la voix (lissée), avec un léger souffle même en silence.
    fileprivate func tick(_ l: CADisplayLink) {
        let dt = lastTick == 0 ? 1.0 / 60 : min(0.05, l.timestamp - lastTick)
        lastTick = l.timestamp
        let recent = levels.suffix(4).reduce(0, +) / 4
        let target = mode == .listening ? max(0.08, recent) : (mode == .finishing ? 0.12 : 0.05)
        amp += (target - amp) * min(1, CGFloat(dt) * 9)
        phase += CGFloat(dt) * (2.4 + amp * 5)
        drawWaves()
    }

    private func drawWaves() {
        let w = bars.bounds.width, h = bars.bounds.height
        guard w > 10, h > 4 else { return }
        let mid = h / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (k, layer) in waveLayers.enumerated() {
            let path = UIBezierPath()
            let freq = 1.6 + CGFloat(k) * 0.55
            let shift = CGFloat(k) * 2.1
            let a = amp * (h / 2 - 4) * (1 - CGFloat(k) * 0.18)
            var x: CGFloat = 0
            while x <= w {
                let t = x / w
                // Les bords restent posés, le milieu ondule (comme Siri).
                let env = sin(.pi * t)
                let y = mid + sin(t * .pi * 2 * freq + phase * (1 + CGFloat(k) * 0.3) + shift) * a * env
                if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                x += 3
            }
            layer.path = path.cgPath
            layer.opacity = Float(0.55 + 0.45 * min(1, amp * 2))
        }
        CATransaction.commit()
    }

    /// Un niveau de voix (0 à 1) : les barres défilent de droite à gauche.
    func push(level: CGFloat) {
        levels.removeFirst()
        levels.append(max(0, min(1, level)))
        layoutBars()
    }

    private func layoutBars() {
        for l in waveLayers { l.frame = bars.bounds }
        if link == nil { drawWaves() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let pad: CGFloat = 16
        status.frame = CGRect(x: pad, y: 12, width: w - 2 * pad, height: mode == .needsApp ? 64 : 22)
        let btn: CGFloat = 54
        cancel.frame = CGRect(x: pad, y: h - btn - 14, width: btn, height: btn)
        cancel.layer.cornerRadius = btn / 2
        done.frame = CGRect(x: w - pad - btn, y: h - btn - 14, width: btn, height: btn)
        done.layer.cornerRadius = btn / 2
        bars.frame = CGRect(x: cancel.frame.maxX + 16, y: h - btn - 14, width: max(0, done.frame.minX - cancel.frame.maxX - 32), height: btn)
        let ty = status.frame.maxY + 6
        transcript.frame = CGRect(x: pad, y: ty, width: w - 2 * pad, height: max(0, bars.frame.minY - ty - 6))
        let s = openApp.sizeThatFits(CGSize(width: w - 2 * pad, height: 60))
        openApp.frame = CGRect(x: (w - s.width) / 2, y: max(status.frame.maxY + 10, (h - s.height) / 2 + 10), width: s.width, height: s.height)
        layoutBars()
        // Le liseré suit le bord arrondi du panneau ; le dégradé, plus grand, tourne dessous.
        glowHolder.frame = bounds
        glowMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: layer.cornerRadius).cgPath
        let d = hypot(w, h)
        glowGradient.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        glowGradient.position = CGPoint(x: w / 2, y: h / 2)
    }
}

/// Le minuteur d'images ne retient pas le panneau (sinon il ne serait jamais libéré).
private final class WeakTarget: NSObject {
    weak var panel: KBVoicePanel?
    init(_ p: KBVoicePanel) { panel = p }
    @objc func tick(_ l: CADisplayLink) {
        guard let panel else { l.invalidate(); return }
        panel.tick(l)
    }
}
