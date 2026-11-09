import UIKit

/// Les emojis, comme sur le clavier d'Apple : une touche 😀 ouvre une grille qui défile, rangée par catégories,
/// avec les récents en premier. « ABC » revient aux lettres.
enum KBEmoji {
    static let categories: [(symbol: String, list: [String])] = [
        ("face.smiling", ["😀","😃","😄","😁","😆","😅","😂","🤣","🥲","☺️","😊","😇","🙂","🙃","😉","😌","😍","🥰","😘","😗","😙","😚","😋","😛","😝","😜","🤪","🤨","🧐","🤓","😎","🥸","🤩","🥳","😏","😒","😞","😔","😟","😕","🙁","☹️","😣","😖","😫","😩","🥺","😢","😭","😤","😠","😡","🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","😓","🤗","🤔","🫣","🤭","🫢","🤫","🤥","😶","😐","😑","😬","🙄","😯","😦","😧","😮","😲","🥱","😴","🤤","😪","😵","🤐","🥴","🤢","🤮","🤧","😷","🤒","🤕","🤑","🤠","😈","👿","👻","💀","☠️","👽","🤖","💩","😺","😸","😹","😻","😼","😽","🙀","😿","😾"]),
        ("hand.wave", ["👋","🤚","🖐️","✋","🖖","👌","🤌","🤏","✌️","🤞","🫰","🤟","🤘","🤙","👈","👉","👆","🖕","👇","☝️","🫵","👍","👎","✊","👊","🤛","🤜","👏","🙌","🫶","👐","🤲","🤝","🙏","✍️","💅","🤳","💪","🦾","🧠","👀","👁️","👅","👄","🫦","👶","🧒","👦","👧","🧑","👱","👨","🧔","👩","🧓","👴","👵","🙋","🙆","🙅","🤷","🤦","💁","🙇","🧏","💃","🕺","🚶","🏃","👫","👭","👬","💏","💑","👪"]),
        ("heart", ["❤️","🧡","💛","💚","💙","🩵","💜","🤎","🖤","🩶","🤍","💔","❤️‍🔥","❤️‍🩹","❣️","💕","💞","💓","💗","💖","💘","💝","💟","💌","💋","💯","💢","💥","💫","💦","💨","🕳️","💬","🗨️","💭","💤"]),
        ("pawprint", ["🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐻‍❄️","🐨","🐯","🦁","🐮","🐷","🐸","🐵","🙈","🙉","🙊","🐔","🐧","🐦","🐤","🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞","🐢","🐍","🦖","🐙","🦑","🦀","🐠","🐟","🐬","🐳","🦈","🐊","🐘","🦒","🐪","🐄","🐎","🐑","🐐","🦌","🐕","🐈","🐓","🦃","🕊️","🐇","🌵","🎄","🌲","🌳","🌴","🌱","🌿","🍀","🍁","🍂","🍃","🌷","🌹","🥀","🌺","🌸","🌼","🌻","🌞","🌝","🌚","🌙","⭐️","🌟","✨","⚡️","🔥","🌈","☀️","⛅️","☁️","🌧️","⛈️","❄️","☃️","💧","🌊"]),
        ("fork.knife", ["🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑","🥦","🥬","🥒","🌶️","🌽","🥕","🧄","🧅","🥔","🥐","🥯","🍞","🥖","🧀","🥚","🍳","🥞","🧇","🥓","🥩","🍗","🍖","🌭","🍔","🍟","🍕","🥪","🌮","🌯","🥗","🍝","🍜","🍲","🍛","🍣","🍱","🥟","🍤","🍙","🍚","🍦","🍰","🎂","🧁","🍫","🍬","🍭","🍩","🍪","🍿","☕️","🍵","🧃","🥤","🧋","🍺","🍻","🥂","🍷","🥃","🍸","🍹","🍾"]),
        ("soccerball", ["⚽️","🏀","🏈","⚾️","🎾","🏐","🏉","🎱","🏓","🏸","🥊","🥋","⛳️","⛸️","🎿","🏂","🏋️","🤸","🚴","🏊","🧘","🏆","🥇","🥈","🥉","🏅","🎖️","🎫","🎟️","🎪","🎭","🎨","🎬","🎤","🎧","🎼","🎹","🥁","🎷","🎺","🎸","🎻","🎲","🎯","🎳","🎮","🧩","🚗","🚕","🚌","🏎️","🚓","🚑","🚒","🚲","🛵","🏍️","🚂","✈️","🚀","🛸","🚁","⛵️","🚢","🏠","🏡","🏢","🏥","🏫","🏰","🗼","🗽","⛰️","🏔️","🏖️","🏝️","🌍","🗺️"]),
        ("lightbulb", ["⌚️","📱","💻","⌨️","🖥️","🖨️","🖱️","📷","📸","🎥","📺","📻","⏰","⏳","🔋","🔌","💡","🔦","🕯️","💸","💵","💶","💳","💎","🔧","🔨","🛠️","🔑","🗝️","🚪","🛋️","🛏️","🧸","🎁","🎈","🎉","🎊","✉️","📦","📅","📌","📎","✂️","🖊️","✏️","📝","📚","📖","🔒","🔓","❤️‍🩹","💊","🩺","🧴","🧼","🛒"]),
        ("number", ["✅","☑️","✔️","❌","❎","➕","➖","➗","✖️","♾️","‼️","⁉️","❓","❔","❕","❗️","〰️","©️","®️","™️","🔴","🟠","🟡","🟢","🔵","🟣","⚫️","⚪️","🟤","🔶","🔷","🔺","🔻","🔸","🔹","▶️","⏸️","⏹️","⏺️","⏭️","⏮️","🔁","🔂","🔄","🆗","🆕","🆒","🆓","🆘","🚫","⛔️","⚠️","🚸","♻️","🔞","📵","🔇","🔔","🔕","🎵","🎶","💲","🏳️","🏴","🏁","🚩","🏳️‍🌈","🇫🇷","🇧🇪","🇨🇭","🇨🇦","🇺🇸","🇬🇧","🇪🇸","🇮🇹","🇩🇪","🇵🇹","🇲🇦","🇩🇿","🇹🇳","🇸🇳","🇨🇮","🇯🇵"]),
    ]

