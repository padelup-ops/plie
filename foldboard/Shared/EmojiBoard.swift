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

    /// Les noms des emojis (en anglais, donnés par iOS), calculés une fois.
    private static let names: [(emoji: String, words: [String])] = {
        var seen = Set<String>(), out: [(String, [String])] = []
        for e in categories.flatMap({ $0.list }) where seen.insert(e).inserted {
            let base = e.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0x200D }.map { String($0) }.joined()
            let n = (base.applyingTransform(.toUnicodeName, reverse: false) ?? "")
                .replacingOccurrences(of: "\\N{", with: " ").replacingOccurrences(of: "}", with: " ").lowercased()
            out.append((e, n.split(whereSeparator: { !$0.isLetter }).map(String.init)))
        }
        return out
    }()

    /// Des mots d'autres langues vers les noms anglais (les plus cherchés).
    private static let synonyms: [String: [String]] = [
        "coeur": ["heart"], "cœur": ["heart"], "amour": ["heart", "kiss", "love"], "rire": ["joy", "laughing", "rolling", "grinning"], "mdr": ["joy", "rolling"],
        "lol": ["joy", "rolling"], "pleur": ["crying", "tear"], "triste": ["sad", "pensive", "crying", "frowning", "disappointed"], "larme": ["tear", "crying"],
        "feu": ["fire"], "pouce": ["thumbs"], "merci": ["folded", "pray"], "priere": ["folded"], "prière": ["folded"], "fete": ["party", "confetti", "partying"],
        "fête": ["party", "confetti", "partying"], "chat": ["cat"], "chien": ["dog"], "soleil": ["sun"], "lune": ["moon"], "etoile": ["star"], "étoile": ["star"],
        "fleur": ["flower", "blossom", "rose", "tulip"], "bisou": ["kiss", "kissing"], "yeux": ["eyes"], "oeil": ["eye"], "main": ["hand"], "cadeau": ["gift", "present"],
        "gateau": ["cake"], "gâteau": ["cake"], "anniversaire": ["birthday"], "biere": ["beer"], "bière": ["beer"], "vin": ["wine"], "cafe": ["coffee", "hot"], "café": ["coffee", "hot"],
        "voiture": ["car", "automobile"], "avion": ["airplane"], "maison": ["house"], "argent": ["money", "dollar", "euro"], "content": ["smiling", "grinning", "happy"],
        "heureux": ["smiling", "grinning", "happy"], "sourire": ["smiling", "grinning"], "colere": ["angry", "pouting", "rage"], "colère": ["angry", "pouting", "rage"],
        "peur": ["fearful", "screaming", "anxious"], "dodo": ["sleeping", "zzz"], "malade": ["mask", "thermometer", "nauseated", "sneezing"], "bravo": ["clapping"],
        "applaudir": ["clapping"], "clin": ["winking"], "lunettes": ["sunglasses", "glasses"], "diable": ["devil", "imp"], "fantome": ["ghost"], "fantôme": ["ghost"],
        "caca": ["poo"], "singe": ["monkey"], "oiseau": ["bird"], "poisson": ["fish"], "arbre": ["tree"], "neige": ["snow", "snowflake"], "pluie": ["rain", "umbrella"],
        "drapeau": ["flag"], "valider": ["check"], "croix": ["cross"], "attention": ["warning"], "musique": ["music", "note"], "foot": ["soccer"], "ballon": ["ball"],
        "telephone": ["mobile", "phone"], "téléphone": ["mobile", "phone"], "ordinateur": ["laptop", "computer"], "livre": ["book"], "cle": ["key"], "clé": ["key"],
        "cochon": ["pig"], "vache": ["cow"], "lapin": ["rabbit"], "ours": ["bear"], "renard": ["fox"], "licorne": ["unicorn"], "pomme": ["apple"], "banane": ["banana"],
        "fraise": ["strawberry"], "pain": ["bread"], "fromage": ["cheese"], "glace": ["ice", "cream"], "bonbon": ["candy"], "chocolat": ["chocolate"], "ok": ["ok"],
        "bébé": ["baby"], "bebe": ["baby"], "femme": ["woman"], "homme": ["man"], "fille": ["girl"], "garçon": ["boy"], "garcon": ["boy"], "muscle": ["biceps", "flexed"],
        "fort": ["biceps", "flexed"], "cent": ["hundred"], "eclair": ["lightning", "high voltage"], "éclair": ["lightning", "high voltage"], "nuage": ["cloud"],
        "arc": ["rainbow"], "mer": ["wave", "water"], "plage": ["beach"], "montagne": ["mountain"], "velo": ["bicycle"], "vélo": ["bicycle"], "train": ["train", "locomotive"],
        "fusee": ["rocket"], "fusée": ["rocket"], "bougie": ["candle"], "ampoule": ["bulb"], "horloge": ["clock", "alarm"], "sablier": ["hourglass"],
        "cœurbrisé": ["broken"], "brisé": ["broken"], "nerd": ["nerd"], "cool": ["sunglasses", "cool"], "pensif": ["thinking"], "reflechir": ["thinking"], "réfléchir": ["thinking"],
        "chut": ["shushing"], "zut": ["grimacing"], "gene": ["grimacing", "flushed"], "gêne": ["grimacing", "flushed"], "chaud": ["hot", "fire"], "froid": ["cold", "freezing"],
        "fatigue": ["tired", "weary", "yawning"], "fatigué": ["tired", "weary", "yawning"], "ange": ["angel", "halo"], "robot": ["robot"], "extraterrestre": ["alien"],
        "danse": ["dancing", "dancer"], "course": ["running"], "sport": ["ball", "medal"], "trophee": ["trophy"], "trophée": ["trophy"], "medaille": ["medal"], "médaille": ["medal"],
        "corazon": ["heart"], "risa": ["joy", "laughing"], "herz": ["heart"], "lachen": ["joy", "laughing"], "cuore": ["heart"], "coração": ["heart"],
    ]

    /// Les emojis dont le nom contient tous les mots cherchés (début de mot), les plus utilisés d'abord.
    static func search(_ query: String) -> [String] {
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return Array(recent.prefix(12)) }
        let alts: [[String]] = terms.map { t in
            var a = [t]
            for (k, v) in synonyms where k.hasPrefix(t) && (t.count >= 3 || k == t) { a += v }
            return a
        }
        let rec = recent
        let found = names.filter { item in
            alts.allSatisfy { alt in alt.contains { a in item.words.contains { $0.hasPrefix(a) } } }
        }.map { $0.emoji }
        return found.sorted { (rec.firstIndex(of: $0) ?? 99) < (rec.firstIndex(of: $1) ?? 99) }
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
    /// Chercher un emoji par son nom (les lettres reviennent, les résultats s'affichent dans la barre).
    var onSearch: (() -> Void)?
    private let searchBtn = UIButton(type: .system)
    /// Un élément du presse-papier à coller.
    var onClip: ((String) -> Void)? { didSet { clips.onPaste = onClip } }
    /// Le presse-papier à la place des emojis (bouton 📋 de la barre du bas).
    private(set) var clipMode = false
    let clips = ClipboardList()
    private let clipBtn = UIButton(type: .system)

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

        clips.isHidden = true
        addSubview(clips)
        clipBtn.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        clipBtn.accessibilityLabel = L("Clipboard")
        clipBtn.addAction(UIAction { [weak self] _ in self?.setClipMode(!(self?.clipMode ?? false)) }, for: .touchUpInside)
        bar.addSubview(clipBtn)
        searchBtn.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        searchBtn.accessibilityLabel = L("Search emoji")
        searchBtn.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        bar.addSubview(searchBtn)
    }

    /// Ouvre ou ferme le presse-papier (à la place de la grille d'emojis).
    func setClipMode(_ on: Bool) {
        clipMode = on
        clips.isHidden = !on
        scroll.isHidden = on
        if on { clips.reload() }
        highlightTab()
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
        clips.frame = scroll.frame
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
        // Le presse-papier juste après ABC, puis les catégories.
        let clipW: CGFloat = 40
        clipBtn.frame = CGRect(x: side + 6, y: 4, width: clipW, height: barH - 8)
        searchBtn.frame = CGRect(x: side + 6 + clipW, y: 4, width: clipW, height: barH - 8)
        let avail = bounds.width - 2 * side - 16 - 2 * clipW
        let tw = avail / CGFloat(symbols.count)
        for (i, s) in symbols.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
            b.frame = CGRect(x: side + 8 + 2 * clipW + CGFloat(i) * tw, y: 4, width: tw, height: barH - 8)
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
        clips.textColor = textColor
        clips.keyColor = keyColor
        clips.accent = accent
        highlightTab()
    }

    private func jump(to i: Int) {
        if clipMode { setClipMode(false) }
        guard i < sections.count else { return }
        let x = min(sections[i].start, max(0, scroll.contentSize.width - scroll.bounds.width))
        scroll.setContentOffset(CGPoint(x: x, y: 0), animated: false)
        highlightTab()
    }

    private func highlightTab() {
        let x = scroll.contentOffset.x + 1
        var current = 0
        for (i, s) in sections.enumerated() where s.start <= x { current = i }
        for (i, b) in tabs.enumerated() { b.tintColor = !clipMode && i == current ? accent : textColor.withAlphaComponent(0.45) }
        clipBtn.tintColor = clipMode ? accent : textColor.withAlphaComponent(0.45)
        searchBtn.tintColor = textColor.withAlphaComponent(0.45)
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
