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
    /// Ce que fait « retour » dans ce champ (rechercher, envoyer, aller…).
    var kbReturnType: UIReturnKeyType { get }
}

extension KBInput {
    var kbReturnType: UIReturnKeyType { .default }
}

/// Images système déjà dessinées : un pli ne recharge pas une nouvelle loupe, un nouveau globe, etc.
enum KBSymbol {
    private static var cache: [String: UIImage] = [:]
    static func image(_ name: String) -> UIImage? {
        if let i = cache[name] { return i }
        guard let i = UIImage(systemName: name) else { return nil }
        cache[name] = i
        return i
    }
    /// Mémoire serrée : les images se redessinent à la demande.
    static func clear() { cache.removeAll() }
}

/// Vues encore en vie (touches, clavier, boutons du côté). Le journal de la main l'écrit pour vérifier
/// qu'un pli ne laisse pas de nouvelles vues derrière lui.
enum KBViews {
    static var keys = 0
    static var canvases = 0
    static var panels = 0
    static var live: Int { keys + canvases + panels }
}

/// Une touche dessinée (elle ne reçoit pas les touchers : c'est le clavier qui les gère tous).
/// Créée une fois, puis reconfigurée : un changement de taille ne jette pas la touche.
final class KeyView: UIView {
    let label = UILabel()
    let icon = UIImageView()
    var spec: KeySpec
    var special: Bool
    /// Coins carrés (réglage).
    var square = false

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
        KBViews.keys += 1
    }

    deinit { KBViews.keys -= 1 }

    /// Même vue, autre lettre ou autre place. On jette le glyphe précédent (image et calque).
    func reconfigure(spec: KeySpec, special: Bool) {
        self.spec = spec
        self.special = special
        park()
        isHidden = false
        alpha = 1
    }

    /// Le pavé tactile efface les lettres : elles reviennent toujours, même sur une touche rangée entre-temps.
    func showGlyphs() {
        label.alpha = 1
        icon.alpha = 1
    }

    /// Touche en trop pour cette disposition : on garde la vue, plus son image.
    func park() {
        isHidden = true
        label.text = nil
        label.attributedText = nil
        icon.image = nil
        layer.contents = nil
        layer.removeAllAnimations()
        transform = .identity
        backgroundColor = nil
        alpha = 1
        showGlyphs()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Jamais animé : quand iOS redimensionne le clavier dans une animation (pli, rotation, mode portable), la
        // lettre et les coins de chaque touche glissaient à part, et les rangées semblaient se défaire.
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.frame = bounds.insetBy(dx: 2, dy: 0)
            let s = min(bounds.width, bounds.height) * 0.46
            icon.frame = CGRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
            let r = square ? min(4, bounds.height * 0.08) : min(13, bounds.height * 0.26)
            layer.cornerRadius = r
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: r).cgPath
            CATransaction.commit()
        }
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
    /// Les trois dispositions (suit la main, toute la largeur, coupé en deux). Créé une fois : on ne fait que
    /// le montrer ou le cacher, jamais un nouveau contrôle à chaque apparition.
    private let layoutSwitch: UISegmentedControl = {
        let images = ["hand.raised.fingers.spread", "keyboard", "rectangle.split.2x1"].map {
            (UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) ?? UIImage())
                .withRenderingMode(.alwaysTemplate)
        }
        let s = UISegmentedControl(items: images)
        s.selectedSegmentIndex = 0
        s.apportionsSegmentWidthsByContent = false
        let names = ["Follows your hand", "Full width", "Split keyboard"]
        for (i, n) in names.enumerated() { s.imageForSegment(at: i)?.accessibilityLabel = L(n) }
        return s
    }()
    private let hideButton = UIButton(type: .system)
    /// Petit clavier : le globe et les emojis sont ici, pour laisser la place à l'espace.
    private let globeButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    /// Le presse-papier, toujours en vue dans la barre du haut.
    private let clipButton = UIButton(type: .system)
    /// La dictée (voir KBDictation) : le micro au-dessus des touches, et ce qu'on entend pendant qu'on parle.
    private let micButton = UIButton(type: .system)
    /// « Corriger » : la phrase avant le curseur, corrigée sur l'iPhone (Apple Intelligence).
    private let fixButton = UIButton(type: .system)
    /// Ce que reçoit le bouton « Coller » du système (UIPasteControl) : le texte est gardé et écrit.
    private lazy var pasteTarget: KBPasteTarget = {
        let t = KBPasteTarget()
        t.isHidden = true
        t.onText = { [weak self] text in
            guard let self else { return }
            KBClipboard.shared.keep(text)
            KBClipboard.shared.dismissFresh()
            self.pasteClip(text)
            self.rebuildChips()
        }
        addSubview(t)
        return t
    }()
    /// 🌐 Traduire le texte avant le curseur (appui long : choisir la langue).
    private let translateButton = UIButton(type: .system)
    /// « ⋯ » : pendant qu'on écrit, les boutons de la barre sont rangés derrière lui (les suggestions ont la place).
    private let moreButton = UIButton(type: .system)
    /// Les boutons montrés à la demande (« ⋯ »), jusqu'à la prochaine touche.
    private var barOpened = false
    private var fixing = false
    private let dictLabel = UILabel()
    private enum DictState { case idle, connecting, listening, finishing }
    private var dictState = DictState.idle { didSet { if micKey, oldValue != dictState { updateLabels() } } }
    private var dictSeq = 0
    private let adjustButton = UIButton(type: .system)
    private let chips = UIScrollView()
    private let chipStack = UIStackView()
    private let toast = UILabel()
    /// Dans la place libre à côté du clavier à une main : une flèche discrète (« touche ici pour mettre le clavier
    /// de ce côté »), avec le texte les premières fois.
    private let sideHint = UILabel()
    private let panel = UIView()
    private let bubble = UILabel()
    private let accentView = UIView()
    private var accentLabels: [UILabel] = []

    /// Mode automatique : la main qui tient le téléphone (inclinaison, puis GripSense pendant la frappe).
    private let grip = GripDetector()
    private let knock = KBKnock()
    /// Correction et suggestions de mots.
    // Les correcteurs sont partagés par tous les claviers du processus (iOS en crée un à chaque apparition) :
    // listes, lexique et caches ne sont chargés qu'une fois.
    private static let mainSuggest = KBSuggest()
    private static let backSuggest = KBSuggest()
    private static let backQueue = DispatchQueue(label: "foldboard.suggest", qos: .userInitiated)
    private let suggest = KeyboardCanvas.mainSuggest
    /// Les suggestions se calculent à part (le correcteur d'iOS peut prendre plusieurs dizaines de ms) :
    /// le fil principal reste libre pour les touchers, la frappe ne rame plus.
    private let bgSuggest = KeyboardCanvas.backSuggest
    private let suggestQueue = KeyboardCanvas.backQueue
    private var suggestGen = 0
    /// La correction déjà calculée pour le mot en cours (évite de la recalculer à l'espace).
    private var cachedFix: (word: String, fix: String?)?
    private var suggestionItems: [String] = []
    /// Le mot pour lequel la barre a été calculée.
    private var suggestionsWord = ""
    private var suggestionBest: Int?
    private var lastCorrection: (original: String, corrected: String, sep: String)?
    /// Où le doigt s'est posé pour chaque lettre tapée (les dernières) : la correction s'en sert, comme chez Apple.
    private var wordTouches: [(ch: Character, p: CGPoint)] = []

    /// Où tu tapes vraiment (voir KBTapMap), et combien d'appuis pas encore enregistrés.
    private var tapMap = KBTapMap()
    private var tapDirty = 0

    /// Un mot gardé tel quel (pas de correction) : chaque appui dit où ton pouce se pose sur la touche visée.
    private func learnTaps(_ word: String) {
        guard eff.tapLearn, recording == nil, page == .letters, word.count >= 2, suggest.isWord(word) else { return }
        let w = Array(word.lowercased())
        guard wordTouches.count >= w.count else { return }
        let tail = Array(wordTouches.suffix(w.count))
        for (i, t) in tail.enumerated() where t.ch != w[i] { _ = i; return }
        let two = !layoutMode.isOneHand
        for t in tail {
            guard let c = cells.first(where: { if case .char(let s) = $0.view.spec.kind { return s.lowercased().first == t.ch && s.count == 1 }; return false }),
                  c.frame.width > 0, c.frame.height > 0 else { continue }
            tapMap.add(key: String(t.ch), dx: Double((t.p.x - c.frame.midX) / c.frame.width),
                       dy: Double((t.p.y - c.frame.midY) / c.frame.height), twoHands: two)
            tapDirty += 1
        }
        if tapDirty >= 25 { saveTaps() }
    }

    private func learnSpace(at p: CGPoint, frame f: CGRect) {
        guard eff.tapLearn, recording == nil, f.width > 0, f.height > 0 else { return }
        tapMap.add(key: " ", dx: Double((p.x - f.midX) / f.width), dy: Double((p.y - f.midY) / f.height), twoHands: !layoutMode.isOneHand)
        tapDirty += 1
    }

    // MARK: Dictée
    //
    // Les touches laissent la place au panneau de dictée (KBVoicePanel) : la voix, le texte qui s'écrit, annuler ou
    // valider. L'app Foldboard tient le micro (iOS ne le donne pas aux claviers) : si elle n'est pas prête, le panneau
    // propose de l'ouvrir une fois, et la dictée démarre toute seule au retour.

    private let voice = KBVoicePanel()
    private var dictCancelled = false
    /// La dictée dans le clavier (WebKit tient le micro) : pas besoin d'ouvrir l'app.
    private var mic: KeyboardMic?
    private var micMode = false
    /// L'app a été ouverte pour la dictée : au retour du clavier, on écoute tout de suite.
    private static let pendingKey = "foldboard.dictation.pending"

    private func micTapped() {
        KBFeedback.shared.tap(sound: .off, haptics: max(0.3, eff.haptics))
        switch dictState {
        case .listening:
            stopDictation()
        case .idle:
            startDictation()
        default:
            break
        }
    }

    private func showVoice(_ m: KBVoicePanel.Mode, text: String? = nil) {
        voice.set(m, text: text)
        voice.setTranslate(on: eff.dictTranslate && eff.translateKey, pair: eff.translatePair, shown: eff.translateKey)
        if voice.isHidden {
            voice.isHidden = false
            layoutVoice()
        }
        layoutTopBar()
    }

    private func hideVoice() {
        guard !voice.isHidden else { return }
        voice.isHidden = true
        layoutTopBar()
    }

    private func layoutVoice() {
        let top = barTop + Self.topBarHeight
        voice.frame = CGRect(x: 6, y: top + 2, width: max(0, bounds.width - 12), height: max(0, bounds.height - top - 8))
        voice.style(background: theme.background, key: theme.special, text: theme.text, accent: theme.accent)
        bringSubviewToFront(voice)
    }

    /// Demande à l'app si elle est prête (micro disponible) ; sinon, le panneau propose de l'ouvrir.
    private func startDictation() {
        dictCancelled = false
        dictState = .connecting
        showVoice(.connecting)
        KBDictation.observe(KBDictation.pong) { [weak self] in
            guard let self, self.dictState == .connecting else { return }
            self.dictSeq = KBVault.loadDictation()?.seq ?? 0
            self.dictState = .listening
            self.showVoice(.listening, text: "")
            KBFeedback.shared.tap(sound: .off, haptics: max(0.3, self.eff.haptics))
            KBDictation.post(KBDictation.start)
        }
        KBDictation.observe(KBDictation.update) { [weak self] in self?.dictationUpdate() }
        // L'app n'a pas pu ouvrir le micro en arrière-plan : la dictée se fait dans le clavier.
        KBDictation.observe(KBDictation.needApp) { [weak self] in
            guard let self, !self.micMode, self.dictState == .listening || self.dictState == .connecting else { return }
            self.dictateInKeyboard()
        }
        KBDictation.post(KBDictation.ping)
        // L'app ne répond pas (fermée) : la dictée se fait dans le clavier, sans l'ouvrir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.dictState == .connecting else { return }
            self.dictateInKeyboard()
        }
    }

    /// La dictée dans le clavier. Si le micro ou la reconnaissance n'ont jamais été permis (ou sans l'accès
    /// complet), le panneau propose d'ouvrir l'app une fois.
    private func dictateInKeyboard() {
        guard KeyboardMic.canUse(fullAccess: input?.kbFullAccess ?? false) else {
            dictState = .idle
            showVoice(.needsApp)
            return
        }
        micRelease?.cancel()
        micRelease = nil
        // La page WebKit de la dictée coûte quelques Mo : on fait de la place avant, pas après.
        emojiBoard.releaseMemory()
        let m = mic ?? KeyboardMic()
        mic = m
        m.attach(to: self)
        micMode = true
        dictState = .listening
        showVoice(.listening, text: "")
        KBFeedback.shared.tap(sound: .off, haptics: max(0.3, eff.haptics))
        m.onText = { [weak self] t, final in
            guard let self, self.micMode else { return }
            if final {
                self.micMode = false
                if !self.dictCancelled { self.insertDictation(t) }
                self.dictState = .idle
                self.hideVoice()
                self.releaseMicSoon()
            } else if !t.isEmpty {
                self.voice.set(self.dictState == .finishing ? .finishing : .listening, text: t)
            }
        }
        m.onLevel = { [weak self] l in self?.voice.push(level: CGFloat(l)) }
        m.onFail = { [weak self] _ in
            guard let self, self.micMode else { return }
            self.micMode = false
            self.dictState = .idle
            self.showVoice(.needsApp)
            self.releaseMicIfIdle()
        }
        m.start(localeID: KBDictation.localeID())
    }

    private func openAppForDictation() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.pendingKey)
        openContainingApp(KBDictation.url)
    }

    /// Au retour de l'app ouverte pour la dictée : on écoute sans qu'il faille retoucher le micro.
    private func resumePendingDictation() {
        let t = UserDefaults.standard.double(forKey: Self.pendingKey)
        guard t > 0 else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        guard eff.dictationKey, Date().timeIntervalSince1970 - t < 180 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.visible, self.dictState == .idle else { return }
            self.startDictation()
        }
    }

    /// Valider : on arrête d'écouter et on écrit le texte (le dernier résultat arrive tout de suite).
    private func stopDictation() {
        guard dictState == .listening else {
            if dictState == .idle { hideVoice() }
            return
        }
        if micMode {
            dictState = .finishing
            showVoice(.finishing)
            mic?.stop()
            return
        }
        dictState = .finishing
        showVoice(.finishing)
        KBDictation.post(KBDictation.stop)
        // Si le texte final n'arrive pas, on écrit ce qui a été entendu (Parakeet peut prendre quelques secondes).
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, self.dictState == .finishing else { return }
            if let s = KBVault.loadDictation(), s.seq > self.dictSeq, !self.dictCancelled { self.insertDictation(s.text) }
            self.dictState = .idle
            self.hideVoice()
        }
    }

    /// Annuler : rien n'est écrit.
    private func cancelDictation() {
        dictCancelled = true
        if micMode {
            micMode = false
            mic?.cancel()
        }
        if dictState == .listening || dictState == .finishing { KBDictation.post(KBDictation.stop) }
        dictState = .idle
        hideVoice()
        releaseMicSoon()
    }

    private func dictationUpdate() {
        guard dictState == .listening || dictState == .finishing, let s = KBVault.loadDictation(), s.seq > dictSeq else { return }
        if s.final {
            dictSeq = s.seq
            if !dictCancelled { insertDictation(s.text) }
            dictState = .idle
            hideVoice()
        } else {
            if !s.text.isEmpty { voice.set(dictState == .finishing ? .finishing : .listening, text: s.text) }
            voice.push(level: CGFloat(s.level ?? 0))
        }
    }

    // MARK: Traduire

    /// Le paragraphe avant le curseur, traduit dans l'autre langue de la paire (ou celle choisie par appui long).
    private func translateTapped(to chosen: String?) {
        guard !fixing, let before = input?.kbTextBefore(), !before.isEmpty else {
            flash(L("Type something, then tap 🌐 to translate it"))
            return
        }
        let para = String(before.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")
        let text = String(para.suffix(600))
        guard text.trimmingCharacters(in: .whitespaces).count > 1 else { return }
        let pair = eff.translatePair
        let src = KBTranslate.detect(text) ?? pair[0]
        let dst = chosen ?? (KBTranslate.target(for: text, pair: pair)?.to ?? pair[1])
        fixing = true
        layoutTopBar()
        KBFeedback.shared.tap(sound: .off, haptics: max(0.3, eff.haptics))
        Task { @MainActor [weak self] in
            let r = await KBTranslate.translate(text, from: src, to: dst)
            guard let self else { return }
            self.fixing = false
            defer { self.layoutTopBar() }
            switch r {
            case .success(let out):
                guard out != text, (self.input?.kbTextBefore() ?? "").hasSuffix(text) else { return }
                let trailing = text.hasSuffix(" ") && !out.hasSuffix(" ") ? " " : ""
                for _ in 0..<text.count { self.input?.kbDelete() }
                self.input?.kbInsert(out + trailing)
                self.lastCorrection = nil
                self.refreshSuggestionsSoon()
            case .failure(let f):
                self.translateFailed(f)
            }
        }
    }

    private func translateFailed(_ f: KBTranslate.Failure) {
        switch f {
        case .notInstalled(let a, let b):
            flash(String(format: L("Download %@ and %@ in Foldboard › Translate, then try again"), KBTranslate.name(a), KBTranslate.name(b)), hold: 3.5)
        case .unavailable:
            flash(L("Translation isn't available on this iPhone"), hold: 3)
        }
    }

    /// Le menu de l'appui long sur 🌐 : traduire vers une autre langue.
    private func translateMenu() -> UIMenu {
        let items = KBTranslate.languages.map { code in
            UIAction(title: KBTranslate.name(code)) { [weak self] _ in self?.translateTapped(to: code) }
        }
        return UIMenu(title: L("Translate to"), children: items)
    }

    /// Le bouton du panneau de dictée : traduire ce qu'on dit, ou non.
    private func toggleDictTranslate() {
        settings.dictTranslate.toggle()
        eff.dictTranslate = settings.dictTranslate
        persist()
        voice.setTranslate(on: eff.dictTranslate && eff.translateKey, pair: eff.translatePair, shown: eff.translateKey)
        KBFeedback.shared.tap(sound: .off, haptics: max(0.3, eff.haptics))
    }

    /// Corriger le paragraphe avant le curseur (jusqu'au dernier retour à la ligne, 600 caractères au plus).
    private func fixTapped() {
        guard !fixing, let before = input?.kbTextBefore(), !before.isEmpty else { return }
        let para = String(before.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")
        let text = String(para.suffix(600))
        guard text.trimmingCharacters(in: .whitespaces).count > 1 else { return }
        fixing = true
        layoutTopBar()
        KBFeedback.shared.tap(sound: .off, haptics: max(0.3, eff.haptics))
        Task { @MainActor [weak self] in
            let fixed = await KBWritingFix.fix(text)
            guard let self else { return }
            self.fixing = false
            defer { self.layoutTopBar() }
            // Le texte n'a pas bougé entre-temps : on remplace (en gardant l'espace de fin).
            guard let fixed, fixed != text, (self.input?.kbTextBefore() ?? "").hasSuffix(text) else { return }
            let trailing = text.hasSuffix(" ") && !fixed.hasSuffix(" ") ? " " : ""
            for _ in 0..<text.count { self.input?.kbDelete() }
            self.input?.kbInsert(fixed + trailing)
            self.lastCorrection = nil
            self.refreshSuggestionsSoon()
            self.refreshShiftSoon()
        }
    }

    private func insertDictation(_ text: String) {
        let t0 = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t0.isEmpty else { return }
        // Dictée traduite : parlé en français, écrit en anglais (et l'inverse, ou d'autres langues).
        if eff.dictTranslate, eff.translateKey, let pair = KBTranslate.target(for: t0, pair: eff.translatePair), pair.from != pair.to {
            flash(L("Translating…"), hold: 1.2)
            Task { @MainActor [weak self] in
                let r = await KBTranslate.translate(t0, from: pair.from, to: pair.to)
                guard let self else { return }
                switch r {
                case .success(let out): self.writeDictation(out, lang: pair.to)
                case .failure(let f): self.translateFailed(f); self.writeDictation(t0)
                }
            }
            return
        }
        writeDictation(t0)
    }

    /// La langue dictée (celle de la disposition), en deux lettres.
    private var dictationLang: String {
        switch eff.layout {
        case .azerty: return "fr"
        case .qwertz: return "de"
        case .spanish: return "es"
        case .swedish: return "sv"
        case .qwerty: return "en"
        }
    }

    /// La fin de ce que la dictée vient d'écrire : la lettre tapée juste après commence un nouveau mot (l'espace
    /// vient toute seule, comme après un mot écrit en glissant).
    private var dictatedTail: String?

    private func writeDictation(_ text: String, lang: String? = nil) {
        let before = input?.kbTextBefore() ?? ""
        // Comme la dictée d'Apple : « à la ligne », la majuscule selon l'endroit où l'on écrit, l'espace devant.
        let t = KBDictationText.prepare(text, before: before, lang: String((lang ?? dictationLang).prefix(2)))
        guard !t.isEmpty else { return }
        input?.kbInsert(t)
        dictatedTail = t.last.map { $0.isWhitespace } == true ? nil : String(t.suffix(16))
        glidedWord = nil
        wordTouches.removeAll()
        lastCorrection = nil
        refreshSuggestionsSoon()
        refreshShiftSoon()
    }

    /// Ouvrir l'app Foldboard depuis le clavier. `UIApplication.open` est refusé à une extension, avec ou sans
    /// accès complet. Le sélecteur `openURL:` le long de la chaîne des répondeurs, lui, est transmis à l'app hôte
    /// (Messages, Safari, Discord).
    static func deliver(_ url: URL, from start: UIResponder) -> Bool {
        let legacy = NSSelectorFromString("openURL:")
        var r: UIResponder? = start
        while let cur = r {
            if cur.responds(to: legacy) {
                cur.perform(legacy, with: url)
                return true
            }
            r = cur.next
        }
        return false
    }

    private func openContainingApp(_ url: URL) {
        if Self.deliver(url, from: self) { return }
        // Secours : l'API moderne, seulement si le sélecteur historique n'est pas là.
        var r: UIResponder? = self
        let modern = NSSelectorFromString("openURL:options:completionHandler:")
        while let cur = r {
            if let app = cur as? UIApplication, app.responds(to: modern) {
                typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let f = unsafeBitCast(app.method(for: modern), to: OpenFn.self)
                f(app, modern, url as NSURL, NSDictionary(), nil)
                return
            }
            r = cur.next
        }
    }

    private func saveTaps() {
        guard tapDirty > 0 else { return }
        tapDirty = 0
        let m = tapMap
        suggestQueue.async { KBVault.saveTaps(m) }
    }

    private func noteTouch(_ text: String, at p: CGPoint) {
        checkMemory()
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
        /// Pavé tactile : la vitesse du doigt, lissée (sans elle, l'accélération saute d'un mouvement à l'autre).
        var cursorSpeed: CGFloat = 0
        var lastAnchor: TimeInterval = 0
        var lastT: TimeInterval = 0
        /// Le curseur a atteint le bout du texte connu du clavier : on relit le texte autour avant de continuer.
        var reanchoring = false
        var accents: [String] = []
        var accentIndex = 0
        var longTimer: Timer?
        var repeatTimer: Timer?
        var done = false
        /// La lettre déjà écrite, dès que le doigt s'est posé (comme ça, rien n'attend que le doigt se relève).
        var typed: String?
        /// La majuscule au moment où le doigt s'est posé : si le doigt glisse ensuite pour tracer un mot,
        /// la lettre écrite est effacée et la majuscule doit revenir pour le mot tracé.
        var shiftAtDown: Shift = .off
        var autoShiftAtDown = false
        var swipe = false
        /// Écrire en glissant : le doigt trace le mot.
        var glide = false
        var points: [CGPoint] = []
        /// L'instant de chaque point du tracé (secondes), pour le modèle de glisser.
        var times: [TimeInterval] = []
        var t0: TimeInterval = 0
        /// La lettre effacée quand le glisser a commencé : si le doigt n'a fait que rouler sur la touche d'à côté,
        /// c'était un appui et elle est réécrite.
        var glideUndo: String?
        /// Le doigt de cet appui : s'il a quitté l'écran sans qu'iOS le dise, l'appui s'arrête quand même.
        weak var touch: UITouch?
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

    /// Le texte autour du curseur, en paragraphes (les vrais retours à la ligne), pour le pavé tactile : à gauche et
    /// à droite lettre par lettre (d'une ligne à l'autre dans un paragraphe, comme le texte s'enroule), en haut et en
    /// bas d'une ligne estimée (iOS ne dit pas aux claviers où passent les lignes à l'écran).
    /// Positions comptées depuis le curseur au moment où la carte est faite.
    struct TrackMap {
        var paras: [(start: Int, len: Int)] = []
        var para = 0
        var off = 0
        /// La colonne gardée quand on monte et descend (comme dans un éditeur de texte).
        var goalCol: Int?
        let perLine: Int
        let total: (lo: Int, hi: Int)

        init(before: String, after: String, perLine: Int) {
            self.perLine = max(12, perLine)
            let idx = before.count
            total = (-idx, after.count)
            var pos = 0
            for p in (before + after).components(separatedBy: "\n") {
                paras.append((start: pos - idx, len: p.count))
                pos += p.count + 1
            }
            if paras.isEmpty { paras = [(start: 0, len: 0)] }
            para = paras.lastIndex(where: { $0.start <= 0 }) ?? 0
            off = max(0, min(paras[para].len, -paras[para].start))
        }

        var current: Int { paras[para].start + off }
        /// Au bout du texte connu : iOS ne donne au clavier que quelques lignes autour du curseur, il faudra relire.
        var atStart: Bool { para == 0 && off == 0 }
        var atEnd: Bool { para == paras.count - 1 && off == paras[para].len }

        private func lastLine(_ len: Int) -> Int { len == 0 ? 0 : (len - 1) / perLine }

        /// n lettres à gauche (n < 0) ou à droite, sans sauter un retour à la ligne ; rend le déplacement fait.
        mutating func moveH(_ n: Int) -> Int {
            let o = max(0, min(paras[para].len, off + n))
            let moved = o - off
            off = o
            if moved != 0 { goalCol = nil }
            return moved
        }

        /// Une ligne plus haut (d < 0) ou plus bas, à la même colonne ; false au bout du texte connu.
        mutating func moveV(_ d: Int) -> Bool {
            let len = paras[para].len
            let line = min(off / perLine, lastLine(len))
            let col = goalCol ?? (off - line * perLine)
            goalCol = col
            if d < 0 {
                if line > 0 { off = min(len, (line - 1) * perLine + col); return true }
                guard para > 0 else { return false }
                para -= 1
                let l = paras[para].len
                off = min(l, lastLine(l) * perLine + col)
                return true
            }
            if line < lastLine(len) { off = min(len, (line + 1) * perLine + col); return true }
            guard para < paras.count - 1 else { return false }
            para += 1
            off = min(paras[para].len, col)
            return true
        }
    }
    private var order: [UITouch] = []

    static let topBarHeight: CGFloat = 42
    private let pad: CGFloat = 4
    private let gap: CGFloat = 6
    private let vgap: CGFloat = 11

    private var baseKeyH: CGFloat { CGFloat(screenKeyHeight) * (wideFull ? 1.24 : 1) }
    private var rowUnits: CGFloat { CGFloat(rowCount) + CGFloat(eff.spaceRowScale - 1) }
    private var fixedH: CGFloat { Self.topBarHeight + 6 + CGFloat(rowCount - 1) * vgap + 8 }
    /// La hauteur des touches à l'écran. Duo posé en mode « portable » (à moitié ouvert), iOS donne au clavier tout
    /// l'écran du bas : les touches grandissent pour le remplir (jusqu'à 1,8 fois) au lieu de laisser des bandes vides.
    /// Seulement là : ailleurs, une hauteur en trop venait souvent de l'autre écran (ou de l'aperçu dans l'app), et
    /// le réglage « hauteur des touches » d'un écran agrandissait aussi l'autre.
    /// La hauteur demandée à iOS (preferredHeight) reste celle des touches normales.
    private var keyH: CGFloat {
        let k = baseKeyH
        guard laptopLike, bounds.height > 0, bounds.height - (fixedH + k * rowUnits) > 12 else { return k }
        return max(k, min(k * 1.8, ((bounds.height - fixedH) / rowUnits).rounded(.down)))
    }
    /// Le mode « portable » : la charnière à moitié ouverte, ou, comme iOS ne le dit pas toujours au clavier, un
    /// clavier qui reçoit presque la moitié de l'écran déplié (un clavier normal en prend 40 % au plus).
    private var laptopLike: Bool {
        if hingeHalf { return true }
        guard gripContext.hasPrefix("open") else { return false }
        let h = screenSize.height
        return h > 0 && bounds.height >= h * 0.47
    }
    /// La hauteur des touches pour l'écran affiché : plié et déplié peuvent avoir chacun la leur.
    private var screenKeyHeight: Double {
        gripContext.hasPrefix("open") && eff.keyHeightOpen > 0 ? eff.keyHeightOpen : eff.keyHeight
    }
    /// Le clavier entier sur l'écran déplié : de grandes touches, comme le clavier d'Apple.
    private var wideFull: Bool { layoutMode == .full && bounds.width >= 560 && !showEmoji }
    private var reportedHeight: CGFloat = 0
    private var rowCount: Int { eff.numberRow ? 5 : 4 }
    /// Le haut de la barre : 0, ou plus bas si l'app hôte a donné plus de hauteur que demandé (le vide va au-dessus).
    private var barTop: CGFloat { max(0, (bounds.height - (fixedH + CGFloat(rowCount) * keyH + bottomExtra)).rounded(.down)) }
    var preferredHeight: CGFloat {
        fixedH + CGFloat(rowCount) * baseKeyH + (baseKeyH * CGFloat(eff.spaceRowScale - 1)).rounded()
    }
    /// La rangée de la barre d'espace peut être plus haute (ou plus basse) que les autres (réglage).
    private var bottomExtra: CGFloat { (keyH * CGFloat(eff.spaceRowScale - 1)).rounded() }

    /// Banc d'essai de la mémoire (simulateur) : combien de claviers vivent encore.
    static var alive = 0
    deinit { Self.alive -= 1; KBViews.canvases -= 1 }

    /// Banc d'essai de la mémoire (simulateur) : tape un texte comme au doigt, ouvre ou ferme les emojis.
    func probeType(_ s: String) { for ch in s { if ch == " " { typeSpace() } else { typeText(String(ch)) } } }
    func probeEmoji(_ on: Bool) {
        if on { showEmoji = true; builtFor = .zero; rebuild() } else { closeEmoji() }
    }

    /// Certaines apps (la recherche de l'écran d'accueil, en particulier sur les deux écrans du Duo) posent le clavier
    /// en panneau flottant, sans toucher le bas ou les bords de l'écran : on arrondit alors aussi les coins du bas,
    /// comme le clavier d'Apple, au lieu d'un rectangle aux angles droits.
    private func roundForHost() {
        guard let w = window else { return }
        let f = convert(bounds, to: w)
        // Dans Spotlight, le clavier flotte au-dessus du bas de l'écran, mais sa fenêtre (celle de l'extension)
        // fait juste sa taille : impossible de le voir d'ici. Le réglage « Arrondir les quatre coins » s'en charge,
        // et si iOS donne la vraie place de la fenêtre sur l'écran, on la lit.
        var floating = eff.roundAllCorners || f.maxY < w.bounds.maxY - 2 || f.minX > 2 || f.maxX < w.bounds.maxX - 2
        if !floating, let screen = w.windowScene?.screen {
            let g = convert(bounds, to: screen.coordinateSpace)
            let gap = screen.bounds.maxY - g.maxY
            // Une vraie position (la fenêtre n'est pas collée en haut de l'écran) et un petit vide sous le clavier
            // (pas la barre du globe et du micro d'iOS, plus haute) : il flotte.
            if g.minY > 40, gap > 8, gap < 56 || g.minX > 4 || g.maxX < screen.bounds.maxX - 4 { floating = true }
        }
        let corners: CACornerMask = floating
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
        let r: CGFloat = floating ? 28 : 24
        if layer.cornerRadius != r { layer.cornerRadius = r }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        Self.alive += 1
        KBViews.canvases += 1
        isMultipleTouchEnabled = true
        clipsToBounds = true
        // Passer de l'écran extérieur à l'écran intérieur garde parfois la même fenêtre : un changement de taille de
        // l'écran (classes de taille, échelle) refait aussi le clavier pour ce nouvel écran.
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self, UITraitDisplayScale.self]) { (v: KeyboardCanvas, _: UITraitCollection) in
            v.builtFor = .zero
            v.setNeedsLayout()
        }
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
        voice.isHidden = true
        voice.onCancel = { [weak self] in self?.cancelDictation() }
        voice.onDone = { [weak self] in self?.stopDictation() }
        voice.onOpenApp = { [weak self] in self?.openAppForDictation() }
        addSubview(voice)
        adjustButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        adjustButton.addAction(UIAction { [weak self] _ in self?.startAdjust() }, for: .touchUpInside)
        adjustButton.accessibilityLabel = L("Adjust the keyboard")
        for b in [modeButton, flipButton, middleButton, bigButton, hideButton, adjustButton, globeButton, emojiButton, clipButton, micButton] {
            b.tintColor = .label
            topBar.addSubview(b)
        }
        fixButton.setImage(UIImage(systemName: "wand.and.sparkles"), for: .normal)
        fixButton.accessibilityLabel = L("Fix the text")
        fixButton.addAction(UIAction { [weak self] _ in self?.fixTapped() }, for: .touchUpInside)
        topBar.addSubview(fixButton)
        translateButton.setImage(UIImage(systemName: "translate"), for: .normal)
        translateButton.accessibilityLabel = L("Translate")
        translateButton.addAction(UIAction { [weak self] _ in self?.translateTapped(to: nil) }, for: .touchUpInside)
        topBar.addSubview(translateButton)
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.accessibilityLabel = L("More")
        moreButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.barOpened.toggle()
            UIView.animate(withDuration: 0.18) { self.layoutTopBar() }
        }, for: .touchUpInside)
        topBar.addSubview(moreButton)
        voice.onTranslate = { [weak self] in self?.toggleDictTranslate() }
        micButton.setImage(UIImage(systemName: "mic"), for: .normal)
        micButton.accessibilityLabel = L("Dictation")
        micButton.addAction(UIAction { [weak self] _ in self?.micTapped() }, for: .touchUpInside)
        dictLabel.isHidden = true
        dictLabel.textAlignment = .center
        dictLabel.lineBreakMode = .byTruncatingHead
        dictLabel.font = .systemFont(ofSize: 15, weight: .medium)
        topBar.addSubview(dictLabel)
        modeButton.showsMenuAsPrimaryAction = true
        flipButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        flipButton.addAction(UIAction { [weak self] _ in self?.flipSide() }, for: .touchUpInside)
        flipButton.accessibilityLabel = L("Switch side")
        middleButton.setImage(UIImage(systemName: "rectangle.center.inset.filled"), for: .normal)
        middleButton.addAction(UIAction { [weak self] _ in self?.centerKeyboard() }, for: .touchUpInside)
        middleButton.accessibilityLabel = L("Keyboard in the middle")
        // Le menu système (UIMenu) s'ouvre dans l'app Foldboard et reste muet dans Messages, Safari, Discord.
        // Le « … » ouvre un panneau dessiné par le clavier lui-même.
        bigButton.addAction(UIAction { [weak self] _ in self?.toggleBarSheet() }, for: .touchUpInside)
        // Le bouton ouvre un menu (voir openLayoutMenu) : pas d'action directe.
        // Appui long : la situation reconnue et l'étalonnage utilisé (pour vérifier).
        // Le geste retient sa cible : un relais faible, sinon le clavier ne peut plus être libéré.
        let hold = KBWeakTarget(self)
        flipButton.addGestureRecognizer(UILongPressGestureRecognizer(target: hold, action: #selector(KBWeakTarget.grip(_:))))
        hideButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hideButton.addAction(UIAction { [weak self] _ in self?.input?.kbDismiss() }, for: .touchUpInside)
        hideButton.accessibilityLabel = L("Hide keyboard")
        hideButton.addGestureRecognizer(UILongPressGestureRecognizer(target: hold, action: #selector(KBWeakTarget.perf(_:))))
        layoutSwitch.addAction(UIAction { [weak self] _ in
            guard let self, !self.switchProgrammatic else { return }
            self.chooseOpenLayout(self.layoutSwitch.selectedSegmentIndex)
        }, for: .valueChanged)
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.addAction(UIAction { [weak self] _ in self?.globeTapped() }, for: .touchUpInside)
        emojiButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        emojiButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.showEmoji = true
            self.builtFor = .zero
            self.rebuild()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.checkMemory(force: true) }
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
        visibilityAtLoad = settings
        self.pro = pro
        // « Oublier mes mains » dans l'app : on efface aussi ce que le détecteur a appris pendant cette session.
        if settings.gripResetAt > UserDefaults.standard.double(forKey: "foldboard.gripResetSeen") {
            UserDefaults.standard.set(settings.gripResetAt, forKey: "foldboard.gripResetSeen")
            grip.reset()
        }
        eff = settings.effective(pro: pro)
        applyScreenMode()
        theme = KBTheme.named(eff.theme)
        suggest.setLayout(eff.layout)
        KBLayouts.currentLayoutIsFrench = eff.layout == .azerty
        KBClipboard.shared.autoSave = settings.clipAutoSave
        KBClipboard.shared.onDenied = { [weak self] in
            guard let self else { return }
            // Refusé deux fois : on arrête de lire tout seul (la demande ne revient plus à chaque copie).
            self.settings.clipAutoSave = false
            self.persist()
            self.flash(L("Saving copies is off: iOS asked each time. Paste still works."), hold: 3.5)
        }
        suggest.useNames = settings.contactNames
        let names = settings.contactNames
        suggestQueue.async { [bgSuggest] in bgSuggest.useNames = names }
        suggest.setMyWords(settings.activeMyWords)
        let mine = settings.activeMyWords
        suggestQueue.async { [bgSuggest] in bgSuggest.setMyWords(mine) }
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
        syncSensors()
    }

    /// Les capteurs de mouvement ne tournent que là où le clavier suit vraiment la main (et pendant l'étalonnage) :
    /// toute la largeur ou deux moitiés choisies pour un écran, ils restent éteints (batterie).
    private var needSensors: Bool { (autoOn && gripMoves) || recording != nil }

    private func syncSensors() {
        guard visible else { return }
        let wantKnock = eff.knockToMove && layoutMode.isOneHand && !demoOneHand && demoContext == nil
        knock.sensitivity = eff.knockSensitivity
        if wantKnock && !knock.running {
            knock.onKnock = { [weak self] pushedRight in self?.knocked(pushedRight) }
            knock.start()
        } else if !wantKnock && knock.running {
            knock.stop()
        }
        if needSensors && !gripStarted { startGrip() }
        if !needSensors && gripStarted { grip.stop(); gripStarted = false }
    }

    private var appearedAt: TimeInterval = 0

    /// Le clavier vient d'apparaître.
    func appeared() {
        Self.active = self
        hiddenByWindow = false
        // Annoncé deux fois de suite (la fenêtre, puis le contrôleur) : une seule remise en route.
        let now = ProcessInfo.processInfo.systemUptime
        if visible, now - appearedAt < 0.3 {
            builtFor = .zero
            setNeedsLayout()
            return
        }
        appearedAt = now
        visible = true
        resetGestures()
        perfStart()
        typedOnSide = 0
        showEmoji = false
        KBFeedback.shared.attach(to: self)
        tapMap = KBVault.loadTaps() ?? KBTapMap()
        tapDirty = 0
        if needSensors { startGrip() }
        page = .letters
        shift = .off
        refreshShift()
        KBFeedback.shared.prepare()
        emojiBoard.setClipMode(false)
        startClipWatch()
        resumePendingDictation()
        KBMemLog.begin(mb: Self.footprintMB(), context: gripContext, mode: (settings.screenModes[gripContext] ?? settings.mode).rawValue)
        // À l'apparition, les réglages ont déjà rechargé les listes rendues faute de place.
        listsShed = false
        checkMemory(force: true)
        startMemoryWatch()
        // Le modèle de glisser se charge une fois, après l'affichage, si iOS laisse encore de la mémoire — et
        // seulement si le glisser est allumé.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.visible, self.eff.glide else { return }
            NeuralSwipe.warm()
        }
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
    /// L'écran du dernier clavier affiché : un nouveau clavier (iOS en crée un à chaque apparition) part de là,
    /// au lieu de se croire sur l'écran fermé tant qu'il n'est pas à l'écran (hauteur demandée de l'autre écran).
    static var lastContext: String?
    private var gripContext = KeyboardCanvas.lastContext ?? "closed-portrait"
    /// La charnière du Duo : fermé (true), ouvert (false), inconnue (nil).
    private var hingeClosed: Bool?
    /// La charnière à moitié ouverte (mode « portable »).
    private var hingeHalf = false
    private var hingeWatched = false
    /// Tant que l'angle de la charnière bouge, on ne replace pas les touches (sinon les rangées glissent).
    private var hingeSettling = false
    private var hingeTicket = 0
    private var hingeApplies = 0
    private var pendingHingeClosed: Bool?
    private var pendingHingeHalf = false

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
        persist()
    }

    private func watchHinge() {
        guard !hingeWatched else { return }
        hingeWatched = true
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                let closed: Bool?
                switch update.hinge?.status {
                case .closed?: closed = true
                case .partiallyOpen?, .fullyOpen?: closed = false
                default: closed = nil
                }
                self.scheduleHinge(closed: closed, half: update.hinge?.status == .partiallyOpen)
            })
        }
    }

    /// Plusieurs messages arrivent pendant que le téléphone se plie. On n'applique que le dernier,
    /// une fois l'angle stabilisé, et les touches prennent leur place d'un coup.
    private func scheduleHinge(closed: Bool?, half: Bool) {
        hingeSettling = true
        pendingHingeClosed = closed
        pendingHingeHalf = half
        hingeTicket += 1
        let ticket = hingeTicket
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, ticket == self.hingeTicket else { return }
            self.applyScheduledHinge()
        }
    }

    private func applyScheduledHinge() {
        hingeClosed = pendingHingeClosed
        hingeHalf = pendingHingeHalf
        hingeSettling = false
        hingeApplies += 1
        learnScreen()
        updateGripContext()
        builtFor = .zero
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setNeedsLayout()
            layoutIfNeeded()
            CATransaction.commit()
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
        if window == nil, demoContext == nil, !demoOneHand, let last = Self.lastContext { c = last }
        gripContext = c
        if window != nil, demoContext == nil, !demoOneHand { Self.lastContext = c }
        applyScreenMode()
        grip.angleOffset = kbAngleOffset(window?.windowScene?.interfaceOrientation)
        grip.useTilt = eff.followTilt
        grip.useThumbs = eff.followThumbs
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
        if correction {
            noteCorrection()
            var e: [String: Double] = ["g": two ? 2 : (right ? 1 : 0)]
            if let q = grip.currentPosture { e["roll"] = q.roll; e["inc"] = q.incline }
            KBGripLog.shared.add(4, context: gripContext, e)
        }
        guard let p = grip.currentPosture else { return }
        KBHabits.shared.add(context: gripContext, roll: p.roll, incline: p.incline, right: right, two: two,
                            weight: correction ? 3 : 1, correction: correction)
        grip.habitReady = KBHabits.shared.ready(context: gripContext, seeds: habitSeeds)
        showLearning(correction: correction)
    }

    /// Montrer que le clavier apprend : « noté » aux premières corrections, puis des paliers.
    private func showLearning(correction: Bool) {
        guard settings.learningTips else { return }
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

    /// Le clavier affiché en dernier. Quand le Duo s'ouvre ou se ferme, iOS garde parfois l'ancien clavier (celui de
    /// l'autre écran) par-dessus le nouveau : ses touches, rangées pour l'autre largeur, recevaient les appuis
    /// (« le clavier est en pleine largeur, mais les touches tapent ailleurs »). Seul le dernier répond.
    private static weak var active: KeyboardCanvas?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        roundForHost()
        if window != nil { Self.active = self }
        // Autre écran, autre fenêtre : on redessine tout pour celui-ci, même si la largeur est la même.
        builtFor = .zero
        setNeedsLayout()
        watchHinge()
        updateGripContext()
        // Revenu à l'écran sans « apparition » (dans l'app, après une autre page) : on relance ce qui tournait.
        if window != nil, hiddenByWindow { appeared() }
    }

    /// Le clavier quitte l'écran par n'importe quel chemin (iOS ne prévient pas toujours avec viewWillDisappear) :
    /// on coupe tout ce qui tourne, pour que le clavier puisse être libéré.
    private var hiddenByWindow = false
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, visible { disappeared(); hiddenByWindow = true }
    }

    /// Le contrôleur du clavier est détruit : plus rien ne doit tourner (capteurs, minuteries, mesure).
    func shutdown() {
        knock.stop()
        if visible { disappeared() }
        perfLink?.invalidate()
        perfLink = nil
        idleTimer?.invalidate()
        clipTimer?.invalidate()
        clipTimer = nil
        grip.stop()
        grip.onGrip = nil
        grip.onUnlock = nil
        grip.onSample = nil
        grip.onSwipeSample = nil
        gripStarted = false
        trackEdgeTimer?.invalidate()
        trackEdgeTimer = nil
        // Si quelque chose garde encore ce clavier, il ne garde plus rien de lourd : touches, emojis, suggestions.
        cells.forEach { $0.view.removeFromSuperview() }
        cells = []
        emojiBoard.releaseMemory()
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        interactions.forEach { removeInteraction($0) }
        hingeWatched = false
        builtFor = .zero
    }

    /// Tout ce qui ne vaut que le temps d'un geste. Le même clavier sert à chaque apparition (iOS change de
    /// contrôleur à chaque pli, rotation ou changement d'app) : un doigt dont iOS n'a jamais annoncé la fin laissait
    /// le pavé tactile affiché (touches sans lettres, barre vide), une touche enfoncée ou l'effacement qui continue.
    private func resetGestures() {
        for tr in tracks.values {
            tr.done = true
            tr.longTimer?.invalidate()
            tr.repeatTimer?.invalidate()
        }
        tracks.removeAll()
        order.removeAll()
        placeTouches.removeAll()
        pageSlide = nil
        idleTimer?.invalidate()
        pendingGrip = nil
        liveWork?.cancel(); liveWork = nil
        heightWork?.cancel(); heightWork = nil
        setTrackpad(false, animated: false)
        hideBubble()
        accentView.isHidden = true
        glideLayer.removeAllAnimations()
        glideLayer.path = nil
        glideLayer.opacity = 0
        glidedWord = nil
        dictatedTail = nil
        lastCorrection = nil
        wordTouches.removeAll()
        emojiQuery = nil
        barOpened = false
        barSheet?.isHidden = true
        hingeSettling = false
        fixing = false
        toast.layer.removeAllAnimations()
        toast.alpha = 0
        for i in cells.indices { setPressed(i, false) }
    }

    /// Le clavier disparaît : on coupe les capteurs.
    func disappeared() {
        knock.stop()
        visible = false
        // Le réglage au doigt en cours est gardé tel qu'il est (pas de poignées encore affichées au retour).
        if adjusting { endAdjust(keep: true) }
        resetGestures()
        saveTaps()
        if dictState != .idle {
            KBDictation.post(KBDictation.stop)
            dictState = .idle
        }
        if micMode {
            micMode = false
            mic?.cancel()
        }
        releaseMicIfIdle()
        memTimer?.invalidate()
        memTimer = nil
        pasteControl = nil
        voice.isHidden = true
        perfLink?.invalidate()
        perfLink = nil
        grip.stop()
        gripStarted = false
        idleTimer?.invalidate()
        clipTimer?.invalidate()
        clipTimer = nil
        KBStatsRecorder.shared.flush()
        KBGripLog.shared.flush()
        // Le clavier n'est plus à l'écran : on rend la mémoire des emojis (iOS ferme les claviers trop gourmands,
        // surtout quand le Duo s'ouvre et que deux claviers tournent un instant).
        if !showEmoji { emojiBoard.releaseMemory() }
    }

    /// La mémoire utilisée par le clavier (celle qu'iOS compte pour le fermer), en Mo, et le maximum vu.
    static var memoryPeak: Double = 0
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let mb = Double(info.phys_footprint) / 1_048_576
        memoryPeak = max(memoryPeak, mb)
        return mb
    }

    /// Un seul clavier pour le processus. Un pli ou une rotation donne un nouveau contrôleur iOS :
    /// on y déplace ce clavier, on n'en construit pas un deuxième.
    static var shared: KeyboardCanvas?
    private var hostPins: [NSLayoutConstraint] = []

    func move(to host: UIView) {
        guard superview !== host else { return }
        NSLayoutConstraint.deactivate(hostPins)
        hostPins.removeAll()
        removeFromSuperview()
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        hostPins = [
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
            topAnchor.constraint(equalTo: host.topAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostPins)
    }

    static func install(in host: UIView) -> KeyboardCanvas {
        let c = shared ?? KeyboardCanvas()
        shared = c
        c.move(to: host)
        return c
    }

    /// Trente plis et rotations, comme sur le Duo. Vrai si un seul clavier reste, les touches ne se
    /// multiplient pas, le modèle neuronal n'est chargé qu'une fois, et la mémoire reste sous 50 Mo.
    static func simulateFoldCycles() -> Bool {
        let scenes: [(String, CGSize, KBMode)] = [
            ("closed-portrait", CGSize(width: 390, height: 280), .full),
            ("closed-landscape", CGSize(width: 844, height: 200), .left),
            ("open-portrait", CGSize(width: 670, height: 340), .auto),
            ("open-landscape", CGSize(width: 980, height: 360), .split),
        ]
        var host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 360))
        let canvas = install(in: host)
        var base = KBSettings()
        base.layout = .azerty
        base.mode = .full
        canvas.configure(settings: base, pro: true)
        NeuralSwipe.warm()
        let loads = NeuralSwipe.loads
        let modelPresent = Bundle.main.url(forResource: "futo-swipe-encoder-int8", withExtension: "pte") != nil
        var mb: [Double] = []
        var keys: [Int] = []
        var views: [Int] = []
        for i in 0..<30 {
            let s = scenes[i % scenes.count]
            autoreleasepool {
                // Un contrôleur neuf à chaque pli, comme iOS. Le bassin lâche menus et images
                // avant la mesure : sans lui, la boucle les garde et la mémoire monte à tort.
                let next = UIView(frame: CGRect(x: 0, y: 0, width: s.1.width, height: s.1.height + 48))
                let c = install(in: next)
                NSLayoutConstraint.deactivate(c.hostPins)
                c.hostPins.removeAll()
                c.translatesAutoresizingMaskIntoConstraints = true
                c.frame = CGRect(origin: .zero, size: s.1)
                c.demoContext = s.0
                c.settings.screenModes[s.0] = s.2
                c.settings.mode = s.2
                c.eff = c.settings.effective(pro: true)
                c.builtFor = .zero
                c.layoutIfNeeded()
                host = next
            }
            let m = footprintMB()
            mb.append(m)
            keys.append(KBViews.keys)
            views.append(KBViews.live)
            print("RESULT memcycle \(i) \(String(format: "%.1f", m)) Mo claviers \(alive) touches \(KBViews.keys) vues \(KBViews.live) loads \(NeuralSwipe.loads) \(s.0)")
        }
        NeuralSwipe.warm()
        let final = mb.last ?? 99
        let early = mb.count > 4 ? mb[4] : final
        let growth = final - early
        let keysFlat = keys.count > 4 && keys.dropFirst(4).allSatisfy { $0 == keys[4] }
        let viewsFlat = views.count > 4 && views.dropFirst(4).allSatisfy { $0 == views[4] }
        let built = (keys.last ?? 0) >= 20
        var rises = 0
        if mb.count > 5 {
            for i in 5..<mb.count where mb[i] > mb[i - 1] + 0.35 { rises += 1 }
        }
        let once = NeuralSwipe.loads == loads && loads <= 1 && (!modelPresent || loads == 1)
        let plateau = alive == 1 && keysFlat && viewsFlat && built && final < 50 && growth <= 3 && rises <= 6 && once
        print("RESULT memcycle plateau \(plateau ? "yes" : "no") final \(String(format: "%.1f", final)) growth \(String(format: "%+.1f", growth)) rises \(rises) claviers \(alive) touches \(KBViews.keys) vues \(KBViews.live) loads \(NeuralSwipe.loads)")
        return plateau
    }

    /// Les bugs remontés par les testeurs le 26 novembre, rejoués :
    ///  - un pavé tactile resté affiché (touches sans lettres, barre vide) ne survit pas à la prochaine apparition ;
    ///  - un doigt posé au milieu d'une touche écrit cette touche, même avec un décalage appris maximal (effacer et
    ///    « P » au bord compris) ;
    ///  - une touche reprise au pot revient toujours avec sa lettre.
    static func verifyTouchSafety() -> Bool {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 669, height: 420))
        let c = install(in: host)
        NSLayoutConstraint.deactivate(c.hostPins)
        c.hostPins.removeAll()
        c.translatesAutoresizingMaskIntoConstraints = true
        c.demoContext = "open-portrait"
        c.frame = CGRect(x: 0, y: 0, width: 669, height: 300)
        var s = KBSettings()
        s.layout = .qwerty
        s.mode = .full
        c.configure(settings: s, pro: true)
        c.appearedAt = 0
        c.appeared()
        c.builtFor = .zero
        c.layoutIfNeeded()
        // 1. Le pavé tactile resté bloqué.
        c.setTrackpad(true, animated: false)
        let hidden = c.cells.allSatisfy { $0.view.label.alpha == 0 } && c.chips.alpha == 0
        c.page = .numbers
        c.builtFor = .zero
        c.rebuild()
        c.disappeared()
        c.appearedAt = 0
        c.appeared()
        c.builtFor = .zero
        c.layoutIfNeeded()
        let shown = !c.trackpadOn && c.chips.alpha == 1 && c.hideButton.alpha == 1 && c.tracks.isEmpty
            && c.cells.allSatisfy { $0.view.label.alpha == 1 && $0.view.icon.alpha == 1 && $0.view.alpha == 1 && !$0.view.isHidden }
            && c.keyPool.allSatisfy { $0.label.alpha == 1 && $0.icon.alpha == 1 }
        let labelled = c.cells.allSatisfy { cell in
            if case .char(let ch) = cell.view.spec.kind { return cell.view.label.text?.lowercased() == ch.lowercased() }
            return true
        }
        // 2. Le centre de chaque touche, avec le décalage appris le plus fort dans chaque sens.
        var centred = true
        for dx in [-0.9, 0.9] {
            var m = KBTapMap()
            for _ in 0..<80 { m.add(key: "g", dx: dx * 0.8, dy: 0.3, twoHands: true) }
            c.tapMap = m
            for (i, cell) in c.cells.enumerated() {
                // +4 : le clavier retire 4 pt à chaque appui (le pouce touche plus bas qu'il ne vise).
                if c.cellIndex(at: CGPoint(x: cell.frame.midX, y: cell.frame.midY + 4)) != i { centred = false }
            }
        }
        // 3. Et le décalage appris sert bien entre deux lettres (près de la frontière).
        var learns = false
        if let g = c.cells.firstIndex(where: { $0.view.spec.kind == .char("g") }),
           let h = c.cells.firstIndex(where: { $0.view.spec.kind == .char("h") }) {
            let border = CGPoint(x: (c.cells[g].frame.maxX + c.cells[h].frame.minX) / 2 + 2, y: c.cells[g].frame.midY + 4)
            c.tapMap = KBTapMap()
            let plain = c.cellIndex(at: border)
            var m = KBTapMap()
            for _ in 0..<80 { m.add(key: "g", dx: 0.3, dy: 0, twoHands: true) }
            c.tapMap = m
            learns = plain == h && c.cellIndex(at: border) == g
        }
        c.tapMap = KBTapMap()
        c.disappeared()
        let ok = hidden && shown && labelled && centred && learns
        print("RESULT touchsafety pave_cache=\(hidden) retabli=\(shown) lettres=\(labelled) centre=\(centred) frontiere=\(learns) \(ok ? "yes" : "no")")
        return ok
    }

    /// Le filet mémoire : les paliers, et le dernier recours (les listes de mots rendues, puis rechargées à
    /// l'apparition suivante) sans que le clavier s'arrête d'écrire.
    static func verifyMemoryShed() -> Bool {
        let levels = memoryLevel(footprintMB: 30, headroomMB: 30) == .fine && memoryLevel(footprintMB: 58, headroomMB: 12) == .tight
            && memoryLevel(footprintMB: 40, headroomMB: 5) == .critical && memoryLevel(footprintMB: 40, headroomMB: 0) == .fine
            && memoryLevel(footprintMB: 47, headroomMB: 0) == .tight && memoryLevel(footprintMB: 60, headroomMB: 0) == .critical
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 360))
        let c = install(in: host)
        NSLayoutConstraint.deactivate(c.hostPins)
        c.hostPins.removeAll()
        c.translatesAutoresizingMaskIntoConstraints = true
        c.demoContext = "closed-portrait"
        c.frame = CGRect(x: 0, y: 0, width: 390, height: 280)
        var s = KBSettings()
        s.layout = .azerty
        s.mode = .full
        c.configure(settings: s, pro: true)
        backQueue.sync {}
        c.builtFor = .zero
        c.layoutIfNeeded()
        let loaded = c.suggest.hasLists && c.bgSuggest.hasLists
        let before = footprintMB()
        c.shedMemory(.critical)
        backQueue.sync {}
        let after = footprintMB()
        let shed = !c.suggest.hasLists && !c.bgSuggest.hasLists && c.listsShed
        // Le clavier écrit toujours, et la correction ne plante pas sans ses listes.
        let field = ProbeField()
        c.input = field
        c.probeType("bonjour ca va ")
        _ = c.suggest.correction(for: "bonjoru", before: "bonjoru", touch: nil, fast: true)
        _ = c.suggest.predictions(before: "je suis ")
        let typed = field.text.lowercased().hasPrefix("bonjour")
        // Apparition suivante : tout revient.
        c.configure(settings: s, pro: true)
        backQueue.sync {}
        c.appearedAt = 0
        c.appeared()
        let back = c.suggest.hasLists && c.bgSuggest.hasLists && !c.listsShed
        c.disappeared()
        c.input = nil
        let ok = levels && loaded && shed && typed && back
        print("RESULT memshed paliers=\(levels) charge=\(loaded) rendu=\(shed) (\(String(format: "%.1f", before)) → \(String(format: "%.1f", after)) Mo) ecrit=\(typed) revenu=\(back) \(ok ? "yes" : "no")")
        return ok
    }

    /// Un champ de texte pour les essais : ce que le clavier écrit.
    final class ProbeField: KBInput {
        var text = ""
        func kbInsert(_ t: String) { text += t }
        func kbDelete() { if !text.isEmpty { text.removeLast() } }
        func kbMoveCursor(_ offset: Int) {}
        func kbTextBefore() -> String? { String(text.suffix(400)) }
        func kbTextAfter() -> String? { "" }
        func kbNextKeyboard() {}
        func kbDismiss() {}
        func kbSettingsChanged(_ settings: KBSettings) {}
        var kbNeedsGlobe: Bool { false }
        var kbFullAccess: Bool { false }
        func kbRecheckPro(_ done: @escaping (Bool) -> Void) { done(true) }
    }

    /// Chaque interrupteur de la barre, après une mise en page : le bouton correspondant est caché ou montré.
    static func verifyVisibility() -> Bool {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 980, height: 420))
        let c = install(in: host)
        NSLayoutConstraint.deactivate(c.hostPins)
        c.hostPins.removeAll()
        c.translatesAutoresizingMaskIntoConstraints = true
        func layout(_ edit: (inout KBSettings) -> Void) {
            var s = KBSettings()
            s.layout = .azerty
            s.mode = .right
            s.layoutSwitchOpenOnly = false
            edit(&s)
            c.demoContext = "open-landscape"
            c.frame = CGRect(x: 0, y: 0, width: 980, height: 360)
            c.configure(settings: s, pro: true)
            c.builtFor = .zero
            c.layoutIfNeeded()
        }
        layout {
            $0.emojiKey = false
            $0.showHandButton = true
            $0.showSettingsButton = false
            $0.showMicButton = false
            $0.showClipboardButton = false
            $0.dictationKey = true
            $0.hideKeyButton = false
            $0.showLayoutSwitch = false
            $0.showSwapButton = false
            $0.showCenterButton = false
            $0.showLayoutMenu = false
            $0.showMoreButton = false
        }
        let off = c.visibilityProbe()
        layout {
            $0.emojiKey = true
            $0.showHandButton = true
            $0.showSettingsButton = true
            $0.showMicButton = true
            $0.showClipboardButton = true
            $0.dictationKey = true
            $0.hideKeyButton = true
            $0.showLayoutSwitch = true
        }
        let on = c.visibilityProbe()
        // Le raccourci des dispositions : sur le clavier entier (il a sa place), entier et jamais sur les mots,
        // avec ou sans suggestions ; pas sur le petit clavier à une main (il y serait écrasé).
        layout { $0.mode = .full }
        let wide = c.visibilityProbe().layoutSwitch
        c.suggestionItems = ["bonjour", "bonsoir", "bonne"]
        c.layoutTopBar()
        let still = c.visibilityProbe().layoutSwitch
        let whole = c.layoutSwitch.frame.width >= layoutSwitchWidth - 0.5
            && !c.layoutSwitch.frame.intersects(c.chips.frame) && c.chips.frame.width >= 3 * 78
        c.suggestionItems = []
        let ok = !off.emoji && !off.adjust && off.mode && !off.mic && !off.hide && !off.clip && !off.layoutSwitch
            && on.emoji && on.adjust && on.mode && on.mic && on.hide && on.clip && !on.layoutSwitch && wide && still && whole
        print("RESULT visibility off emoji=\(off.emoji) adjust=\(off.adjust) mode=\(off.mode) mic=\(off.mic) clip=\(off.clip) hide=\(off.hide) switch=\(off.layoutSwitch) on emoji=\(on.emoji) adjust=\(on.adjust) mode=\(on.mode) mic=\(on.mic) clip=\(on.clip) hide=\(on.hide) switch_petit=\(on.layoutSwitch) switch_entier=\(wide) stable=\(still) entier=\(whole) \(ok ? "yes" : "no")")
        let cached = KBVault.resolveAccess(shared: nil, cache: {
            var a = KBAccess()
            a.purchased = true
            return a
        }())
        let fresh = KBVault.resolveAccess(shared: {
            var a = KBAccess()
            a.purchased = true
            return a
        }(), cache: nil)
        let proOK = cached.access.purchased && !cached.trusted && fresh.access.purchased && fresh.trusted
        print("RESULT access cache=\(cached.access.purchased) trusted=\(cached.trusted) fresh=\(fresh.trusted) \(proOK ? "yes" : "no")")
        return ok && proOK
    }

    func visibilityProbe() -> (emoji: Bool, adjust: Bool, mode: Bool, mic: Bool, hide: Bool, hand: Bool, clip: Bool, layoutSwitch: Bool) {
        func on(_ v: UIView) -> Bool { v.isHidden == false && v.alpha > 0.5 && v.frame.width > 1 }
        return (on(emojiButton), on(adjustButton), on(modeButton), on(micButton), on(hideButton), on(modeButton), on(clipButton), on(layoutSwitch))
    }

    // MARK: Mémoire
    //
    // iOS ferme un clavier qui dépasse sa limite de mémoire (et remet le clavier d'Apple à la place). La limite change
    // d'un iPhone à l'autre : on ne regarde donc pas un nombre de Mo fixe mais la marge qu'iOS dit laisser encore
    // (os_proc_available_memory), toutes les deux secondes tant que le clavier est à l'écran et aux moments qui
    // coûtent (emojis, dictée, pli). Trois paliers :
    //  - serré : on rend ce qui se recrée sans que ça se voie (emojis cachés, modèle de glisser, page de la dictée,
    //    caches) ;
    //  - critique : on ferme aussi les emojis et on rend les listes de mots et le modèle de langue (les suggestions
    //    s'arrêtent un instant, le clavier reste) ; ils reviennent dès qu'il y a de nouveau de la place.

    enum MemoryLevel: Int { case fine, tight, critical }

    /// Le palier pour une empreinte et une marge données (marge nulle ou négative : inconnue, simulateur).
    static func memoryLevel(footprintMB mb: Double, headroomMB room: Double) -> MemoryLevel {
        if room > 0 {
            if room < 7 { return .critical }
            if room < 14 { return .tight }
            return .fine
        }
        if mb > 54 { return .critical }
        if mb > 44 { return .tight }
        return .fine
    }

    private var memChecks = 0
    private var memTimer: Timer?
    private var lastCritical: TimeInterval = 0
    private var lastTight: TimeInterval = -100
    /// Les listes de mots ont été rendues (palier critique) : à recharger quand la place revient.
    private var listsShed = false
    private var shedAt: TimeInterval = 0

    private func startMemoryWatch() {
        memTimer?.invalidate()
        memTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkMemory(force: true, log: false) }
    }

    /// Filet de sécurité : si le clavier approche la limite d'iOS, il libère ce qu'il peut avant qu'iOS ne le ferme.
    private func checkMemory(force: Bool = false, log: Bool = true) {
        memChecks += 1
        guard force || memChecks % 30 == 0 else { return }
        let mb = Self.footprintMB()
        let room = NeuralSwipe.availableMB()
        if log {
            KBMemLog.note(mb: mb, emoji: showEmoji, alive: Self.alive, views: KBViews.live)
            NeuralSwipe.noteFootprint()
        }
        let level = Self.memoryLevel(footprintMB: mb, headroomMB: room)
        if level != .fine { shedMemory(level) }
        else if listsShed { restoreListsIfRoom(footprintMB: mb, headroomMB: room) }
    }

    /// Rend de la mémoire selon le palier. `critical` au plus une fois toutes les 3 secondes.
    func shedMemory(_ level: MemoryLevel) {
        guard level != .fine else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Un iPhone dont la limite est basse reste « serré » en permanence : on ne refait pas le ménage toutes les
        // deux secondes (les caches du correcteur servent à la frappe), seulement toutes les dix.
        if level == .critical || now - lastTight > 10 {
            lastTight = now
            trimMemory(flush: false)
            NeuralSwipe.release()
            releaseMicIfIdle()
        }
        guard level == .critical else { return }
        guard now - lastCritical > 3 else { return }
        lastCritical = now
        KBSymbol.clear()
        pasteControl = nil
        KBMemLog.note(mb: Self.footprintMB(), emoji: showEmoji, alive: Self.alive, views: KBViews.live)
        if !listsShed {
            // D'abord les listes de mots (une dizaine de Mo) : les emojis ouverts restent ouverts.
            listsShed = true
            shedAt = now
            suggest.shed()
            suggestQueue.async { [bgSuggest] in
                bgSuggest.shed()
                KBSuggest.shedShared()
            }
            cachedFix = nil
            applySuggestions([], nil)
        } else if showEmoji {
            // Toujours critique alors que tout le reste est rendu : les emojis se ferment, le clavier reste.
            closeEmoji()
        }
    }

    /// La place est revenue (au moins 20 secondes plus tard, pour ne pas recharger et rendre en boucle) : les mots
    /// et le modèle de langue reviennent.
    private func restoreListsIfRoom(footprintMB mb: Double, headroomMB room: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard listsShed, now - shedAt > 20, tracks.isEmpty else { return }
        guard room > 0 ? room > 26 : mb < 34 else { return }
        reloadLists()
    }

    /// Recharge les listes à part (elles sont partagées : le correcteur du fil principal les reprend ensuite sans
    /// rien reconstruire, la frappe ne se fige pas).
    private func reloadLists() {
        guard listsShed else { return }
        listsShed = false
        let layout = eff.layout
        suggestQueue.async { [weak self, bgSuggest] in
            bgSuggest.setLayout(layout)
            DispatchQueue.main.async {
                guard let self, !self.listsShed, self.eff.layout == layout else { return }
                self.suggest.setLayout(layout)
                self.refreshSuggestionsSoon()
            }
        }
    }

    /// iOS prévient qu'il manque de mémoire : on libère tout ce qui se recrée tout seul, pour ne pas être fermé
    /// (et remplacé par le clavier d'Apple).
    func trimMemory(flush: Bool = true) {
        if !showEmoji { emojiBoard.releaseMemory() } else { emojiBoard.trimPool() }
        suggest.trimMemory()
        suggestQueue.async { [bgSuggest] in bgSuggest.trimMemory() }
        // Écrire le journal ne libère rien (et demande un peu de mémoire) : seulement quand iOS prévient.
        if flush { KBGripLog.shared.flush() }
    }

    /// iOS prévient (alerte mémoire) : comme le palier serré, ou critique s'il ne reste presque rien.
    func memoryWarning() {
        let level = Self.memoryLevel(footprintMB: Self.footprintMB(), headroomMB: NeuralSwipe.availableMB())
        shedMemory(level == .critical ? .critical : .tight)
        KBGripLog.shared.flush()
    }

    /// La page cachée de la dictée dans le clavier (WebKit) : rendue dès que la dictée est finie. Avant, elle
    /// restait en mémoire pour toujours après la première dictée.
    private var micRelease: DispatchWorkItem?
    private func releaseMicIfIdle() {
        micRelease?.cancel()
        micRelease = nil
        guard !micMode, dictState == .idle, let m = mic else { return }
        m.tearDown()
        mic = nil
    }

    /// Après une dictée : la page reste 20 secondes (pour enchaîner), puis elle est rendue.
    private func releaseMicSoon() {
        micRelease?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.releaseMicIfIdle() }
        micRelease = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
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

    /// Le globe : on passe à un autre clavier. Au retour (dans les deux minutes), Foldboard revient exactement là
    /// où il était, sans relire l'inclinaison (c'est en tendant le pouce vers le globe qu'on penche le téléphone).
    private static let globeKey = "foldboard.globeAt"
    private func globeTapped() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.globeKey)
        input?.kbNextKeyboard()
    }

    private var gripStarted = false
    private func startGrip() {
        gripStarted = true
        grip.onGrip = { [weak self] g in self?.gripDetected(g) }
        grip.onUnlock = { [weak self] in self?.layoutTopBar() }
        let fromGlobe = Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: Self.globeKey) < 120
        if fromGlobe { UserDefaults.standard.removeObject(forKey: Self.globeKey) }
        grip.start { [weak self] g in
            guard let self, let g, self.autoOn, self.gripMoves else { return }
            // Retour par le globe : le clavier reste du côté où il était.
            if fromGlobe { return }
            // Sans posture « deux mains » étalonnée, l'inclinaison ne fait pas quitter le mode deux mains.
            if self.settings.autoTwo && self.settings.calib[self.gripContext]?["two"] == nil { return }
            self.applyGrip(g)
        }
    }

    private func gripDetected(_ g: KBGrip) {
        guard autoOn, gripMoves else { return }
        pendingGrip = g
        scheduleGrip()
    }

    /// On ne déplace pas les touches sous le doigt : on attend une petite pause dans la frappe.
    private func scheduleGrip() {
        idleTimer?.invalidate()
        guard pendingGrip != nil, tracks.isEmpty else { return }
        // Une vraie pause, pas l'intervalle entre deux lettres : le clavier changeait de côté pendant que le pouce
        // allait vers la touche suivante, et l'appui tombait sur une autre touche.
        let since = ProcessInfo.processInfo.systemUptime - lastKeyTime
        idleTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, Self.gripPause - since), repeats: false) { [weak self] _ in
            guard let self, let g = self.pendingGrip, self.tracks.isEmpty else { return }
            guard ProcessInfo.processInfo.systemUptime - self.lastKeyTime >= Self.gripPause - 0.02 else { self.scheduleGrip(); return }
            self.applyGrip(g)
        }
    }

    /// Le temps sans appui avant que le clavier ose changer de côté tout seul.
    private static let gripPause: TimeInterval = 0.45

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
        var e: [String: Double] = ["g": g == .two ? 2 : (g == .right ? 1 : 0)]
        if let q = grip.currentPosture { e["roll"] = q.roll; e["inc"] = q.incline }
        KBGripLog.shared.add(3, context: gripContext, e)
        KBThumb.shared.reset()
        typedOnSide = 0
        settings = s
        save()
        layoutIfNeeded()
    }

    /// Le lexique de l'utilisateur (contacts, remplacements de texte).
    func setLexicon(_ lexicon: UILexicon) {
        suggest.setLexicon(lexicon)
        suggestQueue.async { [bgSuggest] in
            bgSuggest.setLexicon(lexicon)
            // Une fois : on oublie les fautes de frappe retenues comme des mots par les versions d'avant.
            KBWordStore.shared.purge { bgSuggest.isReal($0) }
        }
    }

    /// Le texte a changé (curseur déplacé, autre champ) : on revoit la majuscule et les suggestions.
    func textChanged() {
        refreshSuggestionsSoon()
        // Un autre champ (recherche, message…) : la touche retour change.
        if (input?.kbReturnType ?? .default) != shownReturnType { updateLabels() }
        // Collé avec le menu d'iOS : « Coller » s'en va de la barre.
        if KBClipboard.shared.freshText != nil {
            KBClipboard.shared.dismissIfPasted(before: String((input?.kbTextBefore() ?? "").suffix(400)))
            if KBClipboard.shared.freshText == nil, suggestionItems.isEmpty { rebuildChips() }
        }
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

    /// Réglages au dernier chargement : un interrupteur bougé depuis là n'est pas écrasé par une copie plus récente.
    private var visibilityAtLoad = KBSettings()

    private func save() {
        let edited = settings
        let stored = KBVault.loadSettings()
        if stored.stamp > visibilityAtLoad.stamp && stored.stamp > edited.stamp {
            settings.takeVisibility(from: stored)
            settings.restoreVisibilityEdits(from: edited, baseline: visibilityAtLoad)
        }
        settings.stamp = Date()
        let stamped = settings
        input?.kbSettingsChanged(stamped)
        visibilityAtLoad = stamped
        configure(settings: stamped, pro: pro)
        settings.stamp = stamped.stamp
        visibilityAtLoad = settings
    }

    /// Un réglage changé par le clavier lui-même (taille d'écran apprise, mot gardé…) : enregistré avec sa date,
    /// sans refaire les touches.
    private func persist() {
        settings.stamp = Date()
        input?.kbSettingsChanged(settings)
    }

    /// L'app vient d'enregistrer des réglages : faut-il les prendre ? Seulement s'ils sont plus récents que ceux du
    /// clavier et vraiment différents, et jamais pendant qu'un doigt est posé ou qu'on règle le clavier au doigt.
    func shouldAdopt(_ stored: KBSettings) -> Bool {
        guard tracks.isEmpty, !adjusting, stored.stamp > settings.stamp else { return false }
        var a = stored, b = settings
        a.stamp = .distantPast; b.stamp = .distantPast
        return a != b
    }

    /// La disposition de cet écran (réglée par écran, sinon la générale), avec les limites de la version gratuite.
    private func applyScreenMode() {
        var m = settings.mode(for: gripContext)
        if !pro {
            if m == .split { m = .full }
            if m == .auto { m = settings.autoRight ? .right : .left }
        }
        eff.mode = m
    }

    /// Choisir une disposition depuis le clavier : pour cet écran seulement (fermé, ouvert en portrait, en paysage…).
    private func setScreenMode(_ m: KBMode, in s: inout KBSettings) {
        s.screenModes[gripContext] = m
    }

    private func setMode(_ m: KBMode) {
        if (m == .auto || m == .split) && !pro {
            guard let input else { flash(L("Foldboard Pro: open the app to unlock")); return }
            input.kbRecheckPro { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.pro = true
                    self.setMode(m)
                } else if !input.kbFullAccess, KBVault.accessTrusted {
                    self.flash(L("Allow Full Access to use Foldboard Pro"))
                } else if KBVault.accessTrusted {
                    self.flash(L("Foldboard Pro: open the app to unlock"))
                }
            }
            return
        }
        setScreenMode(m, in: &settings)
        applyScreenMode()
        grip.locked = false
        save()
        // Choisir « Toute la largeur » (ou un côté) fixe le clavier sur cet écran : on le dit, et comment revenir.
        flash(m == .auto ? L("The keyboard follows your hand on this screen.")
                         : L("The keyboard stays put on this screen. To let it follow your hand again, choose Follows your hand."), hold: 3)
    }

    /// Un toucher dans la place libre : à gauche → clavier à gauche, à droite → à droite, au centre → au milieu
    /// (deux moitiés sur le Duo déplié). Pas besoin d'étalonnage.
    private var placeTouches: [UITouch: (CGPoint, TimeInterval)] = [:]
    private var lastKeyTime: TimeInterval = 0
    /// L'appui sur une touche juste avant le dernier (pour reconnaître un micro touché par erreur en pleine frappe).
    private var prevKeyTime: TimeInterval = 0

    private func updateSideHint() {
        if sideHint.superview == nil {
            sideHint.numberOfLines = 0
            sideHint.textAlignment = .center
            sideHint.isUserInteractionEnabled = false
            addSubview(sideHint)
        }
        let lo = blocks.map(\.minX).min() ?? 0, hi = blocks.map(\.maxX).max() ?? bounds.width
        let leftFree = lo - panelRect.minX, rightFree = panelRect.maxX - hi
        guard eff.tapSideToMove, layoutMode.isOneHand, !showEmoji, !adjusting, panelRect.width > 0, max(leftFree, rightFree) > 70 else {
            sideHint.isHidden = true
            return
        }
        let onLeft = leftFree > rightFree
        let free = onLeft ? CGRect(x: panelRect.minX, y: panelRect.minY, width: leftFree, height: panelRect.height)
                          : CGRect(x: hi, y: panelRect.minY, width: rightFree, height: panelRect.height)
        let shown = UserDefaults.standard.integer(forKey: "foldboard.sideHintShown")
        let words = shown < 6
        let arrow = NSAttributedString(string: onLeft ? "‹‹" : "››", attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                                                                                .foregroundColor: theme.text.withAlphaComponent(words ? 0.45 : 0.22)])
        let text = NSMutableAttributedString(attributedString: arrow)
        if words {
            text.append(NSAttributedString(string: "\n" + L("Tap here to move the keyboard"), attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: theme.text.withAlphaComponent(0.45)]))
        }
        sideHint.attributedText = text
        sideHint.frame = free.insetBy(dx: 8, dy: 10)
        if sideHint.isHidden || sideHint.tag != (onLeft ? 1 : 2) {
            sideHint.tag = onLeft ? 1 : 2
            if words { UserDefaults.standard.set(shown + 1, forKey: "foldboard.sideHintShown") }
        }
        sideHint.isHidden = false
        bringSubviewToFront(sideHint)
    }

    /// Captures : la barre ouverte, comme après avoir touché « ⋯ ».
    func demoOpenBar() { barOpened = true; layoutTopBar() }

    private func placeByTap(at p: CGPoint) {
        guard eff.tapSideToMove else { return }
        let W = bounds.width
        // Écran intérieur : le clavier est coupé en deux (ou entier), il n'y a rien à placer.
        guard W > 0, !(settings.mode(for: gripContext) == .auto && !followsHand) else { return }
        let center = abs(p.x - W / 2) < W * 0.17 && layoutMode.isOneHand
        let auto = eff.mode == .auto
        var s = settings
        if center {
            if auto { s.autoTwo = true } else { setScreenMode(pro && splitAllowed ? .split : .full, in: &s) }
            grip.current = .two
        } else {
            let right = p.x > W / 2
            place(right: right, settings: s)
            return
        }
        guard s != settings else { return }
        KBFeedback.shared.tap(sound: .off, haptics: max(0.4, eff.haptics))
        grip.locked = true
        settings = s
        save()
        layoutIfNeeded()
    }

    /// Un coup sur le bord de l'iPhone : le clavier va du côté tapé.
    /// Mesuré sur un vrai Duo (vidéo du 24/11) : le premier pic d'accélération part du côté tapé (la main qui tient
    /// le téléphone le renvoie aussitôt), donc « poussé vers la droite » = bord droit tapé.
    private func knocked(_ pushedRight: Bool) {
        guard visible, eff.knockToMove, layoutMode.isOneHand, !adjusting, tracks.isEmpty,
              !(settings.mode(for: gripContext) == .auto && !followsHand) else { return }
        // L'écran intérieur du Duo a ses axes inversés par rapport à l'écran extérieur (comme pour l'inclinaison).
        var tappedLeft = !pushedRight
        if gripContext.hasPrefix("open") { tappedLeft.toggle() }
        let s = settings
        place(right: !tappedLeft, settings: s)
    }

    /// Met le clavier à une main d'un côté, et retient comment le téléphone est tenu pour ce côté.
    private func place(right: Bool, settings start: KBSettings) {
        var s = start
        let auto = eff.mode == .auto
        do {
            if auto { s.autoTwo = false; s.autoRight = right } else { setScreenMode(right ? .right : .left, in: &s) }
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

    @objc fileprivate func showGripInfo(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let names = ["closed-portrait": L("Closed · portrait"), "open-portrait": L("Open · portrait"),
                     "open-landscape": L("Open · landscape"), "closed-landscape": L("Closed · landscape")]
        let n = settings.taps[gripContext]?.values.filter { $0.count >= 6 }.count ?? 0
        let state = grip.tapModel != nil ? String(format: L("calibrated (%lld grips)"), n)
            : (grip.calibrated ? L("tilt only") : L("not calibrated"))
        let habits = String(format: L("%lld habits learned"), KBHabits.shared.count(context: gripContext))
        flash((names[gripContext] ?? gripContext) + " · " + state + " · " + habits)
    }

    /// Le menu « … » du Duo ouvert : les trois dispositions de cet écran, la bonne cochée (comme chez Apple) :
    /// suivre la main, toute la largeur, coupé en deux. Toujours là, pour changer d'un geste.
    private func openLayoutMenu() -> UIMenu {
        let now = openLayoutChoice
        func item(_ k: Int, _ title: String, _ icon: String) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: icon), state: now == k ? .on : .off) { [weak self] _ in
                self?.chooseOpenLayout(k)
            }
        }
        return UIMenu(children: [item(0, L("Follows your hand"), "hand.raised.fingers.spread"),
                                 item(1, L("Full width"), "keyboard"),
                                 item(2, L("Split keyboard"), "rectangle.split.2x1"),
                                 toolbarButtonsMenu()])
    }

    /// Montrer ou cacher chaque bouton de la barre. Le « … » lui-même se rallume dans l'app
    /// (Position et taille), pour ne pas se retrouver sans menu.
    private func toolbarButtonsMenu() -> UIMenu {
        func item(_ title: String, _ icon: String, _ on: Bool, _ apply: @escaping (inout KBSettings) -> Void) -> UIAction {
            UIAction(title: L(title), image: UIImage(systemName: icon), state: on ? .on : .off) { [weak self] _ in
                guard let self else { return }
                apply(&self.settings)
                self.eff = self.settings.effective(pro: self.pro)
                self.save()
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
        return UIMenu(title: L("Toolbar buttons"), children: [
            item("Position button", "keyboard", settings.showHandButton, { $0.showHandButton.toggle() }),
            item("Settings button", "slider.horizontal.3", settings.showSettingsButton, { $0.showSettingsButton.toggle() }),
            item("Mic button", "mic", settings.showMicButton, { $0.showMicButton.toggle() }),
            item("Clipboard button", "doc.on.clipboard", settings.showClipboardButton, { $0.showClipboardButton.toggle() }),
            item("Hide keyboard button", "keyboard.chevron.compact.down", settings.hideKeyButton, { $0.hideKeyButton.toggle() }),
            item("Switch side", "arrow.left.arrow.right", settings.showSwapButton, { $0.showSwapButton.toggle() }),
            item("Keyboard in the middle", "rectangle.center.inset.filled", settings.showCenterButton, { $0.showCenterButton.toggle() }),
            item("Layout menu", "ellipsis", settings.showLayoutMenu, { $0.showLayoutMenu.toggle() }),
            item("Layout switcher", "rectangle.split.2x1", settings.showLayoutSwitch, { $0.showLayoutSwitch.toggle() }),
            item("More", "ellipsis.circle", settings.showMoreButton, { $0.showMoreButton.toggle() }),
        ])
    }

    /// 0 : suit la main · 1 : toute la largeur · 2 : coupé en deux.
    private var openLayoutChoice: Int {
        switch settings.screenModes[gripContext] {
        case .full?: return 1
        case .split?: return 2
        case nil where settings.mode == .auto:
            if followsHand { return 0 }
            return layoutMode == .split ? 2 : 1
        default: return followsHand ? 0 : (layoutMode == .split ? 2 : 1)
        }
    }

    private func chooseOpenLayout(_ k: Int) {
        guard k != openLayoutChoice else { return }
        if k == 2 && !pro { setMode(.split); return }
        let portrait = gripContext == "open-portrait"
        switch k {
        case 0:
            settings.screenModes[gripContext] = nil
            if settings.mode != .auto { setScreenMode(.auto, in: &settings) }
            if portrait { settings.openSplit = false } else { settings.openLandFollow = true }
        case 1:
            setScreenMode(.full, in: &settings)
        default:
            setScreenMode(.split, in: &settings)
        }
        settings.openFull = false
        applyScreenMode()
        grip.locked = false
        KBFeedback.shared.tap(sound: .off, haptics: max(0.4, eff.haptics))
        save()
        layoutIfNeeded()
    }

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
        case .left: setScreenMode(.right, in: &settings)
        case .right: setScreenMode(.left, in: &settings)
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
        if let sheet = barSheet, !sheet.isHidden {
            sheet.frame = bounds
            bringSubviewToFront(sheet)
        }
        roundForHost()
        guard bounds.size != builtFor, bounds.width > 50 else { return }
        // La charnière envoie plusieurs tailles pendant le pliage. On attend la dernière.
        guard !hingeSettling else { return }
        builtFor = bounds.size
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateGripContext()
            syncSensors()
            rebuild()
            CATransaction.commit()
        }
    }

    private var isRight: Bool {
        eff.mode == .right || (eff.mode == .auto && eff.autoRight)
    }

    /// Deux moitiés seulement sur un écran large : l'écran déplié du Duo (presque carré), ou un iPhone en paysage.
    /// Sur l'écran extérieur ou un iPhone classique en portrait, le clavier reste en pleine largeur.
    private var splitAllowed: Bool {
        bounds.width >= 600 || (gripContext.hasPrefix("open") && bounds.width >= 360)
            || (gripContext == "closed-landscape" && bounds.width >= 480)
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

    /// La main décide vraiment de la place du clavier sur cet écran. Sinon (entier ou deux moitiés choisis pour cet
    /// écran, ou paysage sans « suivre la main »), la détection ne touche à rien : le clavier ne saute plus.
    private var gripMoves: Bool {
        settings.screenModes[gripContext] != nil || settings.mode != .auto || followsHand
    }

    private var layoutMode: KBMode {
        // Écran intérieur du Duo, comme le clavier d'Apple : deux moitiés en portrait, entier en paysage.
        if settings.screenModes[gripContext] == nil && settings.mode == .auto {
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
            text = String(format: L("Key height %lld pt"), Int(screenKeyHeight.rounded()))
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
            // Chaque écran garde sa hauteur : réglée sur l'écran déplié, elle ne change pas celle de l'écran plié.
            if gripContext.hasPrefix("open") {
                s.keyHeightOpen = min(60, max(34, screenKeyHeight - Double(dy) / 4))
            } else {
                s.keyHeight = min(60, max(34, s.keyHeight - Double(dy) / 4))
            }
            applyLive(s, height: true)
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
        applyLive(s, height: false)
    }

    /// Pendant qu'on règle le clavier au doigt : seulement le dessin, au plus 20 fois par seconde, et la hauteur
    /// du clavier demandée à iOS quand le doigt marque une pause. Avant, chaque mouvement du doigt rechargeait tout
    /// le clavier et changeait sa hauteur des dizaines de fois par seconde : iOS finissait par le fermer
    /// (et affichait son clavier anglais à la place).
    private var liveWork: DispatchWorkItem?
    private var heightWork: DispatchWorkItem?
    private var lastLive: TimeInterval = 0
    private func applyLive(_ s: KBSettings, height: Bool) {
        settings = s
        eff = s.effective(pro: pro)
        applyScreenMode()
        let now = ProcessInfo.processInfo.systemUptime
        if liveWork == nil {
            let w = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.liveWork = nil
                self.lastLive = ProcessInfo.processInfo.systemUptime
                self.builtFor = .zero
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.refreshAdjust()
            }
            liveWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.05 - (now - lastLive)), execute: w)
        }
        if height {
            heightWork?.cancel()
            let h = DispatchWorkItem { [weak self] in self?.onPreferredHeightChange?() }
            heightWork = h
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: h)
        }
    }

    private func resetAdjust() {
        var s = settings
        let d = KBSettings()
        s.edgeMargin = d.edgeMargin
        s.oneHandWidth = d.oneHandWidth
        s.oneHandWidthOpen = d.oneHandWidthOpen
        s.splitWidth = d.splitWidth
        if gripContext.hasPrefix("open") { s.keyHeightOpen = 0 } else { s.keyHeight = d.keyHeight }
        adjustingHeight = false
        configure(settings: s, pro: pro)
        onPreferredHeightChange?()
        layoutIfNeeded()
        refreshAdjust()
    }

    private func endAdjust(keep: Bool) {
        liveWork?.cancel(); liveWork = nil
        heightWork?.cancel(); heightWork = nil
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
        emojiBoard.releaseMemory()
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
            tr.cursorMode = false
        }
        if trackpadOn { setTrackpad(false, animated: false) }
        pageSlideGuard()
        hideBubble()
        accentView.isHidden = true
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rebuildKeys(oldBlocks: oldBlocks)
            CATransaction.commit()
        }
    }

    /// « 123 » tenu pendant que les touches changent : la touche survolée n'est plus la même.
    private func pageSlideGuard() {
        if let ps = pageSlide { pageSlide = (ps.touch, nil) }
    }

    /// Un doigt qu'iOS a retiré sans prévenir (clavier masqué ou déplacé en plein appui, geste du système) : son
    /// appui se termine ici, au lieu de rester « enfoncé » (effacement sans fin, pavé tactile bloqué).
    private func sweepLostTouches(_ event: UIEvent?) {
        guard !tracks.isEmpty || !placeTouches.isEmpty || pageSlide != nil else { return }
        let live = event?.allTouches
        func gone(_ t: UITouch) -> Bool {
            if t.phase == .ended || t.phase == .cancelled { return true }
            if t.window == nil || t.view?.isDescendant(of: self) != true { return true }
            if let live, !live.contains(t) { return true }
            return false
        }
        for t in Array(tracks.keys) where gone(t) {
            tracks[t]?.done = true
            finish(t)
        }
        for t in Array(placeTouches.keys) where gone(t) { placeTouches[t] = nil }
        if let ps = pageSlide, gone(ps.touch) { pageSlide = nil }
    }

    private func rebuildKeys(oldBlocks: [CGRect]) {
        // Thème automatique : le fond du clavier de l'iPhone se voit partout, jusqu'aux bords de l'écran.
        // Pas tout à fait transparent : dans les autres apps, iOS ne transmet pas au clavier les appuis tombés sur
        // une zone transparente (entre les touches), et des lettres se perdaient.
        // Thème automatique : fond plein, couleur du clavier d'Apple. Presque transparent, on voyait au travers
        // l'image de l'ancien clavier qu'iOS laisse dessous quand le Duo s'ouvre ou se ferme (claviers superposés).
        backgroundColor = theme.id == "glass" ? UIColor(white: 0, alpha: 0.012) : theme.background
        // Les suggestions de l'écran d'avant ne restent pas (tableaux, pas les vues : elles sont réutilisées).
        suggestionItems = []
        suggestionsWord = ""
        suggestionBest = nil
        cachedFix = nil
        reclaimKeys()
        // La hauteur change avec la disposition (grandes touches du clavier entier) : on la redemande.
        if abs(preferredHeight - reportedHeight) > 0.5 {
            reportedHeight = preferredHeight
            DispatchQueue.main.async { [weak self] in self?.onPreferredHeightChange?() }
        }
        let W = bounds.width
        // Certaines apps (Reddit…) donnent au clavier plus de hauteur que demandé : les touches restent en bas, sous
        // le pouce, au lieu de laisser un grand vide sous la barre d'espace.
        let top = barTop + Self.topBarHeight + 6
        let areaH = CGFloat(rowCount) * keyH + bottomExtra + CGFloat(rowCount - 1) * vgap
        let margin = CGFloat(eff.edgeMargin)
        let rows = KBLayouts.rows(page, layout: eff.layout, numberRow: eff.numberRow)
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
            // Comme le clavier d'Apple : les touches vont presque jusqu'aux bords (plus larges, moins de vide).
            let b = CGRect(x: 0, y: top, width: W, height: areaH)
            blocks = [b]
            panelRect = .zero
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout, emoji: eff.emojiKey, mic: micKey)], in: b, align: 0)
        case .left, .right, .auto:
            let bw = min(W - 2 * pad, max(min(W - 2 * pad, 250), W * oneHandFraction))
            let x = isRight ? W - margin - bw : margin
            let b = CGRect(x: max(0, x), y: top, width: bw, height: areaH)
            blocks = [b]
            panelRect = isRight
                ? CGRect(x: 6, y: top, width: max(0, b.minX - 12), height: areaH)
                : CGRect(x: b.maxX + 6, y: top, width: max(0, W - b.maxX - 12), height: areaH)
            place(rows + [KBLayouts.bottom(page, globe: globe, layout: eff.layout, compact: true, leftHand: !isRight, mic: micKey)], in: b, align: 0)
        case .split:
            // Comme le clavier coupé d'Apple : les moitiés près des bords (la marge du clavier à une main ne compte pas).
            let sm: CGFloat = 2
            let hw = W * CGFloat(eff.splitWidth)
            let l = CGRect(x: sm, y: top, width: hw, height: areaH)
            let r = CGRect(x: W - sm - hw, y: top, width: hw, height: areaH)
            blocks = [l, r]
            // Comme le clavier coupé d'Apple : rien entre les deux moitiés.
            panelRect = .zero
            let (left0, right0) = Self.halves(rows, page: page)
            var left = left0, right = right0
            // Même taille de touches sur toutes les pages (lettres, chiffres, symboles) : les moitiés ne changent plus
            // de taille en passant de ABC à 123.
            func widest(_ rs: [KeyRow]) -> Double { rs.map { $0.keys.reduce(0) { $0 + $1.width } }.max() ?? 5 }
            var maxL = 5.0, maxR = 5.0
            for pg in [KBPage.letters, .numbers, .symbols] {
                let (a, b) = Self.halves(KBLayouts.rows(pg, layout: eff.layout, numberRow: eff.numberRow), page: pg)
                maxL = max(maxL, widest(a)); maxR = max(maxR, widest(b))
            }
            var lb: [KeySpec] = [KeySpec(kind: .page(page == .letters ? .numbers : .letters), width: 1.5)]
            if globe { lb.append(KeySpec(kind: .globe, width: 1.1)) }
            if eff.emojiKey { lb.append(KeySpec(kind: .emoji, width: 1.1)) }
            let used = lb.reduce(0) { $0 + $1.width }
            lb.append(KeySpec(kind: .space, width: max(1.5, maxL - used)))
            left.append(KeyRow(keys: lb))
            right.append(KeyRow(keys: micKey
                ? [KeySpec(kind: .space, width: max(1.5, maxR - 3.1)), KeySpec(kind: .mic, width: 1.1), KeySpec(kind: .ret, width: 2)]
                : [KeySpec(kind: .space, width: max(1.5, maxR - 2)), KeySpec(kind: .ret, width: 2)]))
            place(left, in: l, align: -1, units: maxL)
            place(right, in: r, align: 1, units: maxR)
        }
        rebuildPanel()
        layoutTopBar()
        updateLabels()
        if adjusting { refreshAdjust() }
        slide(from: oldBlocks)
        updateSideHint()
    }

    /// Le micro dans la rangée du bas, à côté de retour (option) : il quitte alors la barre du haut.
    private var micKey: Bool { eff.micByReturn && eff.dictationKey }

    /// Les rangées coupées en deux moitiés (gauche, droite).
    private static func halves(_ rows: [KeyRow], page: KBPage) -> ([KeyRow], [KeyRow]) {
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
            // Chiffres et symboles aussi : le « ? » du milieu de la dernière rangée reste à portée des deux pouces
            // (il avait disparu de la moitié droite).
            if left.count == rows.count - 1, let edge = lk.last, case .char = edge.kind { rk.insert(edge, at: 0) }
            left.append(KeyRow(keys: lk))
            right.append(KeyRow(keys: rk))
        }
        return (left, right)
    }

    /// Le clavier change de côté, revient au milieu ou passe en grand : chaque touche glisse de son ancienne place
    /// à la nouvelle (pas de saut).
    private func slide(from old: [CGRect]) {
        // Mode portable ou charnière en mouvement : pas de glissement. Les touches prennent leur place finale
        // d'un coup, sinon les rangées se croisent pendant le pliage.
        guard !hingeSettling, !hingeHalf else { return }
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
            let rowH = keyH + (i == rows.count - 1 ? bottomExtra : 0)
            for k in row.keys {
                let w = CGFloat(k.width) * unit
                var f = CGRect(x: x + gap / 2, y: y, width: w - gap, height: rowH)
                // ⇧ et ⌫ un peu plus étroits que leur place, comme chez Apple (la zone d'appui reste entière).
                if k.trim != 0 {
                    let t = min(f.width * 0.4, CGFloat(abs(k.trim)) * unit)
                    f.size.width -= t
                    if k.trim < 0 { f.origin.x += t }
                }
                let special: Bool
                switch k.kind {
                case .char: special = false
                case .space: special = false
                default: special = true
                }
                let v = claimKey(spec: k, special: special)
                v.transform = .identity
                v.layer.removeAllAnimations()
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                v.frame = f
                CATransaction.commit()
                let hit = CGRect(x: x, y: y - vgap / 2, width: w, height: rowH + vgap)
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

    /// Touches déjà dessinées, rendues au pot avant de replacer la disposition.
    private var keyPool: [KeyView] = []

    private func reclaimKeys() {
        var pool = keyPool
        for c in cells {
            c.view.park()
            pool.append(c.view)
        }
        keyPool = pool
        cells = []
    }

    /// Reprend une touche existante, ou en dessine une si la disposition en demande plus qu'avant.
    private func claimKey(spec: KeySpec, special: Bool) -> KeyView {
        let v: KeyView
        if let last = keyPool.popLast() {
            v = last
            v.reconfigure(spec: spec, special: special)
        } else {
            v = KeyView(spec: spec, special: special)
            insertSubview(v, belowSubview: bubble)
        }
        if v.superview !== self { insertSubview(v, belowSubview: bubble) }
        return v
    }

    private func layoutTopBar() {
        topBar.frame = CGRect(x: 0, y: barTop, width: bounds.width, height: Self.topBarHeight)
        let h = Self.topBarHeight
        // Clavier d'un côté : la barre (boutons et suggestions) reste au-dessus des touches, à portée du pouce,
        // au lieu de traverser tout l'écran (Duo ouvert).
        let confine = layoutMode.isOneHand && panelRect.width > 0 && !blocks.isEmpty
        let x0 = confine ? (blocks.map { $0.minX }.min() ?? 0) : 0
        let x1 = confine ? (blocks.map { $0.maxX }.max() ?? bounds.width) : bounds.width
        let showPosition = settings.showHandButton
        modeButton.isHidden = !showPosition
        modeButton.frame = CGRect(x: x0 + 6, y: 0, width: showPosition ? 40 : 0, height: h)
        modeButton.setImage(UIImage(systemName: eff.mode.symbol), for: .normal)
        modeButton.tintColor = theme.text.withAlphaComponent(0.7)
        modeButton.menu = modeMenu()
        modeButton.accessibilityLabel = L("Keyboard position")
        // La flèche ⇆ : changer de côté, ou revenir à une main depuis le milieu.
        let oneHand = layoutMode.isOneHand || (eff.mode == .auto && followsHand)
        flipButton.isHidden = !oneHand || !settings.showSwapButton
        // En couleur : le clavier est verrouillé là où tu l'as mis.
        flipButton.tintColor = grip.locked && eff.mode == .auto ? theme.accent : theme.text.withAlphaComponent(0.7)
        flipButton.frame = CGRect(x: modeButton.frame.maxX, y: 0, width: oneHand ? 36 : 0, height: h)
        // Le bouton du milieu : là où le clavier suit la main (il apprend aussi quand on le veut au milieu).
        let middleShown = eff.mode == .auto && followsHand && autoOn && settings.showCenterButton
        middleButton.isHidden = !middleShown
        middleButton.tintColor = settings.autoTwo ? theme.accent : theme.text.withAlphaComponent(0.7)
        middleButton.frame = CGRect(x: flipButton.frame.maxX, y: 0, width: middleShown ? 36 : 0, height: h)
        // Écran intérieur : un bouton pour passer d'une disposition à l'autre.
        // Portrait : petit clavier qui suit la main ⇄ deux moitiés. Paysage : clavier entier ⇄ deux moitiés.
        let open = gripContext.hasPrefix("open")
        let bigShown = open && pro && settings.showLayoutMenu
        bigButton.isHidden = !bigShown
        // Comme le clavier d'Apple sur le Duo ouvert : « … » ouvre un menu avec les deux dispositions, cochée.
        bigButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        bigButton.accessibilityLabel = L("Keyboard position on this screen")
        if layoutSwitch.superview !== topBar { topBar.addSubview(layoutSwitch) }
        bigButton.showsMenuAsPrimaryAction = false
        bigButton.menu = nil
        bigButton.tintColor = theme.text.withAlphaComponent(0.7)
        bigButton.frame = CGRect(x: max(flipButton.frame.maxX, middleButton.frame.maxX), y: 0, width: bigShown ? 36 : 0, height: h)
        hideButton.tintColor = theme.text.withAlphaComponent(0.7)
        let hk = settings.hideKeyButton
        hideButton.isHidden = !hk
        hideButton.frame = CGRect(x: x1 - (hk ? 46 : 6), y: 0, width: hk ? 40 : 0, height: h)
        let showSettings = settings.showSettingsButton
        adjustButton.tintColor = theme.text.withAlphaComponent(0.7)
        adjustButton.isHidden = !showSettings
        adjustButton.frame = CGRect(x: hideButton.frame.minX - (showSettings ? 36 : 0), y: 0, width: showSettings ? 36 : 0, height: h)
        let compact = layoutMode.isOneHand && !showEmoji
        let globe = input?.kbNeedsGlobe ?? false
        let emojiOn = compact && eff.emojiKey
        emojiButton.isHidden = !emojiOn
        globeButton.isHidden = !(compact && globe)
        globeButton.setImage(UIImage(systemName: eff.globeAsEmoji ? "face.smiling" : "globe"), for: .normal)
        emojiButton.tintColor = theme.text.withAlphaComponent(0.7)
        globeButton.tintColor = theme.text.withAlphaComponent(0.7)
        // Le presse-papier : juste à gauche des réglages, partout (sauf quand les emojis sont ouverts).
        let clipShown = settings.showClipboardButton && !showEmoji
        clipButton.isHidden = !clipShown
        clipButton.tintColor = theme.text.withAlphaComponent(0.7)
        clipButton.frame = CGRect(x: adjustButton.frame.minX - (clipShown ? 36 : 0), y: 0, width: clipShown ? 36 : 0, height: h)
        let micShown = eff.dictationKey && settings.showMicButton && !showEmoji && !micKey
        micButton.isHidden = !micShown
        micButton.tintColor = dictState == .idle ? theme.text.withAlphaComponent(0.7) : theme.accent
        micButton.setImage(UIImage(systemName: dictState == .idle ? "mic" : "mic.fill"), for: .normal)
        micButton.frame = CGRect(x: clipButton.frame.minX - (micShown ? 36 : 0), y: 0, width: micShown ? 36 : 0, height: h)
        let fixShown = eff.wandButton && !showEmoji && (input?.kbFullAccess ?? false) && KBWritingFix.available
        fixButton.isHidden = !fixShown
        fixButton.tintColor = fixing ? theme.accent : theme.text.withAlphaComponent(0.7)
        fixButton.frame = CGRect(x: micButton.frame.minX - (fixShown ? 36 : 0), y: 0, width: fixShown ? 36 : 0, height: h)
        let trShown = eff.translateKey && !showEmoji && (input?.kbFullAccess ?? false)
        translateButton.isHidden = !trShown
        translateButton.tintColor = theme.text.withAlphaComponent(0.7)
        translateButton.menu = translateMenu()
        translateButton.frame = CGRect(x: fixButton.frame.minX - (trShown ? 36 : 0), y: 0, width: trShown ? 36 : 0, height: h)
        emojiButton.frame = CGRect(x: translateButton.frame.minX - (emojiOn ? 36 : 0), y: 0, width: emojiOn ? 36 : 0, height: h)
        globeButton.frame = CGRect(x: emojiButton.frame.minX - (compact && globe ? 36 : 0), y: 0, width: compact && globe ? 36 : 0, height: h)
        // Les boutons de position (main, ⇆, milieu, …) à gauche, serrés l'un contre l'autre.
        var lead = [modeButton, flipButton, middleButton, bigButton].filter { !$0.isHidden && $0.frame.width > 0 }
        // Clavier à une main : s'il y a la place à côté des touches (là où sont les flèches ‹‹), les boutons de
        // position y vont, contre le clavier. La barre au-dessus des touches garde toute sa largeur pour les
        // suggestions et les outils.
        // (Trop juste à trois : le bouton du milieu passe derrière « ⋯ ».)
        let roomLeft = x0, roomRight = bounds.width - x1
        func leadWidth() -> CGFloat { lead.reduce(0) { $0 + $1.frame.width } }
        var middleTucked = false
        if confine, sideButtonsGrid == nil, max(roomLeft, roomRight) < leadWidth() + 8,
           let i = lead.firstIndex(of: middleButton), max(roomLeft, roomRight) >= leadWidth() - middleButton.frame.width + 8 {
            lead.remove(at: i); middleButton.isHidden = true; middleButton.frame.size.width = 0
            middleTucked = true
        }
        let leadOutside = confine && sideButtonsGrid == nil && !lead.isEmpty && max(roomLeft, roomRight) >= leadWidth() + 8
        func packLead() -> CGFloat {
            if leadOutside {
                var x = roomLeft >= roomRight ? x0 - 2 - leadWidth() : x1 + 2
                for b in lead { b.frame.origin.x = x; x += b.frame.width }
                return x0 + 6
            }
            var x = x0 + 6
            for b in lead { b.frame.origin.x = x; x += b.frame.width }
            return x + 4
        }
        func drop(_ b: UIButton) {
            guard let i = lead.firstIndex(of: b) else { return }
            lead.remove(at: i); b.isHidden = true; b.frame.size.width = 0
        }
        var cx = packLead()
        moreButton.isHidden = true
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.tintColor = theme.text.withAlphaComponent(0.7)
        if let g = sideButtonsGrid {
            translateButton.isHidden = true
            fixButton.isHidden = true
            // Dans la place libre, en haut, du côté du clavier : 🌐 😀 réglages masquer.
            let buttons: [UIButton] = (globe ? [globeButton] : []) + (eff.emojiKey ? [emojiButton] : []) + (micShown ? [micButton] : []) + (clipShown ? [clipButton] : []) + (showSettings ? [adjustButton] : []) + (hk ? [hideButton] : [])
            let gridW = CGFloat(g.cols) * 44
            let vertical = gripContext == "open-portrait" || gripContext.hasSuffix("landscape")
            // En colonne : contre le clavier (côté pouce), et les boutons répartis sur la hauteur des touches.
            let ox = vertical ? (isRight ? panelRect.maxX - gridW - 6 : panelRect.minX + 6)
                              : (isRight ? panelRect.maxX - gridW : panelRect.minX)
            let step: CGFloat = vertical ? min(56, panelRect.height / CGFloat(g.rows)) : 44
            for (i, b) in buttons.enumerated() {
                b.isHidden = false
                // En colonne, l'ordre se lit de haut en bas, colonne après colonne.
                let col = vertical ? i / g.rows : i % g.cols
                let row = vertical ? i % g.rows : i / g.cols
                // Les boutons sont dans la barre du haut : leur position se compte depuis elle.
                b.frame = CGRect(x: ox + CGFloat(col) * 44, y: panelRect.minY - barTop + CGFloat(row) * step, width: 44, height: step)
            }
            chips.frame = CGRect(x: cx, y: 0, width: max(0, x1 - cx - 6), height: h)
        } else {
            // La barre ne déborde jamais : elle n'a que la largeur du clavier (une main) et chaque bouton garde
            // sa place. Les boutons secondaires (🌐 😀 traduire, corriger, réglages) se rangent derrière « ⋯ »
            // quand il faut de la place ; le presse-papier, le micro et masquer-le-clavier restent visibles.
            let order: [UIButton] = [globeButton, emojiButton, translateButton, fixButton, micButton, clipButton, adjustButton, hideButton]
            let secondary: [UIButton] = [middleButton, globeButton, emojiButton, translateButton, fixButton, adjustButton]
            func width(_ b: UIButton) -> CGFloat { b === hideButton ? 40 : 36 }
            var tools = order.filter { !$0.isHidden && $0.frame.width > 0 }
            if middleTucked { tools.insert(middleButton, at: 0) }
            let span = x1 - x0 - 12
            if barOpened {
                // « ⋯ » ouvert : les outils prennent la place des suggestions, en une rangée régulière, et ✕ revient
                // aux suggestions. S'il n'y a pas la place, les boutons de position attendent la fermeture.
                moreButton.isHidden = false
                moreButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
                let inRow = leadOutside ? [] : lead
                var row = eff.barLayout == "left" ? inRow + tools + [moreButton] : inRow + [moreButton] + tools
                // « ⋯ » (les dispositions de l'écran ouvert) reste le plus longtemps : il remplace la main et le milieu.
                for b in [middleButton, modeButton, flipButton, bigButton] where !leadOutside && CGFloat(row.count) * 36 > span {
                    drop(b); row.removeAll { $0 === b }
                }
                let step = span / CGFloat(max(1, row.count))
                let w = min(44, step)
                for (i, b) in row.enumerated() {
                    b.isHidden = false
                    b.frame = CGRect(x: x0 + 6 + CGFloat(i) * step + (step - w) / 2, y: 0, width: w, height: h)
                }
                chips.frame = CGRect(x: x1, y: 0, width: 0, height: h)
            } else {
                let words = !suggestionItems.isEmpty || emojiQuery != nil
                // La place à garder pour les suggestions : les trois mots en entier si la barre est « rangée »
                // (réglage), sinon au moins de quoi en lire un.
                let wordsMin: CGFloat = !words ? 0 : (eff.compactBar && emojiQuery == nil ? CGFloat(suggestionItems.count) * 78 : 110)
                let leadW: CGFloat = leadOutside ? 0 : leadWidth() + 4
                let toolsW: CGFloat = tools.reduce(0) { $0 + width($1) }
                // Le raccourci des dispositions prend sa place sur les outils, pas sur les mots.
                let switchW: CGFloat = layoutSwitchFits ? Self.layoutSwitchWidth + 8 : 0
                var tucked: [UIButton] = []
                if settings.showMoreButton && (middleTucked || leadW + toolsW + wordsMin + switchW > span) {
                    tucked = tools.filter { secondary.contains($0) }
                    tucked.forEach { $0.isHidden = true }
                }
                var kept = tools.filter { !tucked.contains($0) }
                if !tucked.isEmpty { moreButton.isHidden = false }
                // Encore trop serré (petit clavier, Duo ouvert en portrait) : le bouton du milieu, puis la main, attendent
                // « ⋯ ». Les trois points des dispositions restent, en portrait comme en paysage (demandé par un testeur).
                func needed() -> CGFloat {
                    let a: CGFloat = leadOutside ? 0 : leadWidth() + 4
                    let k: CGFloat = kept.reduce(0) { $0 + width($1) }
                    let m: CGFloat = moreButton.isHidden ? 0 : 36
                    return a + k + m + min(wordsMin, 110) + switchW
                }
                for b in [middleButton, modeButton] where !leadOutside && needed() > span { drop(b) }
                if needed() > span, kept.contains(micButton), micButton.isHidden == false {
                    micButton.isHidden = true; kept.removeAll { $0 === micButton }; moreButton.isHidden = false
                }
                if !leadOutside && needed() > span { drop(bigButton) }
                cx = packLead()
                let more: [UIButton] = moreButton.isHidden ? [] : [moreButton]
                var leftGroup: [UIButton] = [], rightGroup: [UIButton] = []
                switch eff.barLayout {
                case "left":
                    leftGroup = kept + more
                case "split":
                    leftGroup = kept.filter { $0 !== adjustButton && $0 !== hideButton } + more
                    rightGroup = kept.filter { $0 === adjustButton || $0 === hideButton }
                default:
                    rightGroup = more + kept
                }
                var x = cx
                for b in leftGroup { b.frame = CGRect(x: x, y: 0, width: width(b), height: h); x += width(b) }
                var r = x1 - 6
                for b in rightGroup.reversed() { r -= width(b); b.frame = CGRect(x: r, y: 0, width: width(b), height: h) }
                chips.frame = CGRect(x: x + (leftGroup.isEmpty ? 0 : 4), y: 0, width: max(0, r - x - (leftGroup.isEmpty ? 4 : 8)), height: h)
            }
        }
        if !settings.showMoreButton {
            moreButton.isHidden = true
            moreButton.frame.size.width = 0
        }
        // Dernier mot : un interrupteur coupé ne peut pas être rallumé par la mise en page.
        placeLayoutSwitch(barHeight: h)
        enforceVisibility()
        dictLabel.frame = chips.frame
        dictLabel.textColor = theme.text
        dictLabel.backgroundColor = theme.background
        // La dictée a son panneau à la place des touches : la barre garde ses suggestions.
        dictLabel.isHidden = true
        chips.isHidden = false
        if !voice.isHidden { layoutVoice() }

        rebuildChips()
    }

    /// Le bouton « Coller » du système, créé une fois par thème.
    private var pasteControl: UIView?
    private var pasteControlTheme = ""

    private func rebuildChips() {
        let h = Self.topBarHeight
        // Pas de fondu : les mots changent tout de suite, comme sur le clavier d'Apple (le fondu donnait une
        // impression de retard).
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let q = emojiQuery {
            buildSearchChips(q, height: h)
            return
        }
        if !suggestionItems.isEmpty {
            // Trois suggestions de mots, de même largeur ; la meilleure en gras (celle que l'espace appliquera).
            // Un emoji pour le mot (« triste » → 😢) au bout, comme le clavier d'Apple.
            let emoji = suggestionEmoji()
            let ew: CGFloat = emoji.map { CGFloat($0.es.count) * 40 + 12 } ?? 0
            let n = CGFloat(suggestionItems.count)
            let w = max(chips.bounds.width < 240 ? 50 : 60, (chips.bounds.width - ew - (2 * n - 2) * 8 - (n - 1)) / n)
            for (i, item) in suggestionItems.enumerated() {
                let b = UIButton(type: .system)
                b.setTitle(i == 0 && suggestionBest != nil ? "“\(item)”" : item, for: .normal)
                b.titleLabel?.font = eff.font.ui(size: 16, weight: i == suggestionBest ? .bold : .regular)
                b.titleLabel?.lineBreakMode = .byTruncatingTail
                // Un mot long rétrécit un peu avant d'être coupé.
                b.titleLabel?.adjustsFontSizeToFitWidth = true
                b.titleLabel?.minimumScaleFactor = 0.62
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
            if let emoji {
                let line = UIView()
                line.backgroundColor = theme.text.withAlphaComponent(0.18)
                line.widthAnchor.constraint(equalToConstant: 1).isActive = true
                line.heightAnchor.constraint(equalToConstant: 20).isActive = true
                chipStack.addArrangedSubview(line)
                // Tous les emojis du mot, côte à côte (« haha » → 😂 🤣 😆).
                for e in emoji.es {
                    let b = UIButton(type: .system)
                    b.setTitle(e, for: .normal)
                    b.titleLabel?.font = .systemFont(ofSize: 22)
                    b.accessibilityLabel = e
                    let pick = (e: e, replace: emoji.replace)
                    b.addAction(UIAction { [weak self] _ in self?.applyEmojiSuggestion(pick) }, for: .touchUpInside)
                    chipStack.addArrangedSubview(b)
                    b.widthAnchor.constraint(equalToConstant: 32).isActive = true
                    b.heightAnchor.constraint(equalToConstant: 32).isActive = true
                }
            }
            chipStack.frame = CGRect(x: 0, y: (h - 32) / 2, width: w * n + (2 * n - 2) * 8 + (n - 1) + ew, height: 32)
            chips.contentSize = CGSize(width: chipStack.frame.width, height: h)
            chips.contentOffset = .zero
            return
        }
        // Tu viens de copier quelque chose : « Coller » dans la barre, comme sur le clavier d'Apple.
        // Déjà collé autrement (menu d'iOS) : plus de « Coller ».
        let textBefore = String((input?.kbTextBefore() ?? "").suffix(400))
        KBClipboard.shared.dismissIfPasted(before: textBefore)
        let pendingClip = KBClipboard.shared.freshText == nil && KBClipboard.shared.hasPending
        // En plein milieu d'un mot (sans suggestion pour lui), pas de « Coller » : la barre reste calme.
        let midWord = textBefore.last.map { $0.isLetter || $0.isNumber } ?? false
        if !midWord, let t = KBClipboard.shared.freshText ?? (pendingClip ? "" : nil), input?.kbFullAccess == true {
            // Au bout d'une minute, « Coller » s'en va tout seul.
            DispatchQueue.main.asyncAfter(deadline: .now() + KBClipboard.freshLife + 1) { [weak self] in
                guard let self, self.suggestionItems.isEmpty, self.emojiQuery == nil else { return }
                self.rebuildChips()
            }
            // Pas encore lu : le bouton « Coller » du système. iOS le donne aux apps pour coller sans jamais afficher
            // la demande « Autoriser le collage ? » (le texte n'est lu que parce qu'on a touché ce bouton-là).
            if pendingClip, #available(iOS 16.0, *) {
                let cfgP = UIPasteControl.Configuration()
                cfgP.displayMode = .iconAndLabel
                cfgP.cornerStyle = .capsule
                // Le bouton « Coller » du système doit être bien lisible et opaque : translucide, iOS le dessinait
                // parfois comme un simple rectangle bleu, sans texte.
                cfgP.baseBackgroundColor = theme.key.withAlphaComponent(1)
                cfgP.baseForegroundColor = theme.text.withAlphaComponent(1)
                // Un seul bouton, gardé d'une mise à jour de la barre à l'autre : chaque bouton « Coller » est une vue
                // dessinée par iOS hors du clavier, et la barre se refait à chaque mot.
                let pc: UIView
                if let kept = pasteControl, pasteControlTheme == theme.id {
                    pc = kept
                } else {
                    let made = UIPasteControl(configuration: cfgP)
                    made.target = pasteTarget
                    made.heightAnchor.constraint(equalToConstant: 30).isActive = true
                    made.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
                    pasteControl = made
                    pasteControlTheme = theme.id
                    pc = made
                }
                chipStack.addArrangedSubview(pc)
            } else {
            let b = UIButton(type: .system)
            var cfg = UIButton.Configuration.plain()
            let one = t.replacingOccurrences(of: "\n", with: " ")
            // Pas encore lu (pour ne pas déclencher la demande d'iOS) : simplement « Coller ».
            cfg.title = pendingClip ? L("Paste") : (one.count > 22 ? String(one.prefix(22)) + "…" : one)
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
                if pendingClip {
                    if let text = KBClipboard.shared.readPending() { self.pasteClip(text) }
                } else {
                    self.pasteClip(t)
                }
                self.rebuildChips()
            }, for: .touchUpInside)
            chipStack.addArrangedSubview(b)
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            }
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

    /// Poser l'index sans que le contrôle croie que c'est un doigt (sinon il change la disposition tout seul).
    private var switchProgrammatic = false

    /// Le raccourci des trois dispositions (suit la main, toute la largeur, coupé en deux).
    /// Il n'apparaît que là où il a toute sa place à côté de trois suggestions : sur le clavier entier ou coupé de
    /// l'écran déplié. Jamais écrasé ni posé sur les mots : serré contre « masquer le clavier », il ne restait de lui
    /// qu'un carré bleu sans rien dedans, pris pour une touche apparue par erreur. Sur le petit clavier à une main,
    /// le « … » propose les mêmes trois dispositions.
    private static let layoutSwitchWidth: CGFloat = 132
    private var switchStyledFor = ""

    private var layoutSwitchFits: Bool {
        let open = gripContext.hasPrefix("open")
        guard settings.showLayoutSwitch, !settings.layoutSwitchOpenOnly || open, !showEmoji, !barOpened else { return false }
        // La largeur de la barre (pas celle des suggestions, qui change à chaque mot) : il ne clignote pas.
        let confine = layoutMode.isOneHand && panelRect.width > 0 && !blocks.isEmpty
        let span = confine ? (blocks.map(\.maxX).max() ?? bounds.width) - (blocks.map(\.minX).min() ?? 0) : bounds.width
        return span >= 560
    }

    private func placeLayoutSwitch(barHeight h: CGFloat) {
        let w = Self.layoutSwitchWidth
        let show = layoutSwitchFits && chips.frame.width >= w + 60
        layoutSwitch.isHidden = !show
        layoutSwitch.alpha = show && !trackpadOn ? 1 : 0
        layoutSwitch.isUserInteractionEnabled = show
        guard show else {
            layoutSwitch.frame = .zero
            return
        }
        layoutSwitch.frame = CGRect(x: chips.frame.maxX - w, y: (h - 30) / 2, width: w, height: 30)
        chips.frame.size.width = max(0, chips.frame.width - w - 8)
        if layoutSwitch.selectedSegmentIndex != openLayoutChoice {
            switchProgrammatic = true
            layoutSwitch.selectedSegmentIndex = openLayoutChoice
            switchProgrammatic = false
        }
        // L'habillage une fois par thème (le contrôle redessine ses images à chaque changement).
        if switchStyledFor != theme.id {
            switchStyledFor = theme.id
            layoutSwitch.selectedSegmentTintColor = theme.accent
            layoutSwitch.backgroundColor = theme.key.withAlphaComponent(0.55)
            for i in 0..<layoutSwitch.numberOfSegments { layoutSwitch.setWidth(w / 3, forSegmentAt: i) }
            layoutSwitch.tintColor = theme.text
            layoutSwitch.accessibilityLabel = L("Keyboard position")
        }
        if topBar.subviews.last !== layoutSwitch { topBar.bringSubviewToFront(layoutSwitch) }
    }

    /// Un réglage coupé reste coupé, même si une branche de la mise en page a réaffiché le bouton.
    private func enforceVisibility() {
        func hide(_ b: UIButton) {
            b.isHidden = true
            b.frame.size.width = 0
        }
        if !eff.emojiKey { hide(emojiButton) }
        if !settings.showHandButton { hide(modeButton) }
        if !settings.showSettingsButton { hide(adjustButton) }
        if !settings.showSwapButton { hide(flipButton) }
        if !settings.showCenterButton { hide(middleButton) }
        if !settings.showLayoutMenu { hide(bigButton) }
        if !settings.showMoreButton { hide(moreButton) }
        if !settings.showMicButton || !eff.dictationKey { hide(micButton) }
        if !settings.showClipboardButton { hide(clipButton) }
        if !settings.hideKeyButton { hide(hideButton) }
        if (input?.kbNeedsGlobe ?? false) == false { hide(globeButton) }
        if !layoutSwitchFits {
            layoutSwitch.isHidden = true
            layoutSwitch.alpha = 0
            layoutSwitch.isUserInteractionEnabled = false
            layoutSwitch.frame = .zero
        }
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
        // Pour améliorer la détection de la main : copier le journal des prises (sans le texte tapé) et l'envoyer.
        if (input?.kbFullAccess ?? false), KBGripLog.shared.count >= 50 {
            extra.append(UIAction(title: L("Copy hand data for the developer"), image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                guard let self else { return }
                KBGripLog.shared.flush()
                let l = KBVault.loadLearn()
                let info = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                            "hits": "\(l.hits ?? 0)", "misses": "\(l.misses ?? 0)", "calibrated": "\(self.settings.taps.keys.sorted())",
                            "memMB": String(format: "%.0f", Self.footprintMB()), "memPeakMB": String(format: "%.0f", Self.memoryPeak),
                            "memLog": KBMemLog.lines.joined(separator: " | ")]
                if let text = KBGripLog.shared.exportText(extra: info) {
                    UIPasteboard.general.string = text
                    self.notice(L("Copied. Paste it in a message to the developer."))
                }
            })
        }
        if gripContext == "open-portrait" {
            // Duo ouvert en portrait : l'utilisateur choisit entre deux moitiés et le petit clavier qui suit la main.
            extra.insert(UIAction(title: L("Split when the Duo is open"), image: UIImage(systemName: "rectangle.split.2x1"),
                                  state: settings.openSplit ? .on : .off) { [weak self] _ in
                guard let self else { return }
                if !self.pro && !self.settings.openSplit { self.setMode(.split); return }
                self.settings.openSplit.toggle()
                self.settings.mode = .auto
                self.settings.screenModes[self.gripContext] = nil
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
                self.settings.screenModes[self.gripContext] = nil
                self.grip.locked = false
                self.save()
                self.updateGripContext()
                self.layoutIfNeeded()
            }, at: 0)
        }
        extra.append(toolbarButtonsMenu())
        // Le choix ne vaut que pour cet écran (fermé, ouvert en portrait, en paysage) : on le dit dans le titre.
        return UIMenu(title: L("Keyboard position on this screen"), children: [UIMenu(options: .displayInline, children: actions)] + extra)
    }

    /// Clavier d'un côté : les boutons 🌐 😀 réglages et masquer passent dans la place libre à côté du clavier,
    /// pour laisser toute la barre du haut aux suggestions (on voit les mots même tenu d'une main).
    private var sideButtonsGrid: (cols: Int, rows: Int, count: Int)? {
        guard layoutMode.isOneHand, !showEmoji, !adjusting, panelRect.width >= 44, panelRect.height >= 132 else { return nil }
        let n = (settings.showClipboardButton ? 1 : 0) + (settings.showSettingsButton ? 1 : 0) + (settings.hideKeyButton ? 1 : 0) + ((input?.kbNeedsGlobe ?? false) ? 1 : 0) + (eff.emojiKey ? 1 : 0)
            + (eff.dictationKey && settings.showMicButton ? 1 : 0)
        guard n > 0 else { return nil }
        // Duo ouvert en portrait : une colonne verticale collée au clavier, à portée du pouce
        // (une rangée tout en haut de la place libre était trop loin).
        // Les touches ne font qu'environ 170 pt de haut : boutons resserrés (32 pt mini), sur deux colonnes s'il le faut.
        // Paysage : la place libre est large et basse, une rangée horizontale dépasse des touches.
        // Une colonne, comme en portrait ouvert.
        let stacked = gripContext.hasSuffix("landscape") || gripContext == "open-portrait"
        if stacked, panelRect.height >= 32 {
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
        if let a = Self.active, a !== self, a.window != nil, a.visible { return nil }
        // Les touches ne correspondent plus à la taille du clavier (l'écran a changé) : on les range avant l'appui.
        if bounds.size != builtFor, bounds.width > 50 { setNeedsLayout(); layoutIfNeeded() }
        // Tout appui (touches, globe, barre) suspend la lecture de l'inclinaison : atteindre le globe dans un coin
        // fait pencher le téléphone, ce n'est pas un changement de main.
        if event?.type == .touches, gripStarted { grip.noteActivity() }
        if sideButtonsGrid != nil, !isHidden, isUserInteractionEnabled {
            let q = convert(point, to: topBar)
            for b in [globeButton, emojiButton, micButton, clipButton, adjustButton, hideButton] where !b.isHidden && b.alpha > 0.01 && b.frame.contains(q) {
                return b
            }
        }
        return super.hitTest(point, with: event)
    }

    /// Boutons du côté, dessinés une fois et réécrits (un pli ne les recrée pas).
    private var panelButtons: [UIButton] = []
    private var panelHints: [UIImageView] = []
    private var panelUse = 0
    private var hintUse = 0
    private var panelEmoji: [ObjectIdentifier: String] = [:]
    private var panelPhrase: [ObjectIdentifier: String] = [:]

    private func claimPanelButton() -> UIButton {
        let b: UIButton
        if panelUse < panelButtons.count {
            b = panelButtons[panelUse]
        } else {
            b = UIButton(type: .custom)
            b.addAction(UIAction { [weak self, weak b] _ in
                guard let self, let b else { return }
                let id = ObjectIdentifier(b)
                if let e = self.panelEmoji[id] { self.insertEmoji(e) }
                else if let p = self.panelPhrase[id] { self.insertPhrase(p) }
            }, for: .touchUpInside)
            panel.addSubview(b)
            panelButtons.append(b)
            KBViews.panels += 1
        }
        panelUse += 1
        b.isHidden = false
        let id = ObjectIdentifier(b)
        panelEmoji[id] = nil
        panelPhrase[id] = nil
        return b
    }

    private func claimHint(_ symbol: String) -> UIImageView {
        let v: UIImageView
        if hintUse < panelHints.count {
            v = panelHints[hintUse]
        } else {
            v = UIImageView()
            v.contentMode = .center
            v.isUserInteractionEnabled = false
            panel.addSubview(v)
            panelHints.append(v)
            KBViews.panels += 1
        }
        hintUse += 1
        v.isHidden = false
        v.image = KBSymbol.image(symbol)
        v.tintColor = theme.text.withAlphaComponent(0.22)
        return v
    }

    private func parkPanelExtras() {
        for b in panelButtons.dropFirst(panelUse) {
            b.isHidden = true
            b.setTitle(nil, for: .normal)
            b.setImage(nil, for: .normal)
            panelEmoji[ObjectIdentifier(b)] = nil
            panelPhrase[ObjectIdentifier(b)] = nil
        }
        for v in panelHints.dropFirst(hintUse) {
            v.isHidden = true
            v.image = nil
        }
    }

    private func rebuildPanel() {
        panelUse = 0
        hintUse = 0
        panelEmoji.removeAll(keepingCapacity: true)
        panelPhrase.removeAll(keepingCapacity: true)
        var area = panelRect
        if let g = sideButtonsGrid {
            if gripContext == "open-portrait" || gripContext.hasSuffix("landscape") {
                // La colonne de boutons longe le clavier : le reste de la place libre est à côté.
                let side = CGFloat(g.cols) * 44 + 12
                area = CGRect(x: isRight ? area.minX : area.minX + side, y: area.minY, width: max(0, area.width - side), height: area.height)
            } else {
                let top = CGFloat(g.rows) * 44 + 6
                area = CGRect(x: area.minX, y: area.minY + top, width: area.width, height: area.height - top)
            }
        }
        panel.frame = area
        guard area.width >= 44, area.height >= 44, eff.sidePanel != .none else { parkPanelExtras(); return }
        let w = area.width
        let h = area.height
        if layoutMode.isOneHand {
            // Comme le clavier d'Apple sur le Duo : les emojis au bord de l'écran ; un toucher dans la place libre
            // envoie le clavier de ce côté, ou au milieu près du centre.
            let cell: CGFloat = 44
            // Écran étroit : pas d'emojis sur le côté, toute la place libre sert à placer le clavier.
            var cols = w >= 170 ? 2 : (w >= 110 ? 1 : 0)
            let rowsN = max(1, min(4, Int(h / cell)))
            // Place pour un ou deux emojis seulement (sous les boutons) : rien plutôt qu'un emoji isolé.
            if cols * rowsN < 3 { cols = 0 }
            var list = KBEmoji.recent
            for e in eff.emojis where !list.contains(e) { list.append(e) }
            let count = min(list.count, cols * rowsN)
            let gridW = cell * CGFloat(cols)
            let gridH = cell * CGFloat(rowsN)
            let ox = isRight ? 2 : w - gridW - 2
            let oy = max(0, (h - gridH) / 2)
            for i in 0..<count {
                let e = list[i]
                let b = claimPanelButton()
                panelEmoji[ObjectIdentifier(b)] = e
                b.setTitle(e, for: .normal)
                b.setImage(nil, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 28)
                b.frame = CGRect(x: ox + CGFloat(i % cols) * cell, y: oy + CGFloat(i / cols) * cell, width: cell, height: cell)
            }
            // Indices discrets : flèches vers ce côté, et le milieu près du centre.
            let freeW = w - gridW - 4
            if freeW >= 36 {
                let hint = claimHint(isRight ? "chevron.left.2" : "chevron.right.2")
                let fx = isRight ? gridW + 4 : 0
                hint.frame = CGRect(x: fx, y: 0, width: freeW, height: h)
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
                let b = claimPanelButton()
                panelEmoji[ObjectIdentifier(b)] = e
                b.setTitle(e, for: .normal)
                b.setImage(nil, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: min(30, cell * 0.6))
                b.frame = CGRect(x: ox + CGFloat(i % cols) * cell, y: oy + CGFloat(i / cols) * cell, width: cell, height: cell)
            }
        } else if eff.sidePanel == .phrases {
            let bh: CGFloat = 36
            let n = min(eff.phrases.count, max(1, Int((h + 6) / (bh + 6))))
            for i in 0..<n {
                let p = eff.phrases[i]
                let b = claimPanelButton()
                panelPhrase[ObjectIdentifier(b)] = p
                b.setTitle(p, for: .normal)
                b.setImage(nil, for: .normal)
                b.titleLabel?.font = eff.font.ui(size: 14, weight: .medium)
                b.titleLabel?.lineBreakMode = .byTruncatingTail
                b.setTitleColor(theme.text, for: .normal)
                b.backgroundColor = theme.key
                b.layer.cornerRadius = 10
                b.frame = CGRect(x: 0, y: CGFloat(i) * (bh + 6), width: w, height: bh)
            }
        }
        parkPanelExtras()
    }

    /// Le signe de la touche retour d'après le champ ; nil : le retour habituel, discret.
    static func returnSymbol(_ t: UIReturnKeyType) -> String? {
        switch t {
        case .search, .google, .yahoo: return "magnifyingglass"
        case .go, .route, .join, .continue: return "arrow.right"
        case .send: return "arrow.up"
        case .done: return "checkmark"
        default: return nil
        }
    }

    private var shownReturnType: UIReturnKeyType = .default

    private func updateLabels() {
        shownReturnType = input?.kbReturnType ?? .default
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
                v.icon.image = KBSymbol.image(shift == .caps ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"))
                if shift != .off { v.backgroundColor = theme.key }
            case .backspace:
                v.icon.image = KBSymbol.image("delete.left")
            case .space:
                v.label.text = nil
            case .ret:
                v.icon.image = KBSymbol.image("return")
                // Comme le clavier d'Apple : dans un champ de recherche (Safari, Siri…), la touche devient bleue avec
                // une loupe ; « aller », « envoyer », « terminé » aussi, chacun avec son signe.
                let rt = input?.kbReturnType ?? .default
                if let sym = Self.returnSymbol(rt) {
                    v.icon.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
                    v.backgroundColor = .systemBlue
                    v.icon.tintColor = .white
                } else if ["auto", "cloud", "night"].contains(theme.id) {
                    v.backgroundColor = theme.special
                } else {
                    v.backgroundColor = theme.accent
                    v.icon.tintColor = .white
                }
            case .page(let p):
                v.label.text = p == .letters ? "ABC" : (p == .numbers ? "123" : "#+=")
                v.label.font = eff.font.ui(size: 17, weight: .regular)
            case .globe:
                v.icon.image = KBSymbol.image(eff.globeAsEmoji ? "face.smiling" : "globe")
            case .emoji:
                v.icon.image = KBSymbol.image("face.smiling")
            case .mic:
                v.icon.image = KBSymbol.image(dictState == .idle ? "mic" : "mic.fill")
                if dictState != .idle { v.icon.tintColor = theme.accent }
            }
            // Verre : des touches vraiment transparentes, avec un liseré de lumière (comme le verre d'iOS).
            if theme.id == "glass" {
                v.layer.borderWidth = 0.75
                v.layer.borderColor = UIColor.white.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.28 : 0.6).cgColor
                v.layer.shadowOpacity = 0
            } else {
                v.layer.borderWidth = 0
                v.layer.shadowOpacity = 0.08
            }
            v.square = eff.squareKeys
            v.setNeedsLayout()
        }
    }

    // MARK: Touchers


    private func cellIndex(at raw: CGPoint) -> Int? {
        // Le pouce touche un peu plus bas qu'il ne vise (comme le clavier d'Apple, on compense de 4 pt).
        let base = CGPoint(x: raw.x, y: raw.y - 4)
        // D'abord la touche réellement dessinée sous le doigt pendant une animation (le clavier qui glisse d'un côté
        // à l'autre) ; la touche dont le centre est le plus près, pas la première trouvée (les touches étirées se
        // chevauchent pendant le glissement).
        if cells.contains(where: { !($0.view.layer.animationKeys() ?? []).isEmpty }) {
            let hits = cells.indices.filter { (cells[$0].view.layer.presentation()?.frame ?? cells[$0].view.frame).contains(raw) }
            if let i = hits.min(by: {
                let a = cells[$0].view.layer.presentation()?.frame ?? cells[$0].view.frame
                let b = cells[$1].view.layer.presentation()?.frame ?? cells[$1].view.frame
                return hypot(a.midX - raw.x, a.midY - raw.y) < hypot(b.midX - raw.x, b.midY - raw.y)
            }) { return i }
        }
        // Un doigt posé franchement sur une touche écrit cette touche, quoi que le clavier ait appris : l'apprentissage
        // ne décide que près des bords (avant, toute la zone se décalait d'un tiers de touche au plus, effacer et les
        // lettres du bord comprises : viser « P » pouvait écrire « O »).
        if let i = cells.firstIndex(where: { $0.frame.insetBy(dx: $0.frame.width * 0.2, dy: $0.frame.height * 0.12).contains(base) }) {
            return i
        }
        func isLetter(_ i: Int) -> Bool {
            if case .char(let c) = cells[i].view.spec.kind { return c.count == 1 && c.first?.isLetter == true }
            return false
        }
        let plain = cells.firstIndex(where: { $0.hit.contains(base) })
        // Une fois appris où tu tapes vraiment, la frontière entre deux lettres se décale d'autant.
        if eff.tapLearn, page == .letters, let s = tapMap.shift(twoHands: !layoutMode.isOneHand),
           let k = cells.first(where: { if case .char = $0.view.spec.kind { return true }; return false }) {
            let p = CGPoint(x: raw.x - CGFloat(s.dx) * k.frame.width, y: raw.y - CGFloat(s.dy) * k.frame.height)
            // Entre deux lettres seulement : effacer, majuscule, retour et espace gardent leur place exacte.
            if let i = cells.firstIndex(where: { $0.hit.contains(p) }), isLetter(i), plain.map(isLetter) ?? true { return i }
        }
        // La barre d'espace touchée plus haut que son centre : sa zone d'appui monte un peu dans la rangée du dessus.
        if eff.tapLearn, page == .letters, tapMap.spaceRaise > 0 {
            for (i, c) in cells.enumerated() {
                guard case .space = c.view.spec.kind else { continue }
                let up = CGFloat(tapMap.spaceRaise) * c.frame.height
                if base.x >= c.hit.minX, base.x <= c.hit.maxX, base.y >= c.hit.minY - up, base.y < c.hit.minY { return i }
            }
        }
        if let plain { return plain }
        // Juste à côté du clavier : la touche la plus proche (un appui un peu à côté écrit quand même).
        guard blocks.contains(where: { $0.insetBy(dx: -18, dy: -10).contains(base) }) else { return nil }
        var best: (Int, CGFloat)?
        for (i, c) in cells.enumerated() {
            let d = hypot(c.frame.midX - base.x, c.frame.midY - base.y)
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
        // La mesure de fluidité tient le clavier par un lien faible : avant, elle le gardait en vie (et tournait à
        // chaque image) quand iOS jetait le clavier sans prévenir. Sur le Duo, chaque clavier jeté restait en
        // mémoire : 50 Mo au départ, plus de 100 Mo après quelques changements d'app ou de globe.
        let l = CADisplayLink(target: KBWeakTarget(self), selector: #selector(KBWeakTarget.tick(_:)))
        l.add(to: .main, forMode: .common)
        perfLink = l
    }

    @objc fileprivate func perfTick(_ l: CADisplayLink) {
        if perfLast > 0, l.timestamp - perfLast > 0.05 { perfStalls += 1 }
        perfLast = l.timestamp
    }

    private func perfPush(_ a: inout [Double], _ v: Double) {
        a.append(v)
        if a.count > 60 { a.removeFirst() }
    }

    @objc fileprivate func showPerf(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        func avg(_ a: [Double]) -> Int { a.isEmpty ? 0 : Int(a.reduce(0, +) / Double(a.count)) }
        let text = String(format: "Appui %d ms (max %d) · traitement %d ms · blocages %d · annulés %d · à côté %d",
                          avg(perfDelay), Int(perfDelay.max() ?? 0), avg(perfWork), perfStalls, perfCancelled, perfMissed)
            + " · L\(Int(bounds.width)) · " + lastHits.joined(separator: " ")
            + String(format: " · mémoire %.0f Mo (max %.0f)", Self.footprintMB(), Self.memoryPeak)
        flash(text)
        perfDelay = []; perfWork = []; perfStalls = 0; perfCancelled = 0; perfMissed = 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        idleTimer?.invalidate()
        sweepLostTouches(event)
        let w0 = ProcessInfo.processInfo.systemUptime
        if let t = touches.first { perfPush(&perfDelay, (w0 - t.timestamp) * 1000) }
        defer { perfPush(&perfWork, (ProcessInfo.processInfo.systemUptime - w0) * 1000) }
        if let t = touches.first { knock.lastTouch = t.timestamp }
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
            tr.touch = t
            if recording != nil { halo(at: p, radius: t.majorRadius) }
            tr.points = [p]
            tr.times = [t.timestamp]
            if autoOn, layoutMode.isOneHand, case .char(let c) = cells[i].view.spec.kind, c.count == 1, c.first?.isLetter == true {
                let f = cells[i].frame
                let lo = blocks.map { $0.minX }.min() ?? 0
                let hi = blocks.map { $0.maxX }.max() ?? bounds.width
                KBThumb.shared.tap(kx: Double((f.midX - lo) / max(1, hi - lo)), dx: Double((p.x - f.midX) / max(1, f.width)),
                                   radius: Double(t.majorRadius), time: t.timestamp)
                // Et comment le téléphone a bougé sous l'appui (connu un quart de seconde après).
                let ts = t.timestamp
                var e: [String: Double] = ["ts": ts, "kx": Double((f.midX - lo) / max(1, hi - lo)),
                                           "dx": Double((p.x - f.midX) / max(1, f.width)), "dy": Double((p.y - f.midY) / max(1, f.height)),
                                           "r": Double(t.majorRadius), "side": settings.autoTwo ? 2 : (settings.autoRight ? 1 : 0)]
                if let q = grip.currentPosture { e["roll"] = q.roll; e["inc"] = q.incline }
                KBGripLog.shared.add(1, context: gripContext, e)
                let ctx = gripContext
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                    if let k = self?.grip.kick(at: ts) {
                        KBThumb.shared.kick(time: ts, k)
                        KBGripLog.shared.add(2, context: ctx, ["ts": ts, "x": k.x, "y": k.y, "z": k.z])
                    }
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
            if tr.points.count < (tr.glide ? 600 : 80) {
                tr.points.append(p)
                tr.times.append(t.timestamp)
            }
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
                if tr.cursorMode, var map = trackMap {
                    // Comme chez Apple : le curseur suit le doigt dans tous les sens, sans à-coups. La vitesse est lissée
                    // (un geste lent avance lettre par lettre, un geste rapide va plus loin), et ce qui dépasse un bord
                    // est oublié : en revenant, le curseur repart tout de suite, sans zone morte.
                    let mdx = p.x - tr.lastX, mdy = p.y - tr.lastY
                    let dt = tr.lastT > 0 ? max(0.004, t.timestamp - tr.lastT) : 0.016
                    tr.lastX = p.x; tr.lastY = p.y; tr.lastT = t.timestamp
                    let inst = hypot(mdx, mdy) / CGFloat(dt)          // points par seconde
                    tr.cursorSpeed = tr.cursorSpeed == 0 ? inst : tr.cursorSpeed * 0.7 + inst * 0.3
                    let gain = min(3, 1 + max(0, tr.cursorSpeed - 160) / 420)
                    // Réglage « Sensibilité » : de 11 pt par lettre (lent) à 6 pt (rapide) ; une ligne tous les 22 pt.
                    let charStep = 11 - 5 * CGFloat(eff.swipe)
                    let lineStep: CGFloat = 22
                    // Un geste presque horizontal ne change pas de ligne par mégarde.
                    let vy: CGFloat = abs(mdy) > abs(mdx) * 0.5 ? 1 : 0.6
                    tr.cursorAccum += mdx * gain / charStep
                    // Vers le bas, le pouce n'a que la hauteur sous la barre d'espace : chaque point compte plus
                    // (on descend autant qu'on monte), et au bord bas le curseur continue de lui-même (trackEdge).
                    tr.cursorAccumY += mdy * gain * vy * (mdy > 0 ? 1.7 : 1) / lineStep
                    // Pendant qu'on relit le texte autour du curseur, le geste s'accumule et repart juste après.
                    if tr.reanchoring { continue }
                    let start = map.current
                    var lineMoved = false
                    var edge = false
                    var edgeDir = 0
                    while abs(tr.cursorAccumY) >= 1 {
                        let d = tr.cursorAccumY > 0 ? 1 : -1
                        if map.moveV(d) {
                            tr.cursorAccumY -= CGFloat(d)
                            lineMoved = true
                        } else {
                            tr.cursorAccumY = 0
                            edge = true
                            edgeDir = d
                        }
                    }
                    let n = Int(tr.cursorAccum.rounded(.towardZero))
                    if n != 0 {
                        let moved = map.moveH(n)
                        tr.cursorAccum -= CGFloat(n)
                        if moved != n {
                            tr.cursorAccum = 0
                            if (n < 0 && map.atStart) || (n > 0 && map.atEnd) { edge = true; edgeDir = n < 0 ? -1 : 1 }
                        }
                    }
                    trackMap = map
                    let delta = map.current - start
                    if delta != 0 {
                        input?.kbMoveCursor(delta)
                        if lineMoved { KBFeedback.shared.tap(sound: .off, haptics: eff.haptics * 0.35) }
                    }
                    // iOS ne donne au clavier que quelques lignes autour du curseur : arrivé au bout de ce texte,
                    // on relit ce qu'il y a autour du nouveau curseur et on continue (comme chez Apple, jusqu'en haut).
                    if edge && t.timestamp - tr.lastAnchor > 0.25 {
                        tr.reanchoring = true
                        tr.lastAnchor = t.timestamp
                        let goal = map.goalCol, perLine = map.perLine
                        // Au bout du texte qu'iOS a donné (souvent un seul paragraphe, ou quelques lignes) : un pas de
                        // plus, par-dessus le retour à la ligne, puis on relit. On remonte ainsi jusqu'en haut d'une
                        // longue note, comme avec le clavier d'Apple.
                        let atBorder = (edgeDir < 0 && map.para == 0) || (edgeDir > 0 && map.para == map.paras.count - 1)
                        if atBorder, edgeDir != 0 {
                            let toBorder = edgeDir < 0 ? -map.off : map.paras[map.para].len - map.off
                            input?.kbMoveCursor(toBorder + edgeDir)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak tr] in
                            guard let self, let tr, tr.cursorMode else { return }
                            var m = TrackMap(before: self.input?.kbTextBefore() ?? "", after: self.input?.kbTextAfter() ?? "", perLine: perLine)
                            m.goalCol = goal
                            self.trackMap = m
                            tr.reanchoring = false
                        }
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
                if t.timestamp - t0 < 0.4, hypot(p.x - p0.x, p.y - p0.y) < 18, t.majorRadius < 38, away,
                   tracks.isEmpty, t.timestamp - lastKeyTime > 0.35, panelRect.contains(p) {
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
        let kw = letterKeyWidth
        let dx = p.x - tr.start.x, dy = p.y - tr.start.y
        // Le trait démarre tôt même sur les grandes touches (clavier entier sur l'écran déplié), mais jamais sur un
        // simple roulement du pouce : en appuyant au bord d'une touche, le doigt glisse de quelques points sur la
        // voisine (« P » écrivait « op »). Il faut un vrai déplacement, et être entré dans l'autre touche.
        guard abs(dx) > min(kw * 0.95, max(40, kw * 0.6)) || hypot(dx, dy) > min(kw * 1.6, max(64, kw * 0.9)) else { return false }
        // Arrivé sur une autre lettre, franchement (pas juste sur la bordure entre les deux).
        guard let j = cellIndex(at: p), j != tr.index, case .char(let c2) = cells[j].view.spec.kind, c2.first?.isLetter == true else { return false }
        let f = cells[j].frame
        return f.insetBy(dx: min(8, f.width * 0.12), dy: 0).contains(CGPoint(x: p.x, y: f.midY)) || hypot(dx, dy) > kw * 1.25
    }

    /// La largeur d'une touche de lettre (les seuils du glisser en dépendent).
    private var letterKeyWidth: CGFloat {
        cells.first { if case .char(let c) = $0.view.spec.kind { return c.count == 1 && c.first?.isLetter == true }; return false }?.frame.width ?? 32
    }

    private func startGlide(_ tr: Track) {
        tr.glide = true
        tr.longTimer?.invalidate()
        hideBubble()
        setPressed(tr.index, false)
        if tr.typed != nil {
            input?.kbDelete()
            if !wordTouches.isEmpty { wordTouches.removeLast() }
            tr.glideUndo = tr.typed
            tr.typed = nil
            // La lettre effacée avait consommé la majuscule : on la rend au mot tracé.
            if tr.shiftAtDown == .on && shift == .off {
                shift = .on
                autoShifted = tr.autoShiftAtDown
                updateLabels()
            }
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
        // Un tracé qui tient dans une seule touche n'est pas un mot : le pouce a roulé d'une touche sur sa voisine
        // en appuyant. La lettre du départ revient, comme un appui normal.
        var travelled: CGFloat = 0
        for (a, b) in zip(tr.points, tr.points.dropFirst()) { travelled += hypot(b.x - a.x, b.y - a.y) }
        if travelled < letterKeyWidth * 0.8, let letter = tr.glideUndo {
            tr.glideUndo = nil
            typeText(letter)
            noteTouch(letter, at: tr.start)
            return
        }
        // Les centres des touches, comme pour la correction.
        var centers: [Character: [CGPoint]] = [:]
        var keyW: CGFloat = 0, keyH: CGFloat = 0
        for c in cells {
            guard case .char(let s) = c.view.spec.kind, s.count == 1, let ch = s.lowercased().first, ch.isLetter else { continue }
            centers[ch, default: []].append(CGPoint(x: c.frame.midX, y: c.frame.midY))
            keyW = max(keyW, c.frame.width); keyH = max(keyH, c.frame.height)
        }
        var model = KBTouchModel(points: [], centers: centers, keyW: keyW, keyH: keyH)
        model.canvas = bounds.size
        var before = input?.kbTextBefore() ?? ""
        let found = suggest.glide(tr.points, touch: model, before: before + " ", times: tr.times)
        guard var word = found.first else {
            KBFeedback.shared.tap(sound: .off, haptics: eff.haptics * 0.6)
            return
        }
        // Un espace avant le mot, sauf en début de texte, après un espace ou une parenthèse ouvrante.
        if let last = before.last, !last.isWhitespace, !"([{«“\"'’-/".contains(last) {
            input?.kbInsert(" ")
            before += " "
        }
        let capital = shift != .off
        if capital { word = word.prefix(1).uppercased() + word.dropFirst() }
        if suggest.language.hasPrefix("en"), word == "i" || word.hasPrefix("i’") { word = "I" + word.dropFirst() }
        // Verrouillage des majuscules : tout le mot à l'écran, comme chez Apple (le mot appris reste normal).
        let shown = shift == .caps ? word.uppercased() : word
        input?.kbInsert(shown)
        glidedWord = shown
        lastCorrection = nil
        wordTouches.removeAll()
        if recording == nil { KBStatsRecorder.shared.glide() }
        if shift == .on { shift = .off; autoShifted = false; updateLabels() }
        let prev = KBSuggest.lastWord(before)
        let start = KBSuggest.atSentenceStart(before + "x", word: "x")
        suggestQueue.async { KBWordStore.shared.commit(word, after: start ? nil : prev) }
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
        // Les autres mots possibles dans la barre : un toucher remplace le mot tracé.
        let locked = shift == .caps
        let others = found.dropFirst().map { w -> String in locked ? w.uppercased() : capital ? w.prefix(1).uppercased() + w.dropFirst() : w }
        suggestGen += 1
        cachedFix = nil
        applySuggestions(Array(others.prefix(3)), nil)
    }

    /// Le pavé tactile : les lettres s'effacent, et le doigt déplace le curseur partout dans le texte.
    private func enterTrackpad(_ tr: Track, at p: CGPoint) {
        if tr.typed != nil { input?.kbDelete(); tr.typed = nil }
        tr.cursorMode = true
        // Une ligne de texte compte environ un caractère tous les 8,4 pt, marges du champ en moins.
        trackMap = TrackMap(before: input?.kbTextBefore() ?? "", after: input?.kbTextAfter() ?? "",
                            perLine: max(24, Int((bounds.width - 48) / 8.4)))
        tr.lastX = p.x
        tr.lastY = p.y
        tr.lastT = 0
        tr.cursorAccum = 0
        tr.cursorAccumY = 0
        tr.cursorSpeed = 0
        tr.lastAnchor = 0
        hideBubble()
        setTrackpad(true)
        KBFeedback.shared.tap(sound: .off, haptics: max(0.5, eff.haptics))
        startTrackEdge(tr)
    }

    /// Le doigt posé tout en bas du pavé : le curseur continue de descendre, ligne après ligne, comme on continue
    /// de faire défiler au bord d'une page.
    private var trackEdgeTimer: Timer?
    private func startTrackEdge(_ tr: Track) {
        trackEdgeTimer?.invalidate()
        trackEdgeTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self, weak tr] timer in
            guard let self, let tr, tr.cursorMode, !tr.done else { timer.invalidate(); return }
            guard !tr.reanchoring, var map = self.trackMap else { return }
            // Seulement au tout dernier bord, après être descendu exprès (un pouce au repos ne bouge rien).
            let bottom = tr.lastY > self.bounds.height - 12 && tr.lastY > tr.start.y + 18
            let top = false
            guard bottom || top else { return }
            let start = map.current
            if map.moveV(bottom ? 1 : -1) {
                self.trackMap = map
                let d = map.current - start
                if d != 0 { self.input?.kbMoveCursor(d); KBFeedback.shared.tap(sound: .off, haptics: self.eff.haptics * 0.3) }
            } else {
                // Au bout du texte connu : on relit autour du curseur (iOS n'en donne que quelques lignes).
                let goal = map.goalCol, perLine = map.perLine
                self.input?.kbMoveCursor(bottom ? (map.paras[map.para].len - map.off + 1) : -(map.off + 1))
                tr.reanchoring = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak tr] in
                    guard let self, let tr, tr.cursorMode else { return }
                    var m = TrackMap(before: self.input?.kbTextBefore() ?? "", after: self.input?.kbTextAfter() ?? "", perLine: perLine)
                    m.goalCol = goal
                    self.trackMap = m
                    tr.reanchoring = false
                }
            }
        }
    }

    /// Le pavé tactile est affiché (touches sans lettres, barre du haut effacée).
    private var trackpadOn = false

    private func setTrackpad(_ on: Bool, animated: Bool = true) {
        trackGoalCol = nil
        if !on { trackEdgeTimer?.invalidate(); trackEdgeTimer = nil }
        if !on { trackMap = nil }
        guard on != trackpadOn || !on else { return }
        trackpadOn = on
        let bar: [UIView] = [chips, modeButton, flipButton, middleButton, bigButton, globeButton, emojiButton, micButton,
                             clipButton, adjustButton, hideButton, moreButton, fixButton, translateButton]
        let keys = cells.map(\.view)
        let parked = keyPool
        let apply = {
            // Comme chez Apple : la barre du haut disparaît aussi, il ne reste que le pavé.
            for v in bar { v.alpha = on ? 0 : 1 }
            self.layoutSwitch.alpha = on || self.layoutSwitch.isHidden ? 0 : 1
            for v in keys {
                v.label.alpha = on ? 0 : 1
                v.icon.alpha = on ? 0 : 1
                v.alpha = on ? 0.55 : 1
            }
            // Les touches rangées (autre page, autre disposition) reviennent toujours entières.
            if !on { for v in parked { v.alpha = 1; v.showGlyphs() } }
        }
        if animated { UIView.animate(withDuration: 0.18, animations: apply) } else { UIView.performWithoutAnimation(apply) }
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
        prevKeyTime = lastKeyTime
        lastKeyTime = ProcessInfo.processInfo.systemUptime
        if barOpened { barOpened = false; layoutTopBar() }
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
                guard let self, let tr, !tr.done, !tr.cursorMode, !tr.swipe, self.holds(tr) else { return }
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
                    guard let self, let tr, !tr.done, tr.index < self.cells.count, self.holds(tr) else { return }
                    tr.accents = options.map { upper ? $0.uppercased() : $0 }
                    tr.accentIndex = 0
                    self.hideBubble()
                    self.showAccents(tr.accents, over: self.cells[tr.index].frame)
                }
            }
            // La lettre s'écrit dès que le doigt se pose : c'est ce qui rend la frappe immédiate.
            tr.typed = text
            tr.shiftAtDown = shift
            tr.autoShiftAtDown = autoShifted
            typeText(text)
            noteTouch(text, at: tr.start)
        case .backspace:
            dictatedTail = nil
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
                guard let self, let tr, self.holds(tr) else { return }
                var count = 0
                tr.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self, weak tr] timer in
                    // Le doigt a quitté l'écran (ou le clavier) sans qu'iOS le dise : on n'efface plus rien.
                    guard let self, let tr, self.holds(tr) else { timer.invalidate(); return }
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

    /// Le doigt de cet appui est-il encore posé sur le clavier affiché ?
    private func holds(_ tr: Track) -> Bool {
        guard visible, window != nil, let t = tr.touch, tracks[t] === tr else { return false }
        return t.phase != .ended && t.phase != .cancelled
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
            if !tr.cursorMode && tr.typed == nil {
                if tr.index < cells.count { learnSpace(at: tr.start, frame: cells[tr.index].frame) }
                typeSpace()
            }
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
            globeTapped()
        case .emoji:
            emojiQuery = nil
            showEmoji = true
            builtFor = .zero
            rebuild()
        case .mic:
            // Option « tenir pour dicter » : un effleurement en écrivant ne lance plus la dictée par erreur.
            let held = ProcessInfo.processInfo.systemUptime - tr.t0 >= 0.3
            // En pleine frappe (une touche moins de 0,7 s avant), un effleurement du micro est une erreur : le pouce
            // visait espace ou retour. On ne lance pas la dictée (le tenir un instant la lance quand même).
            let midTyping = tr.t0 - prevKeyTime < 0.7
            if dictState == .idle, !held, eff.micHold || midTyping {
                // Le rappel « Maintiens le micro » : les trois premières fois seulement (il gênait à chaque
                // effleurement du micro).
                let seen = UserDefaults.standard.integer(forKey: "foldboard.micHoldHint")
                if eff.micHold, eff.micHoldHint, seen < 3 {
                    UserDefaults.standard.set(seen + 1, forKey: "foldboard.micHoldHint")
                    flash(L("Hold the mic to dictate"))
                }
            } else {
                micTapped()
            }
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
        if recording == nil, text.count == 1, text.first?.isLetter == true {
            let m = layoutMode
            KBStatsRecorder.shared.letter(hand: m == .split || m == .full ? 2 : (isRight ? 1 : 0))
        }
        // Après un mot écrit en glissant, la lettre suivante commence un nouveau mot : l'espace d'abord.
        if let g = glidedWord {
            glidedWord = nil
            if let c = text.first, c.isLetter || c.isNumber, (input?.kbTextBefore() ?? "").hasSuffix(g) { input?.kbInsert(" ") }
        }
        // Pareil juste après une dictée.
        if let tail = dictatedTail {
            dictatedTail = nil
            if let c = text.first, c.isLetter || c.isNumber, (input?.kbTextBefore() ?? "").hasSuffix(tail) { input?.kbInsert(" ") }
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
        dictatedTail = nil
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
        for e in (q.isEmpty ? [] : KBEmoji.search(q)).prefix(24) {
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
        let wasGlide = glidedWord != nil && glidedWord == typed0
        defer {
            if !typed0.isEmpty, let final = KBSuggest.lastWord(input?.kbTextBefore() ?? "") {
                if recording == nil, !wasGlide { KBStatsRecorder.shared.word() }
                let prev = KBSuggest.previousWord(before0, word: typed0)
                let sentenceStart = KBSuggest.atSentenceStart(before0, word: typed0)
                // Seulement un vrai mot : une faute laissée telle quelle ne doit pas devenir « un de tes mots »
                // (au bout de trois fois, elle n'était plus jamais corrigée).
                suggestQueue.async { [bgSuggest] in
                    if bgSuggest.isReal(final) { KBWordStore.shared.commit(final, after: sentenceStart ? nil : prev) }
                }
            }
        }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        // Tes remplacements de texte (Réglages > Général > Clavier) : appliqués même sans correction automatique,
        // comme sur le clavier d'Apple.
        // Le raccourci peut contenir des chiffres ou des signes (« @@ », « adr1 ») : tout ce qui suit la dernière espace.
        let token = String(before.reversed().prefix { !$0.isWhitespace }.reversed())
        if !token.isEmpty, let r0 = suggest.replacement(for: token), r0 != token {
            let r = Self.keepCapital(r0, like: token)
            wordTouches.removeAll()
            for _ in 0..<token.count { input?.kbDelete() }
            input?.kbInsert(r)
            lastCorrection = (token, r, sep)
            return
        }
        if !eff.autocorrect, !word.isEmpty, let r0 = suggest.replacement(for: word), r0 != word {
            let r = Self.keepCapital(r0, like: word)
            wordTouches.removeAll()
            for _ in 0..<word.count { input?.kbDelete() }
            input?.kbInsert(r)
            lastCorrection = (word, r, sep)
            return
        }
        // AZERTY : l'apostrophe à la place du n (« ma’que » → « manque »).
        if eff.autocorrect, let r = suggest.apostropheTypo(token), r != token {
            wordTouches.removeAll()
            replaceTail(token, with: r)
            lastCorrection = (token, r, sep)
            return
        }
        guard eff.autocorrect, page == .letters || sep != " " else { return }
        let known: String?? = cachedFix?.word == word ? .some(cachedFix?.fix) : nil
        // La correction préparée en arrière-plan si elle est prête, sinon on la calcule (quelques ms : la mesure
        // de fluidité montre que le clavier a toute la marge).
        var computed: String? = known ?? suggest.correction(for: word, before: before, touch: touchModel(for: word), fast: true)
        // Rien de sûr, mais la barre montre un vrai mot pour ce mot qui n'existe pas : on le prend (comme le clavier
        // d'Apple, qui corrige vers la proposition du milieu).
        if computed == nil, suggestionsWord == word, suggestionItems.count > 1 {
            computed = suggest.barFix(word, items: Array(suggestionItems.dropFirst()), before: before)
        }
        // La majuscule du début de phrase reste : « Hâte » ne redevient jamais « hâte ».
        if let c = computed { computed = Self.keepCapital(c, like: word) }
        guard !word.isEmpty, let fix = computed, fix != word else {
            lastCorrection = nil
            if sep == " " { learnTaps(word) }
            wordTouches.removeAll()
            return
        }
        wordTouches.removeAll()
        replaceTail(word, with: fix)
        lastCorrection = (word, fix, sep)
        if recording == nil { KBStatsRecorder.shared.correction() }
    }

    /// Remplacer le mot juste avant le curseur en n'effaçant que ce qui change (« lettees » → « lettres » : on efface
    /// « ees » et on écrit « res »). iOS ne laisse pas un clavier remplacer un mot d'un coup : moins d'effacements,
    /// c'est un mot qui tressaute beaucoup moins.
    private func replaceTail(_ old: String, with new: String) {
        let a = Array(old), b = Array(new)
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        for _ in 0..<(a.count - p) { input?.kbDelete() }
        if p < b.count { input?.kbInsert(String(b[p...])) }
    }

    /// Le mot tapé commence par une majuscule : la correction aussi.
    static func keepCapital(_ fix: String, like word: String) -> String {
        // Une marque s'écrit toujours comme elle (« iPhone » reste « iPhone » en début de phrase).
        if KBSuggest.brands[fix.lowercased()] == fix { return fix }
        // Tapé TOUT EN CAPITALES (« IM ») : la correction aussi (« I’M »), comme le clavier d'Apple.
        if word.count > 1, word == word.uppercased(), word != word.lowercased() { return fix.uppercased() }
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
        // Le mot gardé va dans « Mes mots » (visible et modifiable dans l'app) : il ne sera plus jamais corrigé.
        // En début de phrase, la majuscule vient de la phrase, pas du mot : on le garde en minuscules.
        let stem = String(before.dropLast(lc.corrected.count + lc.sep.count))
        let onlyFirstCap = w0.dropFirst() == w0.dropFirst().lowercased()
        let keep = onlyFirstCap && KBSuggest.atSentenceStart(stem + w0, word: w0) ? w0.lowercased() : w0
        // Pas quand la correction ne changeait que la majuscule (« i » → « I », un prénom) : ce n'est pas un mot à garder.
        let caseOnly = lc.corrected.lowercased() == lc.original.lowercased()
        // La première annulation ne fait que s'en souvenir : le mot n'entre dans « Mes mots » qu'à la deuxième.
        if !caseOnly, w0.count >= 2, w0.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" }), settings.learnOnUndo {
            let added = settings.undidCorrection(keep)
            persist()
            if added {
                suggest.setMyWords(settings.activeMyWords)
                let mine = settings.activeMyWords
                suggestQueue.async { [bgSuggest] in bgSuggest.setMyWords(mine) }
            }
        }
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
        // Un mot corrigé au milieu d'une phrase déjà écrite : l'espace qui suit est déjà là, on n'en ajoute pas.
        let after = input?.kbTextAfter() ?? ""
        let spaceFollows = after.first.map { $0 == " " || $0 == "\n" || ".,;:!?)".contains($0) } ?? false
        replaceTail(word, with: item + (spaceFollows ? "" : " "))
        if spaceFollows, after.first == " " { input?.kbMoveCursor(1) }
        glidedWord = nil
        lastCorrection = nil
        wordTouches.removeAll()
        let prev = word.isEmpty ? KBSuggest.lastWord(before) : KBSuggest.previousWord(before, word: word)
        let start = KBSuggest.atSentenceStart(before + (word.isEmpty ? "x" : ""), word: word.isEmpty ? "x" : word)
        if !item.contains(" ") { suggestQueue.async { KBWordStore.shared.commit(item, after: start ? nil : prev) } }
        refreshSuggestionsSoon()
        refreshShiftSoon()
    }

    /// L'emoji du mot en cours (`replace` : on remplace le mot), ou du mot qu'on vient de finir (on ajoute l'emoji).
    private func suggestionEmoji() -> (es: [String], replace: Bool)? {
        guard eff.emojiSuggest, page == .letters else { return nil }
        let before = input?.kbTextBefore() ?? ""
        let word = KBSuggest.currentWord(before)
        // Deux mots (« mind blown », « puerto rico ») : l'emoji de l'expression.
        func pairEmojis(_ w: String, _ prev: String?) -> [String] {
            if let p = prev?.lowercased() {
                switch (p, w.lowercased()) {
                case ("mind", "blown"), ("mind", "blowing"): return ["🤯"]
                case ("puerto", "rico"): return ["🇵🇷"]
                case ("hong", "kong"): return ["🇭🇰"]
                default: break
                }
            }
            return KBEmojiSuggest.emojis(for: w)
        }
        if !word.isEmpty {
            let es = pairEmojis(word, KBSuggest.previousWord(before, word: word))
            return es.isEmpty ? nil : (es, true)
        }
        guard before.hasSuffix(" ") else { return nil }
        guard let last = KBSuggest.lastWord(before) else { return nil }
        let es = pairEmojis(last, KBSuggest.previousWord(String(before.dropLast()), word: last))
        return es.isEmpty ? nil : (es, false)
    }

    /// Comme le clavier d'Apple : l'emoji remplace le mot en cours ; après une espace, il s'ajoute.
    private func applyEmojiSuggestion(_ s: (e: String, replace: Bool)) {
        KBFeedback.shared.tap(sound: eff.sound, haptics: eff.haptics)
        if s.replace {
            let word = KBSuggest.currentWord(input?.kbTextBefore() ?? "")
            for _ in 0..<word.count { input?.kbDelete() }
        }
        input?.kbInsert(s.e + " ")
        KBEmoji.used(s.e)
        glidedWord = nil
        lastCorrection = nil
        wordTouches.removeAll()
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
                    // Verrouillage des majuscules : les mots proposés aussi en capitales.
                    self.applySuggestions(self.shift == .caps ? items.map { $0.uppercased() } : items, nil)
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
                self.suggestionsWord = word
                // Les mots proposés s'affichent comme ils seront écrits (« SLEE » → « SLEEPING », pas « sleeping »).
                self.applySuggestions(items.map { Self.keepCapital($0, like: word) }, auto ? best : nil)
            }
        }
    }

    private func applySuggestions(_ items: [String], _ best: Int?) {
        guard items != suggestionItems || best != suggestionBest else { return }
        let wasEmpty = suggestionItems.isEmpty
        suggestionItems = items
        suggestionBest = best
        // Les boutons se rangent ou reviennent quand les suggestions apparaissent ou s'en vont.
        if eff.compactBar, wasEmpty != items.isEmpty { layoutTopBar() } else { rebuildChips() }
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

    /// Panneau du « … », créé une fois. Le menu système ne s'affiche pas dans les autres apps.
    private var barSheet: KBBarSheet?

    func toggleBarSheet() {
        let sheet = barSheet ?? KBBarSheet()
        barSheet = sheet
        if sheet.superview !== self { addSubview(sheet) }
        if sheet.isHidden || sheet.alpha == 0 {
            sheet.alpha = 1
            sheet.isHidden = false
            sheet.frame = bounds
            sheet.reload(self)
            bringSubviewToFront(sheet)
        } else {
            sheet.isHidden = true
        }
    }

    func barSheetPick(_ id: String) {
        switch id {
        case "layout-0": chooseOpenLayout(0)
        case "layout-1": chooseOpenLayout(1)
        case "layout-2": chooseOpenLayout(2)
        case "hand": settings.showHandButton.toggle()
        case "settings": settings.showSettingsButton.toggle()
        case "mic": settings.showMicButton.toggle()
        case "clip": settings.showClipboardButton.toggle()
        case "hide": settings.hideKeyButton.toggle()
        case "swap": settings.showSwapButton.toggle()
        case "center": settings.showCenterButton.toggle()
        case "menu": settings.showLayoutMenu.toggle()
        case "switch": settings.showLayoutSwitch.toggle()
        case "more": settings.showMoreButton.toggle()
        case "app":
            barSheet?.isHidden = true
            openContainingApp(URL(string: "foldboard://settings")!)
            return
        case "close":
            barSheet?.isHidden = true
            return
        default: return
        }
        if id.hasPrefix("layout-") { barSheet?.isHidden = true }
        eff = settings.effective(pro: pro)
        save()
        setNeedsLayout()
        layoutIfNeeded()
        if barSheet?.isHidden == false { barSheet?.reload(self) }
    }

    func barSheetRows() -> [(id: String, title: String, check: Bool)] {
        let now = openLayoutChoice
        return [
            ("layout-0", L("Follows your hand"), now == 0),
            ("layout-1", L("Full width"), now == 1),
            ("layout-2", L("Split keyboard"), now == 2),
            ("hand", L("Position button"), settings.showHandButton),
            ("settings", L("Settings button"), settings.showSettingsButton),
            ("mic", L("Mic button"), settings.showMicButton),
            ("clip", L("Clipboard button"), settings.showClipboardButton),
            ("hide", L("Hide keyboard button"), settings.hideKeyButton),
            ("switch", L("Layout switcher"), settings.showLayoutSwitch),
            ("app", L("Open Foldboard settings"), false),
            ("close", L("Done"), false),
        ]
    }

    /// Le « … » n'utilise pas le menu système, le panneau s'ouvre, un choix change la disposition,
    /// et un lien part par la chaîne des répondeurs (pas par UIApplication.shared.open).
    static func verifyBarSheet() -> Bool {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 980, height: 420))
        let c = install(in: host)
        NSLayoutConstraint.deactivate(c.hostPins)
        c.hostPins.removeAll()
        c.translatesAutoresizingMaskIntoConstraints = true
        c.frame = CGRect(x: 0, y: 0, width: 980, height: 360)
        var s = KBSettings()
        s.layout = .azerty
        s.mode = .right
        s.layoutSwitchOpenOnly = false
        c.demoContext = "open-landscape"
        c.configure(settings: s, pro: true)
        c.builtFor = .zero
        c.layoutIfNeeded()
        let noSystemMenu = c.bigButton.menu == nil && c.bigButton.showsMenuAsPrimaryAction == false
        c.toggleBarSheet()
        let open = c.barSheet?.isHidden == false
        c.barSheetPick("layout-2")
        let split = c.settings.screenModes["open-landscape"] == .split
        let closed = c.barSheet?.isHidden != false
        c.barSheetPick("switch")
        let switched = c.settings.showLayoutSwitch == false
        final class Probe: UIResponder {
            var url: URL?
            @objc func openURL(_ url: URL) { self.url = url }
        }
        final class Start: UIResponder {
            var nxt: UIResponder?
            override var next: UIResponder? { nxt }
        }
        let probe = Probe()
        let start = Start()
        start.nxt = probe
        let url = URL(string: "foldboard://settings")!
        let delivered = deliver(url, from: start) && probe.url == url
        let ok = noSystemMenu && open && split && closed && switched && delivered
        print("RESULT barsheet menu=\(noSystemMenu) open=\(open) split=\(split) closed=\(closed) switch=\(switched) url=\(delivered) \(ok ? "yes" : "no")")
        return ok
    }

    /// Passage en mode portable : les touches ne glissent pas, les rangées restent alignées,
    /// et plusieurs angles de charnière ne font qu'une seule mise en page.
    static func verifyLaptopLayout() -> Bool {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 980, height: 500))
        let c = install(in: host)
        NSLayoutConstraint.deactivate(c.hostPins)
        c.hostPins.removeAll()
        c.translatesAutoresizingMaskIntoConstraints = true
        c.frame = CGRect(x: 0, y: 0, width: 980, height: 260)
        var s = KBSettings()
        s.layout = .azerty
        s.mode = .split
        c.demoContext = "open-landscape"
        c.configure(settings: s, pro: true)
        c.hingeHalf = false
        c.hingeSettling = false
        c.builtFor = .zero
        c.layoutIfNeeded()
        var dirty = false
        UIView.animate(withDuration: 0.45) {
            c.frame = CGRect(x: 0, y: 0, width: 980, height: 420)
            c.hingeHalf = true
            c.builtFor = .zero
            c.layoutIfNeeded()
            for cell in c.cells {
                if cell.view.transform != .identity { dirty = true }
                if !(cell.view.layer.animationKeys() ?? []).isEmpty { dirty = true }
            }
        }
        var rows: [CGFloat: Int] = [:]
        for cell in c.cells {
            let y = cell.frame.minY.rounded()
            rows[y, default: 0] += 1
        }
        let aligned = rows.values.contains { $0 >= 4 }
        let before = c.hingeApplies
        for i in 0..<8 { c.scheduleHinge(closed: false, half: i % 2 == 0) }
        let held = c.hingeApplies == before && c.hingeSettling
        c.hingeTicket += 1
        c.pendingHingeHalf = true
        c.pendingHingeClosed = false
        c.applyScheduledHinge()
        let once = c.hingeApplies == before + 1 && c.hingeHalf
        let ok = !dirty && aligned && held && once
        print("RESULT laptop anim=\(!dirty) aligned=\(aligned) held=\(held) once=\(once) \(ok ? "yes" : "no")")
        return ok
    }

    private func highlightAccent(_ i: Int) {
        for (j, l) in accentLabels.enumerated() {
            l.backgroundColor = j == i ? theme.accent : .clear
            l.textColor = j == i ? .white : theme.text
        }
    }
}

