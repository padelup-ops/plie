import UIKit

/// La dictée dans le clavier, comme les claviers de dictée (Wispr Flow, Diction) : les touches laissent la place à un
/// grand panneau. On voit sa voix (barres qui bougent), le texte qui s'écrit, et deux boutons : annuler, ou valider.
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

        for _ in levels {
            let v = UIView()
            v.layer.cornerRadius = 2
            bars.addSubview(v)
            barViews.append(v)
        }
        addSubview(bars)

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
        for v in barViews { v.backgroundColor = accent }
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
        setNeedsLayout()
    }

    /// Un niveau de voix (0 à 1) : les barres défilent de droite à gauche.
    func push(level: CGFloat) {
        levels.removeFirst()
        levels.append(max(0, min(1, level)))
        layoutBars()
    }

    private func layoutBars() {
        let n = CGFloat(barViews.count)
        let w = bars.bounds.width, h = bars.bounds.height
        guard n > 0, w > 0 else { return }
        let step = w / n
        for (i, v) in barViews.enumerated() {
            let bh = max(4, min(h, 4 + levels[i] * (h - 6)))
            v.frame = CGRect(x: CGFloat(i) * step + (step - 4) / 2, y: (h - bh) / 2, width: 4, height: bh)
            v.alpha = 0.35 + 0.65 * levels[i]
        }
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
    }
}
