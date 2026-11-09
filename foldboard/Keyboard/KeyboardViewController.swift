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
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reload()
        Task { await checkStore() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        canvas.appeared()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        canvas.disappeared()
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
    private func checkStore() async {
        guard !access.isPro() else { return }
        var found = access
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == KBProducts.pro { found.purchased = true }
            if t.productID == KBProducts.trial {
                found.trialStart = min(found.trialStart ?? t.originalPurchaseDate, t.originalPurchaseDate)
            }
        }
        if found.purchased != access.purchased || found.trialStart != access.trialStart {
            let pro = found.isPro()
            await MainActor.run {
                self.access = found
                KBVault.save(found)
                self.canvas.configure(settings: self.settings, pro: pro)
            }
        }
    }

    // MARK: KBInput

    func kbInsert(_ text: String) { textDocumentProxy.insertText(text) }
    func kbDelete() { textDocumentProxy.deleteBackward() }
    func kbMoveCursor(_ offset: Int) { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset) }
    func kbTextBefore() -> String? { textDocumentProxy.documentContextBeforeInput }
    func kbNextKeyboard() { advanceToNextInputMode() }
    func kbDismiss() { dismissKeyboard() }
    func kbSettingsChanged(_ settings: KBSettings) {
        self.settings = settings
        KBVault.save(settings)
        heightConstraint?.constant = canvas.preferredHeight
    }
    var kbNeedsGlobe: Bool { needsInputModeSwitchKey }
    var kbFullAccess: Bool { hasFullAccess }
}