    private static let recentKey = "foldboard.emoji.recent"

    static var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(32)), forKey: recentKey) }
    }

    static func used(_ e: String) {
        var r = recent.filter { $0 != e }
        r.insert(e, at: 0)
        recent = r
    }
}

/// La grille d'emojis : défile de côté, rangées de haut en bas, comme chez Apple.
final class EmojiBoard: UIView, UIScrollViewDelegate {
    var onEmoji: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onDelete: (() -> Void)?

    private let scroll = UIScrollView()
    private let bar = UIView()
    private let abc = UIButton(type: .system)
    private let del = UIButton(type: .system)
    private var tabs: [UIButton] = []
    private var sections: [(start: CGFloat, list: [String])] = []
    private var labels: [UILabel] = []
    private var cellW: CGFloat = 40
    private var cellH: CGFloat = 40
    private var rows = 4
    private var favorites: [String] = []
    private var builtFor: CGSize = .zero
    private var deleteTimer: Timer?

    var textColor: UIColor = .label { didSet { restyle() } }
    var keyColor: UIColor = .systemGray4 { didSet { restyle() } }
    var accent: UIColor = .systemBlue { didSet { restyle() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = self
        scroll.delaysContentTouches = false
        addSubview(scroll)
        addSubview(bar)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        scroll.addGestureRecognizer(tap)

        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        abc.layer.cornerRadius = 8
        abc.addAction(UIAction { [weak self] _ in self?.onABC?() }, for: .touchUpInside)
        bar.addSubview(abc)

        del.setImage(UIImage(systemName: "delete.left"), for: .normal)
        del.layer.cornerRadius = 8
        del.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        del.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        bar.addSubview(del)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Les favoris de l'utilisateur viennent en tête, avec les récents.
    func configure(favorites: [String]) {
        if favorites != self.favorites {
            self.favorites = favorites
            builtFor = .zero
            setNeedsLayout()
        }
    }

    func reloadRecent() {
        builtFor = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != builtFor, bounds.width > 40 else { return }
        builtFor = bounds.size
        let barH: CGFloat = 40
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        scroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barH - 4)
        rows = max(3, min(5, Int(scroll.bounds.height / 40)))
        cellH = scroll.bounds.height / CGFloat(rows)
        cellW = max(36, min(48, bounds.width / 8))

        labels.forEach { $0.removeFromSuperview() }
        labels = []
        sections = []
        var lists: [[String]] = []
        var first = KBEmoji.recent
        for f in favorites where !first.contains(f) { first.append(f) }
        lists.append(Array(first.prefix(rows * 6)))
        lists += KBEmoji.categories.map { $0.list }

        var x: CGFloat = 0
        let font = UIFont.systemFont(ofSize: min(32, cellH * 0.72))
        for list in lists {
            sections.append((x, list))
            for (i, e) in list.enumerated() {
                let col = i / rows, row = i % rows
                let l = UILabel(frame: CGRect(x: x + CGFloat(col) * cellW, y: CGFloat(row) * cellH, width: cellW, height: cellH))
                l.text = e
                l.font = font
                l.textAlignment = .center
                scroll.addSubview(l)
                labels.append(l)
            }
            let cols = (list.count + rows - 1) / rows
            x += CGFloat(max(cols, 1)) * cellW + 10
        }
        scroll.contentSize = CGSize(width: x, height: scroll.bounds.height)

        // La barre : ABC, une icône par catégorie, effacer.
        tabs.forEach { $0.removeFromSuperview() }
        tabs = []
        let side: CGFloat = 52
        abc.frame = CGRect(x: 4, y: 4, width: side, height: barH - 8)
        del.frame = CGRect(x: bounds.width - side - 4, y: 4, width: side, height: barH - 8)
        let symbols = ["clock"] + KBEmoji.categories.map { $0.symbol }
        let avail = bounds.width - 2 * side - 16
        let tw = avail / CGFloat(symbols.count)
        for (i, s) in symbols.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
            b.frame = CGRect(x: side + 8 + CGFloat(i) * tw, y: 4, width: tw, height: barH - 8)
            b.tag = i
            b.addAction(UIAction { [weak self] _ in self?.jump(to: i) }, for: .touchUpInside)
            bar.addSubview(b)
            tabs.append(b)
        }
        restyle()
        highlightTab()
    }

