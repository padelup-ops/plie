import StoreKit
import UIKit

/// L'extension clavier : elle affiche le clavier Foldboard et écrit dans le champ de texte.
final class KeyboardViewController: UIInputViewController, KBInput {
    /// Le clavier affiché. Créé à l'apparition et rendu dès que le clavier n'est plus à l'écran : iOS garde parfois
    /// de vieux contrôleurs de clavier en vie (des dizaines, vus sur le Duo : plus de 130 Mo), ils ne gardent ainsi
    /// presque plus rien en mémoire.
    private var canvas: KeyboardCanvas?
    private var lexicon: UILexicon?
    private var heightConstraint: NSLayoutConstraint?
    private var settings = KBSettings()
    private var access = KBAccess()

    @discardableResult
    private func ensureCanvas() -> KeyboardCanvas {
        if let c = canvas { return c }
        let c = KeyboardCanvas()
        c.input = self
        c.onPreferredHeightChange = { [weak self] in
            guard let self, let c = self.canvas else { return }
            self.heightConstraint?.constant = c.preferredHeight
        }
        c.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(c)
        NSLayoutConstraint.activate([
            c.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            c.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            c.topAnchor.constraint(equalTo: view.topAnchor),
            c.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        canvas = c
        if let lexicon { c.setLexicon(lexicon) }
        return c
    }

    /// Le clavier n'est plus à l'écran depuis un moment : on rend tout (le contrôleur peut rester en vie, vide).
    private func releaseCanvasIfGone() {
        guard view.window == nil, let c = canvas else { return }
        c.shutdown()
        c.removeFromSuperview()
        canvas = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ensureCanvas()
        reload()
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.lexicon = lexicon
            self?.canvas?.setLexicon(lexicon)
        }
        Task { [weak self] in await self?.checkStore() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ensureCanvas()
        reload()
        canvas?.appeared()
        if !access.isPro() { Task { [weak self] in await self?.checkStore() } }
    }

    /// Filet de sécurité : le clavier revient à l'écran sans « apparition » d'iOS (il avait été rendu).
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if canvas == nil, view.window != nil {
            ensureCanvas()
            reload()
            canvas?.appeared()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        undelayTouches()
        // Certains gestes du système s'installent un peu après l'apparition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.undelayTouches() }
        if !showTrialOver() { showUpdateNotice() }
    }

    /// Une version plus récente est sur l'App Store (l'app l'a vu) : on le dit deux fois au plus, par version.
    /// Le clavier ne va jamais sur internet : il lit seulement ce que l'app a noté.
    private func showUpdateNotice() {
        guard let v = KBVersion.updateAvailable else { return }
        let key = "foldboard.updateNotice." + v
        let shown = UserDefaults.standard.integer(forKey: key)
        guard shown < 2 else { return }
        UserDefaults.standard.set(shown + 1, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.canvas?.notice(L("New version of Foldboard: update it in the App Store"))
        }
    }

    /// L'essai est fini : le clavier ne suit plus la main. On le dit clairement, les 3 premières fois.
    @discardableResult
    private func showTrialOver() -> Bool {
        guard access.trialOver() else { return false }
        let key = "foldboard.trialOverShown"
        let shown = UserDefaults.standard.integer(forKey: key)
        guard shown < 3 else { return false }
        UserDefaults.standard.set(shown + 1, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.canvas?.notice(L("Trial over: open Foldboard to unlock Pro"))
        }
        return true
    }

    /// iOS retient les appuis rapides (il attend de voir si c'est un de ses gestes) et en avale certains :
    /// des lettres manquaient en tapant vite. Les appuis arrivent maintenant tout de suite au clavier, qui écrit
    /// la lettre dès que le doigt se pose : même si iOS reprend l'appui ensuite, la lettre est écrite.
    private func undelayTouches() {
        var v: UIView? = view
        while let cur = v {
            cur.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
            v = cur.superview
        }
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        canvas?.trimMemory()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        canvas?.disappeared()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Un peu plus tard, si le clavier n'est vraiment plus à l'écran, on le rend (iOS envoie parfois ce message
        // alors que le clavier reste affiché : dans ce cas on n'y touche pas).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.releaseCanvasIfGone() }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        canvas?.textChanged()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        canvas?.textChanged()
    }

    private func reload() {
        settings = KBVault.loadSettings()
        access = KBVault.loadAccess()
        let c = ensureCanvas()
        c.configure(settings: settings, pro: access.isPro())
        let h = c.preferredHeight
        if let c = heightConstraint {
            c.constant = h
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: h)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    /// Si l'app n'a pas pu partager l'accès (trousseau), le clavier regarde lui-même les achats.
    @discardableResult
    private func checkStore() async -> Bool {
        // L'app a peut-être débloqué Pro depuis : on relit d'abord le coffre.
        let stored = KBVault.loadAccess()
        // Version de test : fin d'essai simulée depuis l'app, on ne regarde pas les vrais achats.
        if stored.simulated == true { return stored.isPro() }
        if stored.isPro() && !access.isPro() {
            await MainActor.run {
                self.access = stored
                self.canvas?.configure(settings: self.settings, pro: true)
            }
            return true
        }
        guard !access.isPro() else { return true }
        var found = access
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == KBProducts.pro { found.purchased = true }
            if t.productID == KBProducts.trial {
                found.trialStart = min(found.trialStart ?? t.originalPurchaseDate, t.originalPurchaseDate)
            }
        }
        let pro = found.isPro()
        if found.purchased != access.purchased || found.trialStart != access.trialStart {
            await MainActor.run {
                self.access = found
                KBVault.save(found)
                self.canvas?.configure(settings: self.settings, pro: pro)
            }
        }
        return pro
    }

    // MARK: KBInput

    func kbInsert(_ text: String) { textDocumentProxy.insertText(text) }
    func kbDelete() { textDocumentProxy.deleteBackward() }
    func kbMoveCursor(_ offset: Int) { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset) }
    func kbTextBefore() -> String? { textDocumentProxy.documentContextBeforeInput }
    func kbTextAfter() -> String? { textDocumentProxy.documentContextAfterInput }
    func kbNextKeyboard() { advanceToNextInputMode() }
    func kbDismiss() { dismissKeyboard() }
    func kbSettingsChanged(_ settings: KBSettings) {
        self.settings = settings
        KBVault.save(settings)
        if let c = canvas { heightConstraint?.constant = c.preferredHeight }
    }
    var kbNeedsGlobe: Bool { needsInputModeSwitchKey }
    var kbFullAccess: Bool { hasFullAccess }
    func kbRecheckPro(_ done: @escaping (Bool) -> Void) {
        Task {
            let ok = await checkStore()
            await MainActor.run { done(ok) }
        }
    }
}