/// Le menu du « … », dessiné dans le clavier. Les boutons existent une fois : on ne fait que réécrire leurs titres.
final class KBBarSheet: UIView {
    weak var canvas: KeyboardCanvas?
    private let dim = UIButton(type: .custom)
    private let card = UIView()
    private let stack = UIStackView()
    private var rows: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        dim.addAction(UIAction { [weak self] _ in self?.canvas?.barSheetPick("close") }, for: .touchUpInside)
        addSubview(dim)
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        addSubview(card)
        stack.axis = .vertical
        stack.spacing = 0
        card.addSubview(stack)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = bounds
        let h = min(bounds.height - 8, stack.systemLayoutSizeFitting(CGSize(width: bounds.width - 24, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height + 8)
        card.frame = CGRect(x: 8, y: 8, width: bounds.width - 16, height: max(44, h))
        stack.frame = card.bounds.insetBy(dx: 4, dy: 4)
    }

    func reload(_ canvas: KeyboardCanvas) {
        self.canvas = canvas
        card.backgroundColor = .systemBackground
        let items = canvas.barSheetRows()
        while rows.count < items.count {
            let b = UIButton(type: .system)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            b.contentHorizontalAlignment = .leading
            b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            b.addAction(UIAction { [weak self, weak b] _ in
                guard let id = b?.accessibilityIdentifier else { return }
                self?.canvas?.barSheetPick(id)
            }, for: .touchUpInside)
            rows.append(b)
        }
        for (i, item) in items.enumerated() {
            let b = rows[i]
            b.accessibilityIdentifier = item.id
            let mark = item.check ? "✓  " : ""
            b.setTitle(mark + item.title, for: .normal)
            b.isHidden = false
            if b.superview == nil { stack.addArrangedSubview(b) }
        }
        for b in rows.dropFirst(items.count) {
            b.isHidden = true
            b.removeFromSuperview()
        }
        setNeedsLayout()
    }
}

/// Cible d'un CADisplayLink qui ne retient pas le clavier (un CADisplayLink garde sa cible tant qu'il tourne).
private final class KBWeakTarget: NSObject {
    weak var canvas: KeyboardCanvas?
    init(_ c: KeyboardCanvas) { canvas = c }
    @objc func tick(_ l: CADisplayLink) {
        guard let c = canvas else { l.invalidate(); return }
        c.perfTick(l)
    }
    @objc func grip(_ g: UILongPressGestureRecognizer) { canvas?.showGripInfo(g) }
    @objc func perf(_ g: UILongPressGestureRecognizer) { canvas?.showPerf(g) }
}


/// La cible du bouton « Coller » du système : il donne le texte copié sans demande d'autorisation.
final class KBPasteTarget: UIView {
    var onText: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func paste(itemProviders: [NSItemProvider]) {
        for p in itemProviders where p.canLoadObject(ofClass: NSString.self) {
            _ = p.loadObject(ofClass: NSString.self) { [weak self] obj, _ in
                guard let s = obj as? String, !s.isEmpty else { return }
                DispatchQueue.main.async { self?.onText?(s) }
            }
            return
        }
    }
}