    private func restyle() {
        abc.setTitleColor(textColor, for: .normal)
        abc.backgroundColor = keyColor
        del.tintColor = textColor
        del.backgroundColor = keyColor
        highlightTab()
    }

    private func jump(to i: Int) {
        guard i < sections.count else { return }
        let x = min(sections[i].start, max(0, scroll.contentSize.width - scroll.bounds.width))
        scroll.setContentOffset(CGPoint(x: x, y: 0), animated: false)
        highlightTab()
    }

    private func highlightTab() {
        let x = scroll.contentOffset.x + 1
        var current = 0
        for (i, s) in sections.enumerated() where s.start <= x { current = i }
        for (i, b) in tabs.enumerated() { b.tintColor = i == current ? accent : textColor.withAlphaComponent(0.45) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { highlightTab() }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: scroll)
        guard let l = labels.first(where: { $0.frame.contains(p) }), let e = l.text else { return }
        UIView.animate(withDuration: 0.08, animations: { l.transform = CGAffineTransform(scaleX: 1.3, y: 1.3) }) { _ in
            UIView.animate(withDuration: 0.1) { l.transform = .identity }
        }
        KBEmoji.used(e)
        onEmoji?(e)
    }

    @objc private func deleteDown() {
        onDelete?()
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in self?.onDelete?() }
        }
    }

    @objc private func deleteUp() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }
}
