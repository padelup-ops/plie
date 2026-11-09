import UIKit

/// « Ajuster le clavier » : on glisse le clavier pour le déplacer, on tire ses bords pour l'élargir ou le rétrécir.
/// Une étiquette donne la mesure en direct ; ↺ remet les réglages de départ, ✕ annule, ✓ valide.
final class AdjustOverlay: UIView {
    enum Grab { case move, leftEdge, rightEdge, leftHalf, rightHalf }

    /// Un seul axe à la fois : de côté (position, largeur) ou de haut en bas (hauteur des touches).
    var onPan: ((Grab, CGFloat, CGFloat) -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
    var onReset: (() -> Void)?

    private let dim = CAShapeLayer()
    private let border = CAShapeLayer()
    private var handles: [UIView] = []
    private let label = PaddedLabel()
    private let ok = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    private let reset = UIButton(type: .system)
    private var blocks: [CGRect] = []
    private var split = false
    private var grab: Grab = .move
    private var lastX: CGFloat = 0
    private var lastY: CGFloat = 0
    private var start: CGPoint = .zero
    private var vertical: Bool?
    private let tick = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        dim.fillRule = .evenOdd
        dim.fillColor = UIColor.black.withAlphaComponent(0.35).cgColor
        layer.addSublayer(dim)
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 3
        layer.addSublayer(border)

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.layer.cornerRadius = 15
        label.layer.masksToBounds = true
        addSubview(label)

        for (b, symbol) in [(reset, "arrow.counterclockwise"), (cancel, "xmark"), (ok, "checkmark")] {
            b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
            b.layer.cornerRadius = 26
            b.layer.shadowColor = UIColor.black.cgColor
            b.layer.shadowOpacity = 0.25
            b.layer.shadowRadius = 8
            b.layer.shadowOffset = CGSize(width: 0, height: 3)
            addSubview(b)
        }
        ok.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        reset.addAction(UIAction { [weak self] _ in self?.onReset?() }, for: .touchUpInside)
        reset.accessibilityLabel = L("Default")
        cancel.accessibilityLabel = L("Cancel")
        ok.accessibilityLabel = L("Done")

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(blocks: [CGRect], split: Bool, accent: UIColor, text: String) {
        self.blocks = blocks
        self.split = split
        let all = UIBezierPath(rect: bounds)
        let outline = UIBezierPath()
        for b in blocks {
            let r = UIBezierPath(roundedRect: b.insetBy(dx: -2, dy: -2), cornerRadius: 14)
            all.append(r)
            outline.append(r)
        }
        dim.frame = bounds
        dim.path = all.cgPath
        border.frame = bounds
        border.path = outline.cgPath
        border.strokeColor = accent.cgColor

        handles.forEach { $0.removeFromSuperview() }
        handles = []
        for b in blocks {
            for x in [b.minX - 2, b.maxX + 2] {
                let h = UIView(frame: CGRect(x: x - 4, y: b.midY - 26, width: 8, height: 52))
                h.backgroundColor = accent
                h.layer.cornerRadius = 4
                h.isUserInteractionEnabled = false
                addSubview(h)
                handles.append(h)
            }
        }

        let union = blocks.reduce(blocks.first ?? .zero) { $0.union($1) }
        label.text = text
        label.textColor = .black
        label.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        let size = label.sizeThatFits(CGSize(width: bounds.width, height: 30))
        label.frame = CGRect(x: union.midX - size.width / 2, y: union.minY + 10, width: size.width, height: 30)

        let s: CGFloat = 52
        let y = union.midY - s / 2 + 12
        reset.frame = CGRect(x: union.midX - s * 1.5 - 14, y: y, width: s, height: s)
        cancel.frame = CGRect(x: union.midX - s / 2, y: y, width: s, height: s)
        ok.frame = CGRect(x: union.midX + s / 2 + 14, y: y, width: s, height: s)
        for b in [reset, cancel] {
            b.backgroundColor = .white
            b.tintColor = .black
        }
        ok.backgroundColor = .black
        ok.tintColor = .white
        [reset, cancel, ok].forEach { bringSubviewToFront($0) }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            lastX = p.x
            lastY = p.y
            start = p
            vertical = nil
            tick.prepare()
            if split {
                grab = p.x < bounds.midX ? .leftHalf : .rightHalf
            } else if let b = blocks.first {
                if abs(p.x - b.minX) < 30 { grab = .leftEdge }
                else if abs(p.x - b.maxX) < 30 { grab = .rightEdge }
                else { grab = .move }
            }
        case .changed:
            let dx = p.x - lastX, dy = p.y - lastY
            lastX = p.x
            lastY = p.y
            if vertical == nil, hypot(p.x - start.x, p.y - start.y) > 10 {
                vertical = abs(p.y - start.y) > abs(p.x - start.x) * 1.3
            }
            guard let vertical else { return }
            if vertical { if dy != 0 { onPan?(grab, 0, dy) } }
            else if dx != 0 { onPan?(grab, dx, 0) }
        case .ended, .cancelled:
            tick.selectionChanged()
        default:
            break
        }
    }
}

/// Une étiquette avec un peu d'air autour du texte.
final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 12, dy: 0)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(size)
        return CGSize(width: s.width + 24, height: s.height)
    }
}
