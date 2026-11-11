import StoreKit
import UIKit

/// L'extension clavier : elle affiche le clavier Foldboard et écrit dans le champ de texte.
final class KeyboardViewController: UIInputViewController, KBInput {
    private let canvas = KeyboardCanvas()
    private var heightConstraint: NSLayoutConstraint?
    private var settings = KBSettings()
    private var access = KBAccess()

    override func viewDidLoad() {
        super.viewDidLoad()
        canvas.input = self
        canvas.onPreferredHeightChange = { [weak self] in
            guard let self else { return }
            self.heightConstraint?.constant = self.canvas.preferredHeight
        }
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reload()
        requestSupplementaryLexicon { [weak self] lexicon in self?.canvas.setLexicon(lexicon) }
        Task { await checkStore() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        canvas.appeared()
        if !access.isPro() { Task { await checkStore() } }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        undelayTouches()
        // Certains gestes du système s'installent un peu après l'apparition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.undelayTouches() }
        showTrialOver()
    }

    /// L'essai est fini : le clavier ne suit plus la main. On le dit clairement, les 3 premières fois.
    private func showTrialOver() {
        guard access.trialOver() else { return }
        let key = "foldboard.trialOverShown"
        let shown = UserDefaults.standard.integer(forKey: key)
        guard shown < 3 else { return }
        UserDefaults.standard.set(shown + 1, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.canvas.notice(L("Trial over: open Foldboard to unlock Pro"))
        }
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        canvas.disappeared()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        canvas.textChanged()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        canvas.textChanged()
    }

    private func reload() {
        settings = KBVault.loadSettings()
        access = KBVault.loadAccess()
        canvas.configure(settings: settings, pro: access.isPro())
        let h = canvas.preferredHeight
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
        if stored.isPro() && !access.isPro() {
            await MainActor.run {
                self.access = stored
                self.canvas.configure(settings: self.settings, pro: true)
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
                self.canvas.configure(settings: self.settings, pro: pro)
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
        heightConstraint?.constant = canvas.preferredHeight
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
